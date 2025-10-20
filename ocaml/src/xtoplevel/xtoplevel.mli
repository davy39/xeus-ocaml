(** {1 OCaml Toplevel (REPL)}
    @author Davy Cottet

    This module implements the core Read-Eval-Print Loop (REPL) functionality
    for the `xeus-ocaml` kernel. It is responsible for initializing the OCaml
    toplevel environment and for executing user-provided code.

    The module relies on the `js_of_ocaml-toplevel` library for the underlying
    evaluation mechanism. It enhances this by capturing all forms of output
    (stdout, stderr, toplevel values, and rich display data from the {!Xlib}
    module) and handling special toplevel directives like `#require`.

    {b CRITICAL}: The {!setup} function in this module must only be called
    *after* the {!Xlibloader.setup} function has successfully completed to
    ensure the necessary standard library files are present in the virtual
    filesystem. *)

val setup : url:string -> unit
(** Initializes the OCaml toplevel environment.

    This function performs the final steps of the kernel's OCaml-side setup. It
    must be called after the virtual filesystem has been populated by
    {!Xlibloader.setup}.

    Its main tasks are:
    - Initializing the `js_of_ocaml` toplevel machinery.
    - Creating the initial compiler environment, which requires `stdlib.cmi`.
    - Automatically opening the {!Xlib} module to make rich display functions
      globally available to the user.

    @param url
      The base URL where third-party library files are located. This is stored
      and used later when handling `#require` directives.
    @before 0.1.0
      This function has significant side effects, creating and modifying the
      global state of the OCaml toplevel environment. It should only be called
      once at kernel startup. *)

val eval : string -> Protocol.output list Lwt.t
(** Parses and evaluates a string of OCaml code.

    This is the main execution function for the kernel. It takes a block of
    code, splits it into individual toplevel phrases (ending in `;;`), and
    executes them sequentially.

    It captures all outputs generated during execution, including standard
    streams, the printed value of the last expression, and any rich outputs
    created via the {!Xlib} module. It also provides special handling for the
    `#require "lib_name"` directive by delegating to the
    {!Xlibloader.load_on_demand} function.

    @param code The string of OCaml code to evaluate.
    @return
      A promise that resolves to a list of all captured {!Protocol.output}
      items, which will be sent to the Jupyter frontend for display. *)
