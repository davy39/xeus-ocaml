(**
 * @file xtoplevel.mli
 * @brief The main public interface for the web-based OCaml toplevel.
 *)

(**
 * Initializes the OCaml toplevel environment. Must be called once before [eval].
 *
 * @param url The base URL where library files (.js) are located.
 *)
val setup : url:string -> unit

(**
 * Evaluates a string of OCaml code.
 *
 * @param code The OCaml code to evaluate.
 * @return A promise that resolves to a list of all captured outputs.
 *)
val eval : string -> Protocol.output list Lwt.t