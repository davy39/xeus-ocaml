(** @author Davy Cottet

    This module serves as the primary bridge between the `xeus-ocaml` kernel's
    protocol and the Merlin code analysis library. It is responsible for
    handling all synchronous code intelligence requests, such as code
    completion, type inspection, and error checking. It operates on a virtual
    filesystem (VFS) that must be populated with the necessary Merlin artifacts
    (`.cmi`, `.cmt`, `.cmti`) by the {!Xlibloader} module before this module is
    initialized. *)

val initialize : unit -> unit
(** Initializes the Merlin configuration. This function should be called exactly
    once during kernel startup, immediately after the {!Xlibloader.setup}
    function has successfully completed. It finalizes the configuration Merlin
    will use to find standard library modules in the virtual filesystem. *)

val process_merlin_action : Protocol.action -> Yojson.Basic.t option
(** Processes a synchronous, Merlin-related action from the kernel protocol.

    This is the main entry point for handling code intelligence requests. It
    takes a protocol action, determines if it's a command intended for Merlin,
    and if so, executes the corresponding Merlin query (e.g., `Complete_prefix`,
    `Type_enclosing`).

    @param action The {!Protocol.action} to be processed.
    @return
      It returns [`Some json_result`] if the action was a Merlin command and was
      processed successfully. It returns [`None`] if the action is not a Merlin
      command (e.g., `Eval`), indicating that another part of the system should
      handle it. *)
