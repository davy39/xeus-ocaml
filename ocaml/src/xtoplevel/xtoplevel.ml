(**
    {1 OCaml Toplevel (REPL)}
    @author Davy Cottet
   
    This module implements the core Read-Eval-Print Loop (REPL) functionality for
    the `xeus-ocaml` kernel. It is responsible for initializing the OCaml toplevel
    environment and for executing user-provided code.
   
    The module relies on the `js_of_ocaml-toplevel` library for the underlying
    evaluation mechanism. It enhances this by capturing all forms of output
    (stdout, stderr, toplevel values, and rich display data from the {!Xlib}
    module) and handling special toplevel directives like `#require`.
   
    {b CRITICAL}: The {!setup} function in this module must only be called *after*
    the {!Xlibloader.setup} function has successfully completed to ensure the
    necessary standard library files are present in the virtual filesystem.
 *)

open Js_of_ocaml
open Lwt.Syntax
open Xutil
open Js_of_ocaml_toplevel

let () = log "[Toplevel] Module loaded."

(** A flag to ensure the toplevel is only set up once. *)
let is_setup = ref false
(** A reference to store the base URL for loading third-party libraries. *)
let lib_base_url = ref ""

(**
    Initializes the OCaml toplevel environment.
   
    This function performs the final steps of the kernel's OCaml-side setup. It
    must be called after the virtual filesystem has been populated by {!Xlibloader.setup}.
   
    Its main tasks are:
    - Initializing the `js_of_ocaml` toplevel machinery.
    - Creating the initial compiler environment, which requires `stdlib.cmi`.
    - Automatically opening the {!Xlib} module to make rich display functions
      globally available to the user.
   
    @param url The base URL where third-party library files are located. This is
               stored and used later when handling `#require` directives.
    @before 0.1.0 This function has significant side effects, creating and modifying
                  the global state of the OCaml toplevel environment. It should
                  only be called once at kernel startup.
 *)
let setup ~url =
  log "[Toplevel] Starting OCaml Toplevel setup...";
  if not !is_setup then (
    JsooTop.initialize ();
    log "[Toplevel] Setting up initial toplevel environment...";
    (try
      (* This is the critical step that requires stdlib.cmi to be in the VFS. *)
      Toploop.toplevel_env := Compmisc.initial_env ()
    with exn ->
      let backtrace = Printexc.get_backtrace () in
      log (Printf.sprintf "[Toplevel] FATAL ERROR in Compmisc.initial_env: %s\n%s" (Printexc.to_string exn) backtrace);
      raise exn);
    log "[Toplevel] Initial environment created successfully.";

    Sys.interactive := false;
    (* Silently execute `open Xlib;;` to make rich display functions available. *)
    let init_code = "open Xlib;;" in
    let silent_formatter = Format.formatter_of_buffer (Buffer.create 16) in
    if not (JsooTop.use silent_formatter init_code) then
      Js.Unsafe.global##.console##warn (Js.string "Warning: Could not auto-open Xlib module.");

    lib_base_url := url;
    is_setup := true;
    log "[Toplevel] OCaml Toplevel setup complete."
  ) else log "[Toplevel] Already initialized."

(**
    Helper function to parse a string of code into a list of toplevel phrases.
    It continues parsing until [End_of_file] is reached and wraps parsing
    errors in a [result] type.
    @param lexbuf The lexer buffer initialized with the user's code.
    @return A list where each element is [`Ok phrase] or [`Error exn].
 *)
let rec parse_all_phrases lexbuf =
  match !Toploop.parse_toplevel_phrase lexbuf with
  | phrase -> Ok phrase :: parse_all_phrases lexbuf
  | exception End_of_file -> []
  | exception err -> [ Error err ]

(**
    Parses and evaluates a string of OCaml code.
   
    This is the main execution function for the kernel. It takes a block of code,
    splits it into individual toplevel phrases (ending in `;;`), and executes
    them sequentially.
   
    It captures all outputs generated during execution, including standard streams,
    the printed value of the last expression, and any rich outputs created via
    the {!Xlib} module. It also provides special handling for the `#require "lib_name"`
    directive by delegating to the {!Xlibloader.load_on_demand} function.
   
    @param code The string of OCaml code to evaluate.
    @return A promise that resolves to a list of all captured {!Protocol.output}
            items, which will be sent to the Jupyter frontend for display.
 *)
