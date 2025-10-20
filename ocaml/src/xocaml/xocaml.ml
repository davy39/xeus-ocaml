(** @author Davy Cottet

    This module is the main entry point for the entire OCaml side of the
    `xeus-ocaml` kernel. When compiled with `js_of_ocaml`, it produces the
    `xocaml.js` bundle.

    Its primary responsibility is to expose a well-defined JavaScript API that
    the C++ part of the kernel (running as WebAssembly) can call into. This API
    is registered in the global JavaScript scope under the `xocaml` object.

    The exported API consists of three key functions:

    - `processMerlinAction(jsonString)`: A **synchronous** function for handling
      quick, non-blocking code intelligence requests (completion, inspection,
      etc.). It takes a JSON string and immediately returns a JSON string.

    - `processToplevelAction(jsonString, callback)`: An **asynchronous**
      function for handling potentially long-running operations like code
      evaluation (`Eval`) or the initial kernel setup (`Setup`). It takes a JSON
      string and a JavaScript callback function. It returns immediately, and the
      result (as a JSON string) is delivered later by invoking the provided
      callback.

    - `mountFS()`: A function to trigger the mounting of the Emscripten virtual
      filesystem device from within OCaml.

    This module orchestrates the initialization sequence and delegates incoming
    requests to the appropriate sub-modules (`Xmerlin`, `Xtoplevel`,
    `Xlibloader`). *)

open Merlin_utils.Std
open Lwt.Syntax
open Js_of_ocaml

(** Recursively converts a [`Yojson.Basic.t`] value to a [`Yojson.Safe.t`]
    value. This is a necessary utility because some dependencies (like
    `merlin-lib`) produce `Basic` JSON, while the rest of the application and
    `ppx_deriving_yojson` work with the `Safe` variant.
    @param json The `Yojson.Basic.t` to convert.
    @return The equivalent `Yojson.Safe.t`. *)
let rec yojson_basic_to_safe (json : Yojson.Basic.t) : Yojson.Safe.t =
  match json with
  | `Assoc kvs ->
      `Assoc (List.map ~f:(fun (k, v) -> (k, yojson_basic_to_safe v)) kvs)
  | `List jsons -> `List (List.map ~f:yojson_basic_to_safe jsons)
  | `Null -> `Null
  | `Bool b -> `Bool b
  | `Int i -> `Int i
  | `Float f -> `Float f
  | `String s -> `String s

(** Creates a standard JSON response object, which is the basic communication
    protocol between the OCaml backend and the C++ frontend.
    @param class_name
      The status of the response ("return" for success, "error" for failure).
    @param value The JSON payload of the response. *)
let create_response class_name value =
  `Assoc [ ("class", `String class_name); ("value", value) ]

(** A convenience wrapper for creating a successful response. *)
let create_success_response value = create_response "return" value

(** A convenience wrapper for creating an error response. *)
let create_error_response msg = create_response "error" (`String msg)

(** The synchronous entry point for handling Merlin-related actions. This
    function is exported to JavaScript as `xocaml.processMerlinAction`. It
    decodes the incoming JSON, dispatches the action to the {!Xmerlin} module,
    and encodes the result back into a JSON string for the C++ caller.

    It specifically rejects `Eval` and `Setup` actions, which must be handled
    asynchronously.

    @param json_str_js
      A JavaScript string containing the JSON-encoded {!Protocol.action}.
    @return A JavaScript string containing the JSON-encoded response. *)
let process_merlin_action_sync (json_str_js : Js.js_string Js.t) :
    Js.js_string Js.t =
  let json_str = Js.to_string json_str_js in
  let response_json =
    try
      match Protocol.action_of_yojson (Yojson.Safe.from_string json_str) with
      | Ok (Eval _ | Setup _) ->
          create_error_response "This action must be called asynchronously."
      | Ok action -> (
          match Xmerlin.process_merlin_action action with
          | Some result -> create_success_response (yojson_basic_to_safe result)
          | None -> create_error_response "Unknown or unhandled Merlin action.")
      | Error msg -> create_error_response ("JSON parsing error: " ^ msg)
    with exn ->
      create_error_response ("OCaml exception: " ^ Printexc.to_string exn)
  in
  Yojson.Safe.to_string response_json |> Js.string

(** The asynchronous entry point for handling Toplevel-related actions. This
    function is exported to JavaScript as `xocaml.processToplevelAction`.

    It decodes the action from the input JSON. For an `Eval` action, it calls
    {!Xtoplevel.eval}. For a `Setup` action, it orchestrates the full kernel
    initialization sequence: file loading, toplevel setup, and Merlin setup.

    The result of the Lwt promise is JSON-encoded and passed to the provided
    JavaScript callback function. All exceptions are caught and returned as
    structured error JSONs via the same callback.

    @param json_str_js
      A JavaScript string containing the JSON-encoded {!Protocol.action}.
    @param callback
      A JavaScript callback function that accepts a single string argument (the
      JSON response). *)
let process_toplevel_action_async (json_str_js : Js.js_string Js.t)
    (callback : (Js.js_string Js.t -> unit) Js.callback) : unit =
  let json_str = Js.to_string json_str_js in
  let computation =
    Lwt.catch
      (fun () ->
        let action_res =
          Protocol.action_of_yojson (Yojson.Safe.from_string json_str)
        in
        match action_res with
        | Ok (Protocol.Eval { source }) ->
            Xutil.log "[Xocaml] Received Eval action.";
            let* outputs = Xtoplevel.eval source in
            let response_value =
              `List (List.map ~f:Protocol.output_to_yojson outputs)
            in
            Lwt.return @@ create_success_response response_value
        | Ok (Protocol.Setup setup_config) ->
            Xutil.log "[Xocaml] Received Setup action. Starting file loading...";
            let* () = Xlibloader.setup ~base_url:setup_config.dsc_url in
            Xutil.log "[Xocaml] File loading complete. Initializing Toplevel...";
            Xtoplevel.setup ~url:setup_config.dsc_url;
            Xutil.log "[Xocaml] Toplevel initialized. Initializing Merlin...";
            Xmerlin.initialize ();
            Xutil.log "[Xocaml] Merlin initialized. Setup successful.";
            Lwt.return
            @@ create_success_response (`String "Setup Phase 1 complete")
        | Ok _ ->
            Lwt.return
            @@ create_error_response
                 "This action must be handled synchronously."
        | Error msg ->
            Lwt.return @@ create_error_response ("JSON parsing error: " ^ msg))
      (fun exn ->
        let backtrace = Printexc.get_backtrace () in
        let error_msg =
          Printf.sprintf "OCaml Lwt exception: %s\nBacktrace:\n%s"
            (Printexc.to_string exn) backtrace
        in
        Xutil.log ("[Xocaml] " ^ String.escaped error_msg);
        Lwt.return @@ create_error_response error_msg)
  in
  Lwt.on_success computation (fun response_json ->
      let result_js_string = Yojson.Safe.to_string response_json |> Js.string in
      ignore
        (Js.Unsafe.fun_call callback [| Js.Unsafe.inject result_js_string |]))

(** Main side-effect of the module. This block exports the OCaml functions to
    the JavaScript global scope, making them callable from the C++ kernel. It
    creates a global object named `xocaml` with three properties:
    `processMerlinAction`, `processToplevelAction`, and `mountFS`. *)
let () =
  Js.export "xocaml"
    (object%js
       val processMerlinAction = process_merlin_action_sync
       val processToplevelAction = process_toplevel_action_async
       val mountFS = Xfs.mount_drive
    end)
