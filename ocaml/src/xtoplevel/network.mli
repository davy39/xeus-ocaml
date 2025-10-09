(**
 * @file network.mli
 * @brief Interface for asynchronous network operations.
 *)

(**
 * Asynchronously fetches the content of a given URL.
 *
 * @param url The URL to fetch.
 * @return A promise that resolves to [Some string] on success, or [None] on failure.
 *)
val async_get : string -> string option Lwt.t