let eval (code : string) : Protocol.output list Lwt.t =
  log (Printf.sprintf "[Toplevel] Evaluating code:\n%s" code);
  if not !is_setup
  then failwith "Toplevel not initialized. Call Xtoplevel.setup first.";

  (* --- Setup Output Capture --- *)
  let buffer = Buffer.create 1024 in
  let formatter = Format.formatter_of_buffer buffer in
  let err_formatter = Format.formatter_of_out_channel stderr in
  let std_outputs_ref = ref [] in
  Js_of_ocaml.Sys_js.set_channel_flusher stdout (fun s -> std_outputs_ref := Protocol.Stdout s :: !std_outputs_ref);
  Js_of_ocaml.Sys_js.set_channel_flusher stderr (fun s -> std_outputs_ref := Protocol.Stderr s :: !std_outputs_ref);
  ignore (Xlib.get_and_clear_outputs ()); (* Clear any stale rich outputs *)

  (* Helper to remove the initial newline from the toplevel formatter's output. *)
  let trim_first_newline s =
      if String.length s > 0 && s.[0] = '\n' then
        String.sub s 1 (String.length s - 1)
      else
        s
  in

  (* Function to collect all pending outputs from all sources. *)
  let get_all_pending_outputs () =
    Format.pp_print_flush formatter ();
    let toplevel_value = Buffer.contents buffer |> trim_first_newline in
    Buffer.clear buffer;
    let main_output = if toplevel_value <> "" then [ Protocol.Value toplevel_value ] else [] in
    let rich_outputs = Xlib.get_and_clear_outputs () in
    let std_outputs = List.rev !std_outputs_ref in
    std_outputs_ref := [];
    List.concat [ std_outputs; rich_outputs; main_output ]
  in

  (* --- Parse and Execute --- *)
  let lexbuf = Lexing.from_string (code ^ ";;") in
  let phrases = parse_all_phrases lexbuf in
  log (Printf.sprintf "[Toplevel] Found %d phrase(s) to execute." (List.length phrases));

  (* Asynchronously fold over the list of phrases, accumulating outputs. *)
  let* final_outputs =
    Lwt_list.fold_left_s
      (fun acc_outputs phrase_result ->
        let* new_outputs = match phrase_result with
          (* Special case for #require directive *)
          | Ok (Parsetree.Ptop_dir { pdir_name = { txt = "require"; _ }; pdir_arg = Some { pdira_desc = Pdir_string lib_name; _ }; _ }) ->
            log (Printf.sprintf "[Toplevel] Handling #require for: %s" lib_name);
            let* result = Xlibloader.load_on_demand ~base_url:!lib_base_url ~name:lib_name in
            let linking_output = match result with | Ok o -> [ o ] | Error e -> [ e ] in
            Lwt.return (List.append linking_output (get_all_pending_outputs ()))
          (* Standard toplevel phrase *)
          | Ok toplevel_phrase ->
            let sub_phrases = match toplevel_phrase with | Parsetree.Ptop_def s -> List.map (fun si -> Parsetree.Ptop_def [ si ]) s | Parsetree.Ptop_dir _ as p -> [ p ] in
            List.iter (fun sub_phrase -> try ignore (Toploop.execute_phrase true formatter sub_phrase) with | exn -> Errors.report_error err_formatter exn; Format.pp_print_flush err_formatter ()) sub_phrases;
            Lwt.return (get_all_pending_outputs ())
          (* Syntax error from parsing *)
          | Error err ->
            Errors.report_error err_formatter err;
            Format.pp_print_flush err_formatter ();
            Lwt.return (get_all_pending_outputs ())
        in
        Lwt.return (List.append acc_outputs new_outputs))
      [] phrases
  in
  log "[Toplevel] Evaluation finished.";
  Lwt.return final_outputs