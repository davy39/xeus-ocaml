(** {1 Library and Artifact Loader}
    @author Davy Cottet

    Interface for loading OCaml library files and Merlin artifacts into the
    browser's virtual filesystem. This module is the central point for managing
    the files required for both the OCaml toplevel and the Merlin code analysis
    engine.

    It supports a hybrid loading strategy:
    - Statically embedding critical files at build time.
    - Dynamically fetching standard library files at kernel startup.
    - Dynamically fetching third-party libraries on-demand via `#require`. *)

val setup : base_url:string -> unit Lwt.t
(** Performs the initial file setup for the kernel environment.

    This function orchestrates the loading of all files necessary for the OCaml
    standard library to function correctly within the toplevel and Merlin. It
    first writes any statically-linked files (like `stdlib.cmi`) to the virtual
    filesystem, then asynchronously fetches all other standard library artifacts
    (`.cmt`, `.cmti`, and other `.cmi` files) from the server.

    This function must be called and awaited successfully *before* the OCaml
    toplevel or Merlin engine are initialized to prevent `Env.Error` exceptions.

    @param base_url
      The root URL from which to fetch the dynamic standard library files.
    @return A promise that resolves when all initial files have been loaded. *)

val load_on_demand :
  base_url:string ->
  name:string ->
  (Protocol.output, Protocol.output) result Lwt.t
(** Dynamically loads a pre-compiled third-party OCaml library on-demand.

    This function is triggered by the toplevel when it encounters a `#require
    "lib_name"` directive. It looks up the library in a pre-generated manifest
    (`external_libs.ml`), then fetches the corresponding JavaScript bundle and
    all its Merlin artifacts (`.cmi`, `.cmt`, `.cmti`).

    The JavaScript bundle is executed to make the library's modules available,
    and the artifacts are written to the virtual filesystem to enable code
    completion and documentation for the new library.

    @param base_url
      The root URL where the library's `.js` bundle and artifact files are
      stored.
    @param name The name of the library to load (e.g., "ocamlgraph").
    @return
      A promise that resolves to a result, containing either a success message
      for display in the notebook output, or an error message if the library
      could not be found or loaded. *)
