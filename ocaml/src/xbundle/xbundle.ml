(* {1 OCaml Library Bundler for JS}
   @author Davy Cottet
 
   A command-line tool for bundling OCaml libraries into JavaScript files for
   use with `js_of_ocaml`. It also collects associated Merlin artifacts
   (`.cmi`, `.cmt`, `.cmti`) required for code intelligence features like
   completion and documentation.
 
   The tool reads a list of library names from a text file, resolves their
   full dependency trees using `ocamlfind`, and then performs two main actions
   for each library:
   1.  It compiles the library and all its dependencies into a single JavaScript
       bundle using `js_of_ocaml --toplevel`.
   2.  It finds and copies all Merlin artifacts for the library and its
       dependencies into the current directory.
 
   Finally, it generates an OCaml module (`external_libs.ml`) containing a
   hashtable that maps each bundled library name to its corresponding JS file
   and list of artifact filenames. This module is used by the `xeus-ocaml`
   kernel at runtime to dynamically load libraries via the `#require` directive.
 *)

open Bos

(* Exception raised for unrecoverable errors during the bundling process. *)
exception Fatal_error of string

(* A helper function to unwrap a [Bos.OS] result or raise a [Fatal_error].
   @param result The ['a, 'b] result to process.
   @return The value of [Ok v].
   @raise Fatal_error if the result is an [Error].
 *)
