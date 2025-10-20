(** @author Davy Cottet

    This module is the main entry point for the entire OCaml side of the
    `xeus-ocaml` kernel. When compiled with `js_of_ocaml`, it produces the
    `xocaml.js` bundle.

    Its primary responsibility is to expose a well-defined JavaScript API that
    the C++ part of the kernel (running as WebAssembly) can call into. This API
    is registered in the global JavaScript scope under the `xocaml` object.

    The exported API consists of three key functions:

    - `processMerlinAction(jsonString)`: A **synchronous** function for handling
      quick, non-blocking code intelligence requests (completion, inspection,
      etc.). It takes a JSON string and immediately returns a JSON string.

    - `processToplevelAction(jsonString, callback)`: An **asynchronous**
      function for handling potentially long-running operations like code
      evaluation (`Eval`) or the initial kernel setup (`Setup`). It takes a JSON
      string and a JavaScript callback function. It returns immediately, and the
      result (as a JSON string) is delivered later by invoking the provided
      callback.

    - `mountFS()`: A function to trigger the mounting of the Emscripten virtual
      filesystem device from within OCaml.

    This module orchestrates the initialization sequence and delegates incoming
    requests to the appropriate sub-modules (`Xmerlin`, `Xtoplevel`,
    `Xlibloader`). *)
