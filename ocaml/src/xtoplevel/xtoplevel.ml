(**
 * @file xtoplevel.ml
 * @brief Implements the core logic for the web-based OCaml toplevel.
 *
 * This module coordinates parsing, evaluation, output redirection, and dynamic
 * library loading by delegating to specialized modules.
 *)

open Js_of_ocaml_toplevel
open Lwt.Syntax
open Util

(* --- Global State --- *)

(** A reference to track if the toplevel environment has been initialized. *)
let is_setup = ref false

(** The base URL from which dynamic libraries (.js files) will be fetched. *)
let lib_base_url = ref ""

(* --- Initialization --- *)

(**
 * Initializes the OCaml toplevel environment. This function is idempotent.
 *)
let setup ~url =
  log "[Toplevel] Initializing toplevel environment.";
  if not !is_setup
  then (
    JsooTop.initialize ();
    Toploop.toplevel_env := Compmisc.initial_env ();
    Sys.interactive := false;
    lib_base_url := url;
    log (Printf.sprintf "[Toplevel] Library base URL set to: %s" url);
    let init_code = "open Xlib;;" in
    let silent_formatter = Format.formatter_of_buffer (Buffer.create 16) in
    if not (JsooTop.use silent_formatter init_code)
    then
      Js_of_ocaml.Console.console##warn
        (Js_of_ocaml.Js.string
           "Warning: Could not auto-open Xlib module in toplevel.");
    is_setup := true;
    log "[Toplevel] Setup complete.")
  else log "[Toplevel] Toplevel already initialized."
;;

(* --- Core Evaluation Logic --- *)

(**
 * Recursively parses a string into a list of toplevel phrases.
 *)
let rec parse_all_phrases lexbuf =
  match !Toploop.parse_toplevel_phrase lexbuf with
  | phrase -> Ok phrase :: parse_all_phrases lexbuf
  | exception End_of_file -> []
  | exception err -> [ Error err ]
;;

(**
 * Evaluates a string of OCaml code.
 *)
let eval (code : string) : Protocol.output list Lwt.t =
  log (Printf.sprintf "[Toplevel] Evaluating code:\n%s" code);
  if not !is_setup
  then failwith "Toplevel not initialized. Call Xtoplevel.setup first.";

  (* Setup output collection hooks *)
  let buffer = Buffer.create 1024 in
  let formatter = Format.formatter_of_buffer buffer in
  (* Create a dedicated formatter for stderr *)
  let err_formatter = Format.formatter_of_out_channel stderr in
  let std_outputs_ref = ref [] in
  Js_of_ocaml.Sys_js.set_channel_flusher stdout (fun s ->
    std_outputs_ref := Protocol.Stdout s :: !std_outputs_ref);
  Js_of_ocaml.Sys_js.set_channel_flusher stderr (fun s ->
    std_outputs_ref := Protocol.Stderr s :: !std_outputs_ref);
  ignore (Xlib.get_and_clear_outputs ());

  (* Helper to gather all pending outputs *)
  let get_all_pending_outputs () =
    Format.pp_print_flush formatter ();
    let toplevel_value = Buffer.contents buffer in
    Buffer.clear buffer;
    let main_output =
      if toplevel_value <> "" then [ Protocol.Value toplevel_value ] else []
    in
    let rich_outputs = Xlib.get_and_clear_outputs () in
    let std_outputs = List.rev !std_outputs_ref in
    std_outputs_ref := [];
    List.concat [ std_outputs; rich_outputs; main_output ]
  in

  (* Parse the code into phrases *)
  let lexbuf = Lexing.from_string (code ^ ";;") in
  let phrases = parse_all_phrases lexbuf in
  log (Printf.sprintf "[Toplevel] Found %d phrase(s) to execute." (List.length phrases));

  (* Execute phrases sequentially *)
  let* final_outputs =
    Lwt_list.fold_left_s
      (fun acc_outputs phrase_result ->
        let* new_outputs =
          match phrase_result with
          | Ok
              (Parsetree.Ptop_dir
                { pdir_name = { txt = "require"; _ };
                  pdir_arg = Some { pdira_desc = Pdir_string lib_name; _ };
                  _
                }) ->
            log (Printf.sprintf "[Toplevel] Handling #require for: %s" lib_name);
            let* result =
              Library_loader.load ~base_url:!lib_base_url ~name:lib_name
            in
            let linking_output =
              match result with
              | Ok o -> [ o ]
              | Error e -> [ e ]
            in
            Lwt.return (List.append linking_output (get_all_pending_outputs ()))
          | Ok toplevel_phrase ->
            let sub_phrases =
              match toplevel_phrase with
              | Parsetree.Ptop_def s ->
                List.map (fun si -> Parsetree.Ptop_def [ si ]) s
              | Parsetree.Ptop_dir _ as p -> [ p ]
            in
            List.iter
              (fun sub_phrase ->
                try ignore (Toploop.execute_phrase true formatter sub_phrase) with
                | exn ->
                  (* Use err_formatter and flush it *)
                  Errors.report_error err_formatter exn;
                  Format.pp_print_flush err_formatter ())
              sub_phrases;
            Lwt.return (get_all_pending_outputs ())
          | Error err ->
            (* Use err_formatter and flush it *)
            Errors.report_error err_formatter err;
            Format.pp_print_flush err_formatter ();
            Lwt.return (get_all_pending_outputs ())
        in
        Lwt.return (List.append acc_outputs new_outputs))
      []
      phrases
  in
  log "[Toplevel] Evaluation finished.";
  Lwt.return final_outputs
;;