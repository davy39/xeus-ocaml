(**
 * @file library_loader.ml
 * @brief Implements the logic for dynamically loading OCaml libraries.
 *
 * This module is responsible for handling the `#require` directive within the
 * toplevel. It fetches pre-compiled JavaScript bundles of OCaml libraries,
 * executes them, and verifies their successful integration by directly checking
 * for the creation of new .cmi files in the virtual filesystem.
 *)

open Js_of_ocaml
open Lwt.Syntax
open Util

(* Create a module for string sets for cleaner type annotations and usage. *)
module S = Set.Make(String)

(**
 * A helper function to pretty-print a string set for logging purposes.
 * @param log_prefix A string to prepend to the log message.
 * @param set The string set to be printed.
 *)
let log_set log_prefix set =
  let elements_str =
    if S.is_empty set then "[empty]" else String.concat ", " (S.elements set)
  in
  log (Printf.sprintf "%s: %s" log_prefix elements_str)
;;

(**
 * Gets the set of all `.cmi` filenames in a given directory of the virtual filesystem.
 * This is used to snapshot the state of the CMI directory before and after loading a library.
 *
 * @param path The directory path to scan (e.g., "/static/cmis").
 * @return A string set of `.cmi` filenames. Returns an empty set if the directory
 *         does not exist or an error occurs.
 *)
let get_cmis_in_dir (path : string) : S.t =
  try
    let files = Sys.readdir path |> Array.to_list in
    let cmis = List.filter (fun f -> Filename.check_suffix f ".cmi") files in
    S.of_list cmis
  with Sys_error _ ->
    (* Directory might not exist on the first check, which is fine. *)
    S.empty
;;

(**
 * Dynamically loads a compiled OCaml library from a URL.
 *
 * The success of the load is determined by checking for new `.cmi` files
 * in the `/static/cmis` directory after executing the fetched JavaScript bundle.
 *
 * @param base_url The base path where library .js files are stored.
 * @param name The name of the library (e.g., "ocamlgraph").
 * @return A result containing a success or error message.
 *)
let load ~base_url ~name : (Protocol.output, Protocol.output) result Lwt.t =
  log (Printf.sprintf "[Loader] Attempting to load library: '%s'" name);
  let url = Filename.concat base_url (name ^ ".js") in
  let* content_opt = Network.async_get url in

  match content_opt with
  | None ->
    let error_msg = Printf.sprintf "Error: Could not fetch library '%s' from %s\n" name url in
    log ("[Loader] FETCH FAILED: " ^ error_msg);
    Lwt.return (Error (Protocol.Stderr error_msg))

  | Some content ->
    (try
       let cmi_dir = "/static/cmis" in

       (* 1. Snapshot the filesystem state BEFORE loading. *)
       log (Printf.sprintf "[Loader] STEP 1: Capturing CMI files in %s BEFORE load." cmi_dir);
       let cmis_before = get_cmis_in_dir cmi_dir in
       log_set "[Loader] CMIs BEFORE" cmis_before;

       (* 2. Execute the fetched JavaScript. This should create new .cmi files in the VFS. *)
       log "[Loader] STEP 2: Executing library JavaScript bundle.";
       Js.Unsafe.eval_string content |> ignore;
       log "[Loader] JavaScript execution completed.";

       (* 3. Snapshot the filesystem state AFTER loading. *)
       log (Printf.sprintf "[Loader] STEP 3: Capturing CMI files in %s AFTER load." cmi_dir);
       let cmis_after = get_cmis_in_dir cmi_dir in
       log_set "[Loader] CMIs AFTER" cmis_after;

       (* 4. Calculate the set of newly created CMI files. *)
       let new_cmis = S.diff cmis_after cmis_before in
       log_set "[Loader] STEP 4: Calculated NEW CMI files" new_cmis;

       (* 5. IMPORTANT: Even though we check the filesystem for success, we still must
          tell the toplevel to rescan its paths so it can find the new modules for
          future execution. *)
       Topdirs.dir_directory cmi_dir;

       (* 6. Determine success based on whether new CMI files were created. *)
       if not (S.is_empty new_cmis) then (
         let new_module_names =
           new_cmis
           |> S.elements
           |> List.map (fun cmi_file ->
                (* Attempt to convert filename like "graph__" to a user-friendly "Graph" *)
                let base = Filename.chop_extension cmi_file in
                let cleaned = Str.global_replace (Str.regexp "__$") "" base in
                String.capitalize_ascii cleaned)
           |> String.concat ", "
         in
         let msg = Printf.sprintf "Library '%s' loaded. New modules available: %s" name new_module_names in
         log (Printf.sprintf "[Loader] SUCCESS: %s" msg);
         Lwt.return (Ok (Protocol.Stdout msg))
       ) else (
         let msg = Printf.sprintf "Error: Library '%s' was executed, but no new module interface (.cmi) files were found. The library might be empty, already loaded, or failed to install its files correctly." name in
         log (Printf.sprintf "[Loader] FAILURE: %s" msg);
         Lwt.return (Error (Protocol.Stderr msg))
       )
     with
     | exn ->
       let error_msg = Printf.sprintf "Error executing library '%s': %s" name (Printexc.to_string exn) in
       log (Printf.sprintf "[Loader] EXCEPTION during JS evaluation: %s" error_msg);
       Lwt.return (Error (Protocol.Stderr error_msg)))
;;