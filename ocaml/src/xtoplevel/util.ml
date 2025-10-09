(**
 * @file util.ml
 * @brief Implementation of general-purpose utility functions.
 *)

(** A simple logging utility that prints messages to the browser's console. *)
let log (str : string) : unit =
  Js_of_ocaml.Console.console##log (Js_of_ocaml.Js.string str)
;;