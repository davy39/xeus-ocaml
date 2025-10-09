open Merlin_utils.Std
open Lwt.Syntax
open Js_of_ocaml

let rec yojson_basic_to_safe (json : Yojson.Basic.t) : Yojson.Safe.t =
  match json with
  | `Assoc kvs -> `Assoc (List.map ~f:(fun (k, v) -> (k, yojson_basic_to_safe v)) kvs)
  | `List jsons -> `List (List.map ~f: yojson_basic_to_safe jsons)
  | `Null -> `Null
  | `Bool b -> `Bool b
  | `Int i -> `Int i
  | `Float f -> `Float f
  | `String s -> `String s


let create_response class_name value =
  `Assoc [("class", `String class_name); ("value", value)]
let create_success_response value = create_response "return" value
let create_error_response msg = create_response "error" (`String msg)


let process_merlin_action_sync (json_str_js : Js.js_string Js.t) : Js.js_string Js.t =
  let json_str = Js.to_string json_str_js in
  let response_json =
    try
      match Protocol.action_of_yojson (Yojson.Safe.from_string json_str) with
      | Ok (Eval _ | Setup _) ->
          create_error_response "This action must be called asynchronously."
      | Ok action -> (
          match Xmerlin.process_merlin_action action with
          | Some result -> create_success_response (yojson_basic_to_safe result)
          | None -> create_error_response "Unknown or unhandled Merlin action."
      )
      | Error msg ->
        create_error_response ("JSON parsing error: " ^ msg)
    with exn ->
      create_error_response ("OCaml exception: " ^ Printexc.to_string exn)
  in
  Yojson.Safe.to_string response_json |> Js.string

let process_toplevel_action_async (json_str_js : Js.js_string Js.t) (callback : (Js.js_string Js.t -> unit) Js.callback) : unit =
  let json_str = Js.to_string json_str_js in
  let computation =
    Lwt.catch
      (fun () ->
        let action_res = Protocol.action_of_yojson (Yojson.Safe.from_string json_str) in
        match action_res with
        | Ok (Protocol.Eval { source }) ->
          let* outputs = Xtoplevel.eval source in
          let response_value = `List (List.map ~f:Protocol.output_to_yojson outputs) in
          Lwt.return @@ create_success_response response_value
        | Ok (Protocol.Setup setup_config) ->
          Xtoplevel.setup ~url:setup_config.dsc_url;
          let* () = Xmerlin.setup ~url:setup_config.dsc_url in
          Lwt.return @@ create_success_response (`String "Setup complete")
        | Ok _ ->
          Lwt.return @@ create_error_response "This action must be handled synchronously."
        | Error msg ->
          Lwt.return @@ create_error_response ("JSON parsing error: " ^ msg)
      )
      (fun exn ->
        let error_msg = Printexc.to_string exn in
        Lwt.return @@ create_error_response ("OCaml Lwt exception: " ^ error_msg)
      )
  in
  Lwt.on_success computation (fun response_json ->
    let result_js_string = Yojson.Safe.to_string response_json |> Js.string in
    ignore (Js.Unsafe.fun_call callback [| Js.Unsafe.inject result_js_string |])
  )

let () =
  Js.export "xocaml"
    (object%js
       val processMerlinAction = process_merlin_action_sync
       val processToplevelAction = process_toplevel_action_async
    end)