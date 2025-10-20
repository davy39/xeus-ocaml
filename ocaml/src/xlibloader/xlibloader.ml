(** {1 Library and Artifact Loader}
    @author Davy Cottet

    This module is responsible for loading all necessary files into the
    `js_of_ocaml` virtual filesystem (VFS). It handles three distinct loading
    phases:

    1. **Static Loading:** At build time, essential files (like `stdlib.cmi`)
    are embedded directly into the main kernel bundle. The {!setup} function
    writes these files to the VFS at startup.

    2. **Initial Dynamic Loading:** During kernel startup, the {!setup} function
    asynchronously fetches the remaining standard library artifacts (`.cmi`,
    `.cmt`, `.cmti`) from a specified base URL and writes them to the VFS. This
    ensures Merlin has full access to the standard library for completion and
    documentation.

    3. **On-Demand Dynamic Loading:** When a user issues a `#require "lib_name"`
    directive in a notebook, the {!load_on_demand} function is called. It
    fetches the pre-compiled JavaScript bundle and all associated Merlin
    artifacts for that specific library.

    This hybrid approach ensures a fast initial startup while providing
    comprehensive and extensible language support. *)

open Js_of_ocaml
open Lwt.Syntax
open Xutil
open Merlin_utils.Std

(** The designated path within the `js_of_ocaml` VFS where all Merlin artifacts
    are stored. *)
let merlin_vfs_path = "/static/cmis"

(** Performs the initial file setup for the kernel environment.

    This function orchestrates the loading of all files necessary for the OCaml
    standard library to function correctly within the toplevel and Merlin. It
    first writes any statically-linked files (like `stdlib.cmi`) to the virtual
    filesystem, then asynchronously fetches all other standard library artifacts
    (`.cmt`, `.cmti`, and other `.cmi` files) from the server.

    This function must be called and awaited successfully *before* the OCaml
    toplevel or Merlin engine are initialized to prevent `Env.Error` exceptions.

    @param base_url
      The root URL from which to fetch the dynamic standard library files.
    @return A promise that resolves when all initial files have been loaded. *)
let setup ~base_url:url =
  log "[Loader] Initial setup started.";

  (* --- Static Loading --- *)
  log
    (Printf.sprintf "[Loader] Writing %d static files to VFS path: %s"
       (List.length Static_files.files)
       merlin_vfs_path);
  List.iter Static_files.files ~f:(fun (name, content) ->
      let path = Filename.concat merlin_vfs_path name in
      if not (Sys.file_exists path) then (
        log (Printf.sprintf "[Loader] Writing static file: %s" path);
        Js_of_ocaml.Sys_js.create_file ~name:path ~content)
      else
        log
          (Printf.sprintf "[Loader] Skipping static file, already exists: %s"
             path));

  (* --- Initial Dynamic Loading (Simplified) --- *)
  log
    (Printf.sprintf
       "[Loader] Asynchronously fetching %d dynamic artifact files from base \
        URL: %s"
       (List.length Dynamic_files.files)
       url);

  let fetch_one_file filename =
    let vfs_path = Filename.concat merlin_vfs_path filename in
    if Sys.file_exists vfs_path then (
      log
        (Printf.sprintf
           "[Loader] Skipping async download, file already exists: %s" vfs_path);
      Lwt.return_unit)
    else
      let fetch_url = Filename.concat url filename in
      log (Printf.sprintf "[Loader] Fetching dynamic file: %s" fetch_url);
      let* content_opt = Xnetwork.async_get fetch_url in
      Option.iter content_opt ~f:(fun content ->
          log
            (Printf.sprintf "[Loader] SUCCESS: Fetched and writing to VFS: %s"
               vfs_path);
          Js_of_ocaml.Sys_js.create_file ~name:vfs_path ~content);
      Lwt.return_unit
  in

  let* () = Lwt.join (List.map ~f:fetch_one_file Dynamic_files.files) in
  log "[Loader] All initial dynamic files processed. Setup complete.";
  Lwt.return_unit

(** Dynamically loads a pre-compiled third-party OCaml library on-demand.

    This function is triggered by the toplevel when it encounters a `#require
    "lib_name"` directive. It looks up the library in a pre-generated manifest
    (`external_libs.ml`), then fetches the corresponding JavaScript bundle and
    all its Merlin artifacts (`.cmi`, `.cmt`, `.cmti`).

    The JavaScript bundle is executed to make the library's modules available,
    and the artifacts are written to the virtual filesystem to enable code
    completion and documentation for the new library.

    @param base_url
      The root URL where the library's `.js` bundle and artifact files are
      stored.
    @param name The name of the library to load (e.g., "ocamlgraph").
    @return
      A promise that resolves to a result, containing either a success message
      for display in the notebook output, or an error message if the library
      could not be found or loaded. *)
let load_on_demand ~base_url ~name :
    (Protocol.output, Protocol.output) result Lwt.t =
  log
    (Printf.sprintf "[Loader] Looking up library '%s' for on-demand loading..."
       name);
  match Hashtbl.find_opt External_libs.libraries name with
  | None ->
      let error_msg =
        Printf.sprintf
          "Error: Library '%s' not found. It may not be included in the kernel \
           build."
          name
      in
      log ("[Loader] FAILURE: " ^ error_msg);
      Lwt.return (Error (Protocol.Stderr error_msg))
  | Some { js_bundle; artifacts } -> (
      try%lwt
        log
          (Printf.sprintf
             "[Loader] Found library. JS bundle: '%s', Artifacts: %d" js_bundle
             (List.length artifacts));
        (* Fetch and execute the main JS bundle for the library. *)
        let js_promise =
          let js_url = Filename.concat base_url js_bundle in
          let* js_content_opt = Xnetwork.async_get js_url in
          match js_content_opt with
          | Some content ->
              Js.Unsafe.eval_string content |> ignore;
              Lwt.return_unit
          | None -> Lwt.fail_with ("Failed to fetch JS bundle: " ^ js_url)
        in
        (* Concurrently, fetch all associated Merlin artifacts. *)
        let artifact_promises =
          List.map
            ~f:(fun artifact_file ->
              let artifact_url = Filename.concat base_url artifact_file in
              let* content_opt = Xnetwork.async_get artifact_url in
              match content_opt with
              | Some content ->
                  let path = Filename.concat merlin_vfs_path artifact_file in
                  Sys_js.create_file ~name:path ~content;
                  Lwt.return_unit
              | None ->
                  Lwt.fail_with ("Failed to fetch artifact: " ^ artifact_file))
            artifacts
        in
        (* Wait for all files to be fetched and processed. *)
        let* () = Lwt.join (js_promise :: artifact_promises) in
        log "[Loader] All files for on-demand library fetched and processed.";

        (* Inform the toplevel that new modules are available in this directory. *)
        Topdirs.dir_directory merlin_vfs_path;

        let msg =
          Printf.sprintf
            "Library '%s' and its %d artifacts loaded successfully." name
            (List.length artifacts)
        in
        log (Printf.sprintf "[Loader] SUCCESS: %s" msg);
        Lwt.return (Ok (Protocol.Stdout msg))
      with exn ->
        let error_msg =
          Printf.sprintf "Error processing library '%s': %s" name
            (Printexc.to_string exn)
        in
        log (Printf.sprintf "[Loader] EXCEPTION: %s" error_msg);
        Lwt.return (Error (Protocol.Stderr error_msg)))