let run_or_raise = function
  | Ok v -> v
  | Error (`Msg s) -> raise (Fatal_error s)

(* Executes a command and returns its standard output as a single string.
   Raises [Fatal_error] if the command fails.
   @param cmd The [Bos.Cmd.t] command to execute.
   @return The captured stdout from the command.
 *)
let get_cmd_output cmd =
  let result = OS.Cmd.run_out cmd |> OS.Cmd.out_string in
  fst (run_or_raise result)

(* Splits a multi-line string into a list of strings. *)
let lines = String.split_on_char '\n'

(* A JavaScript snippet prepended to each generated bundle.
   This IIFE (Immediately Invoked Function Expression) safely wraps the
   `jsoo_runtime.jsoo_create_file` function. It suppresses errors that occur
   when a library tries to create a file before the `js_of_ocaml` virtual
   filesystem is fully mounted, a common occurrence in the `xeus-ocaml`
   environment.
 *)
let jsoo_safe_import =
  {|(function(globalThis){
    "use strict";
    var runtime = globalThis.jsoo_runtime;
    var original_create_file = runtime.jsoo_create_file;
    runtime.jsoo_create_file = function(name, content) {
      try {
        return original_create_file(name, content);
      } catch(err) {
        if (!String(err).includes("property 'jsoo_mount_point'")) {
            console.warn("jsoo_create_file failed for:", name, "Error:", err);
        }
      }
    };
  }
  (globalThis));|}

(* Information about a single OCaml library resolved by `ocamlfind`.
 *)
type lib_info = {
  name : string; (* The name of the library (e.g., "ocamlgraph"). *)
  incl : Bos.Cmd.t; (* The include path arguments (`-I ...`) for the library. *)
  cma : string; (* The path to the library's bytecode archive (`.cma`) file. *)
}
[@@warning "-69"]
(* Suppress unused-field warning for 'name', which is used for construction *)

(* Reads a file and returns a list of its non-empty, non-comment lines.
   @param path The [Fpath.t] of the file to read.
   @return A list of trimmed strings.
 *)
let read_lines path =
  let content = run_or_raise @@ OS.File.read path in
  lines content |> List.map String.trim
  |> List.filter (fun s -> s <> "" && not (String.starts_with ~prefix:"#" s))

(* Finds all files within a directory that have one of the specified extensions.
   @param dir The directory to search.
   @param exts A list of file extensions to look for (e.g., [".cmi"; ".cmt"]).
   @return A list of relative paths to the found files.
 *)
let find_files_by_exts dir exts =
  let files_in_dir = run_or_raise @@ OS.Dir.contents ~rel:true dir in
  files_in_dir
  |> List.filter (fun path ->
         List.exists (fun ext -> Fpath.has_ext ext path) exts)

(* Runs `ocamlfind query` to get the path to a library's `.cma` file. *)
let ocamlfind_cma ~preds lib =
  get_cmd_output
    Bos.Cmd.(
      v "ocamlfind" % "query" % lib % "-a-format" % "-predicates" % preds)

(* Runs `ocamlfind query` to get the include path arguments for a library. *)
let ocamlfind_includes lib =
  get_cmd_output
    Bos.Cmd.(
      v "ocamlfind" % "query" % lib % "-i-format" % "-predicates" % "byte")

(* Runs `ocamlfind query` to get the recursive list of dependencies for a library. *)
let ocamlfind_deps ~preds lib =
  lines
  @@ get_cmd_output
       Bos.Cmd.(
         v "ocamlfind" % "query" % lib % "-r" % "-p-format" % "-predicates"
         % preds)

(* A set of strings used to track processed libraries and avoid duplicates. *)
module Env = Stdlib.Set.Make (String)

(* Constructs a {!lib_info} record for a given library name.
   @param preds The `ocamlfind` predicates to use (e.g., "byte").
   @param lib The name of the library.
   @return An [option] containing the {!lib_info} on success, or [None] if no
           `.cma` file is found for the given predicates.
 *)
let make ~preds lib =
  let cma = ocamlfind_cma ~preds lib |> String.trim in
  match cma with
  | "" ->
      Format.printf
        "  [Info] Skipping '%s' (no .cma found for predicate '%s').\n%!" lib
        preds;
      None
  | cma ->
      let incl_str = ocamlfind_includes lib in
      let incl = run_or_raise @@ Bos.Cmd.of_string incl_str in
      Some { incl; cma; name = lib }

(* Recursively resolves the full dependency tree for a list of target libraries.
   @param ppx Whether to include `ppx_driver` predicates for PPX dependencies.
   @param targets A list of top-level library names.
   @return A list of {!lib_info} records for all dependencies, including the
           targets themselves, in an order suitable for compilation.
 *)
let get_dependencies ~ppx targets =
  let preds = if ppx then "ppx_driver,byte" else "byte" in
  let rec gather_deps libs_to_process processed acc =
    match libs_to_process with
    | [] -> List.rev acc
    | lib :: rest -> (
        if Env.mem lib processed then gather_deps rest processed acc
        else
          let processed = Env.add lib processed in
          let direct_deps = ocamlfind_deps ~preds lib in
          let all_to_process = rest @ direct_deps in
          match make ~preds lib with
          | None -> gather_deps all_to_process processed acc
          | Some info -> gather_deps all_to_process processed (info :: acc))
  in
  gather_deps targets Env.empty []

(* Generates the content for the `external_libs.ml` module.
   This module contains a hashtable mapping library names to their bundle data.
   @param data A list of tuples, where each tuple contains a library name and
               its associated JS bundle name and list of artifact filenames.
   @return A string containing the full OCaml module source code.
 *)
let generate_ml_file_content data =
  let header =
    [
      "(* This file is generated by xbundle. Do not edit. *)";
      "";
      "type library = {";
      "  js_bundle: string;";
      "  artifacts: string list;";
      "}";
      "";
      "let libraries : (string, library) Hashtbl.t = Hashtbl.create 10";
      "";
      "let () =";
    ]
  in
  let add_lib_entries =
    List.map
      (fun (lib_name, (js_bundle, artifacts)) ->
        let artifacts_str =
          artifacts |> List.map (Printf.sprintf "%S") |> String.concat "; "
        in
        Printf.sprintf
          "  Hashtbl.add libraries %S {\n\
          \    js_bundle = %S;\n\
          \    artifacts = [%s];\n\
          \  };"
          lib_name js_bundle artifacts_str)
      data
  in
  String.concat "\n" (header @ add_lib_entries)

(* The main entry point of the command-line tool.
   Orchestrates the entire bundling process.
   @param libs_file_path The path to the input text file listing libraries to bundle.
 *)
let main libs_file_path =
  try
    let libs_to_bundle = read_lines (Fpath.v libs_file_path) in
    let ml_module_data = ref [] in

    List.iter
      (fun lib_name ->
        Format.printf "--- Bundling library: %s ---\n%!" lib_name;
        let all_deps = get_dependencies ~ppx:false [ lib_name ] in
        Format.printf "  Found %d dependencies.\n%!" (List.length all_deps);

        (* Find all Merlin artifacts (.cmi, .cmt, .cmti) for all dependencies. *)
        let all_artifacts =
          all_deps
          |> List.concat_map (fun dep ->
                 let lib_dir = Fpath.parent (Fpath.v dep.cma) in
                 find_files_by_exts lib_dir [ ".cmi"; ".cmt"; ".cmti" ]
                 |> List.map (Fpath.append lib_dir))
        in

        (* Copy the found artifacts to the current directory for bundling. *)
        let copied_artifact_basenames =
          all_artifacts
          |> List.map (fun src_path ->
                 let dst_path = Fpath.(v "." // base src_path) in
                 let content = run_or_raise @@ OS.File.read src_path in
                 run_or_raise @@ OS.File.write dst_path content;
                 Fpath.basename dst_path)
          |> List.sort_uniq String.compare
        in
        Format.printf "  Copied %d artifacts to current directory.\n%!"
          (List.length copied_artifact_basenames);

        (* Compile the library and its dependencies into a single JS bundle. *)
        let js_bundle_name = lib_name ^ ".js" in
        let js_bundle_path = Fpath.v js_bundle_name in
        let result =
          OS.File.with_tmp_output "xbundle-%s.js"
            (fun tmp_js_path _ () ->
              let includes =
                List.fold_left
                  (fun acc dep -> Bos.Cmd.(acc %% dep.incl))
                  Bos.Cmd.empty all_deps
              in
              let cmas =
                Bos.Cmd.of_list (List.map (fun dep -> dep.cma) all_deps)
              in
              let jsoo_cmd =
                Bos.Cmd.(
                  v "js_of_ocaml" % "--toplevel" % "--no-cmis" %% includes
                  %% cmas % "-o" % p tmp_js_path)
              in
              ignore (get_cmd_output jsoo_cmd);
              let js_content = run_or_raise @@ OS.File.read tmp_js_path in
              let final_js = jsoo_safe_import ^ js_content in
              OS.File.write js_bundle_path final_js)
            ()
        in
        run_or_raise (Result.bind result Fun.id);
        Format.printf "  Generated JS bundle: %s\n%!" js_bundle_name;

        (* Store metadata for the final ML module generation. *)
        ml_module_data :=
          (lib_name, (js_bundle_name, copied_artifact_basenames))
          :: !ml_module_data)
      libs_to_bundle;

    (* Generate and write the external_libs.ml file. *)
    let ml_content = generate_ml_file_content (List.rev !ml_module_data) in
    let ml_path = Fpath.v "external_libs.ml" in
    run_or_raise @@ OS.File.write ml_path ml_content;
    Format.printf
      "\n--- Successfully generated module: external_libs.ml ---\n%!";
    ()
  with
  | Fatal_error msg ->
      Printf.eprintf "Error: %s\n%!" msg;
      exit 1
  | ex ->
      Printf.eprintf "An unexpected error occurred: %s\n%s\n%!"
        (Printexc.to_string ex)
        (Printexc.get_backtrace ());
      exit 1

(* Cmdliner term for the required command-line argument. *)
let libs_file_arg =
  Cmdliner.Arg.(required & pos 0 (some file) None & info [] ~docv:"LIBS_FILE")

(* Cmdliner term for the main function. *)
let main_term = Cmdliner.Term.(const main $ libs_file_arg)

(* Cmdliner command definition. *)
let cmd_main = Cmdliner.Cmd.v (Cmdliner.Cmd.info "xbundle") main_term

(* Execute the command-line interface. *)
let () = exit (Cmdliner.Cmd.eval cmd_main)
