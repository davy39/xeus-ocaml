(** @author Davy Cottet

    This module provides a minimal, promise-based interface for performing
    asynchronous network requests within the browser. It abstracts the
    callback-based nature of `XmlHttpRequest` into a more convenient Lwt-based
    API for use throughout the OCaml kernel. *)

open Xutil

(** Asynchronously fetches the content of a given URL.

    This function uses the `Js_of_ocaml` bindings for the `XmlHttpRequest` API
    to perform an asynchronous GET request. It bridges the callback-based
    browser API with OCaml's Lwt library by creating a promise with `Lwt.task`.
    The promise is resolved in the `onload` or `onerror` callbacks of the
    request.

    The request is configured to receive an `arraybuffer` to ensure that both
    text and binary files are handled correctly without corruption, before being
    converted to an OCaml string.

    @param url The URL to fetch.
    @return
      A promise that resolves to [`Some string`] on success, or [`None`] if the
      fetch fails for any reason (e.g., network error, 404 status). *)
let async_get (url : string) : string option Lwt.t =
  let open Js_of_ocaml in
  try
    let promise, resolver = Lwt.task () in
    let req = XmlHttpRequest.create () in
    req##.responseType := Js.string "arraybuffer";
    req##_open (Js.string "GET") (Js.string url) Js._true;
    req##.onload :=
      Dom.handler (fun _ ->
          if req##.status = 200 then (
            log (Printf.sprintf "[Network] Successfully fetched %s" url);
            Js.Opt.case
              (File.CoerceTo.arrayBuffer req##.response)
              (fun () -> Lwt.wakeup_later resolver None)
              (fun response_buf ->
                let str = Typed_array.String.of_arrayBuffer response_buf in
                Lwt.wakeup_later resolver (Some str)))
          else (
            log
              (Printf.sprintf "[Network] Failed to fetch %s (status: %d)" url
                 req##.status);
            Lwt.wakeup_later resolver None);
          Js._true);
    req##.onerror :=
      Dom.handler (fun _ ->
          log (Printf.sprintf "[Network] Network error while fetching %s" url);
          Lwt.wakeup_later resolver None;
          Js._true);
    req##send Js.null;
    promise
  with exn ->
    Console.console##error
      (Js.string
         (Printf.sprintf "[Network] Exception: %s" (Printexc.to_string exn)));
    Lwt.return_none
