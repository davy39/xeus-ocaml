(**
 * @file library_loader.mli
 * @brief Interface for dynamically loading pre-compiled OCaml libraries.
 *)

(**
 * Dynamically loads a compiled OCaml library from a URL.
 *
 * @param base_url The base path where library .js files are stored.
 * @param name The name of the library (e.g., "graphics").
 * @return A result containing a success or error message for display.
 *)
val load
  :  base_url:string
  -> name:string
  -> (Protocol.output, Protocol.output) result Lwt.t