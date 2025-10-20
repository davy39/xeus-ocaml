(** @author Davy Cottet

    Provides a bridge between the OCaml standard library's file operations and
    the Emscripten Filesystem (FS) API. This allows standard OCaml code using
    modules like `Sys`, `In_channel`, and `Out_channel` to operate on an
    in-memory filesystem within the browser.

    The module registers a custom `js_of_ocaml` VFS (Virtual File System) device
    that translates these OCaml calls into their corresponding JavaScript calls
    on the Emscripten `FS` object. All filesystem operations are rooted at the
    `/drive/` mount point. Based on
    https://github.com/ocsigen/js_of_ocaml/blob/master/runtime/js/fs.js and
    https://github.com/ocsigen/js_of_ocaml/blob/master/runtime/js/fs_fake.js *)

val mount_drive : unit -> unit
(** Initializes the connection to the Emscripten FS and mounts it as a device at
    `/drive/` within the `js_of_ocaml` VFS.

    This is the primary setup function for all filesystem functionality in the
    kernel and must be called once at startup before any file I/O is attempted.

    Internally, this function performs the following steps: 1. Lazily finds and
    caches the global `Module.FS` object provided by the Emscripten runtime. 2.
    Constructs a JavaScript "device" object that maps OCaml VFS operations
    (e.g., `exists`, `readdir`, `open`) to the corresponding Emscripten `FS`
    methods. 3. Pushes this device object onto the
    `jsoo_runtime.jsoo_mount_point` array, making it active. 4. Attempts to
    change the current working directory of the OCaml process to `/drive/`.

    The function includes error handling and will log critical failures to the
    console if the Emscripten `FS` object cannot be found or the device fails to
    mount. *)
