(** @author Davy Cottet

    This module provides a minimal, promise-based interface for performing
    asynchronous network requests within the browser. It abstracts the
    callback-based nature of `XmlHttpRequest` into a more convenient Lwt-based
    API for use throughout the OCaml kernel. *)

val async_get : string -> string option Lwt.t
(** Asynchronously fetches the content of a given URL.

    This function uses the browser's `XmlHttpRequest` API to perform a GET
    request. It is designed to be safe for fetching both text and binary content
    by requesting an `arraybuffer` and then converting it to a string.

    @param url The URL of the resource to fetch.
    @return
      A promise that resolves to [`Some string`] containing the file content on
      success (HTTP 200), or [`None`] if the fetch fails for any reason (e.g., a
      network error or a non-200 status code like 404). *)
