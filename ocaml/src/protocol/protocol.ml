(** {1 Communication Protocol}
    @author Davy Cottet

    Defines the core data structures used for communication between the
    C++/JavaScript frontend and the OCaml backend of the kernel.

    These types are automatically serialized to and from JSON using
    `ppx_deriving_yojson`, forming a strict contract between the two parts of
    the application. This module is the single source of truth for the API. *)

open Merlin_kernel
module Location = Ocaml_parsing.Location

type source = string [@@deriving yojson]
(** Represents a block of OCaml source code to be processed. *)

type position = [ `Offset of int ] [@@deriving yojson]
(** Represents a cursor position within a source code buffer.
    - [`Offset i] indicates the position is at the [i]-th byte from the start.
*)

(** Converts a {!position} from this protocol into Merlin's internal
    Msource.position type, which is required for all Merlin queries. *)
let to_msource_position : position -> Msource.position = function
  | `Offset i -> `Offset i

type dynamic_setup_config = {
  dsc_url : string;
      (** The base URL from which to fetch dynamic standard library files and
          other assets. *)
}
[@@deriving yojson]
(** Configuration data required for the initial kernel setup. *)

(** The main variant type that represents all possible commands the frontend can
    send to the OCaml backend. *)
type action =
  | Complete_prefix of { source : source; position : position }
      (** A request for code completion at a given position. *)
  | Type_enclosing of { source : source; position : position }
      (** A request for the type of the expression enclosing a given position.
      *)
  | Document of { source : source; position : position }
      (** A request for the documentation (docstring) of the identifier at a
          given position. *)
  | Eval of { source : source }
      (** A request to evaluate a block of source code. *)
  | All_errors of { source : source }
      (** A request to get all syntax and type errors in a source buffer. *)
  | Setup of dynamic_setup_config
      (** The initial command to set up the kernel environment. *)
  | List_files of { path : string }
      (** A utility command to list files in the virtual filesystem (for
          debugging). *)
[@@deriving yojson { strict = false }]

type error = {
  kind : Location.report_kind;
      (** The category of the report (e.g., error, warning). *)
  loc : Location.t;  (** The source code location of the error. *)
  main : string;  (** The primary error message. *)
  sub : string list;  (** A list of secondary or supplementary messages. *)
  source : Location.error_source;
      (** The stage of the toolchain that produced the error (lexer, parser,
          typer). *)
}
(** Represents a single structured error or warning from the OCaml toolchain. *)

(** Represents all possible kinds of output that can result from a code
    evaluation. These are collected and sent back to the frontend for rendering.
*)
type output =
  | Stdout of string  (** Content captured from the standard output channel. *)
  | Stderr of string  (** Content captured from the standard error channel. *)
  | Value of string
      (** The formatted string representation of a toplevel expression's result
          (e.g., [`- : int = 2`]). *)
  | DisplayData of Yojson.Safe.t
      (** A rich output represented as a JSON MIME bundle, for rendering HTML,
          images, etc. *)
[@@deriving yojson]

type completions = {
  from : int;
      (** The starting position (byte offset) of the text to be replaced. *)
  to_ : int;
      (** The ending position (byte offset) of the text to be replaced. *)
  entries : Query_protocol.Compl.entry list;
      (** The list of completion entries provided by Merlin. *)
}
(** A record representing a list of completion candidates from Merlin. *)

type is_tail_position = [ `No | `Tail_position | `Tail_call ]
(** A type used by Merlin to indicate if a position is in a tail-call context.
*)

(** Converts a Merlin Location.error_source variant to a human-readable string.
*)
let report_source_to_string = function
  | Location.Lexer -> "lexer"
  | Location.Parser -> "parser"
  | Location.Typer -> "typer"
  | Location.Warning -> "warning"
  | Location.Unknown -> "unknown"
  | Location.Env -> "env"
  | Location.Config -> "config"
