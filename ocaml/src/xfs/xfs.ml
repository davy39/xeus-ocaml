(** @author Davy Cottet

    Provides a bridge between the OCaml standard library's file operations and
    the Emscripten Filesystem (FS) API. This allows standard OCaml code using
    modules like `Sys`, `In_channel`, and `Out_channel` to operate on an
    in-memory filesystem within the browser.

    The module registers a custom `js_of_ocaml` VFS (Virtual File System) device
    that translates these OCaml calls into their corresponding JavaScript calls
    on the Emscripten `FS` object. All filesystem operations are rooted at the
    `/drive/` mount point. *)

open Js_of_ocaml
open Xutil

let () = log "[XFS] Module loaded."

(** A mutable reference to cache the Emscripten FS object once it's retrieved
    from the global JavaScript scope. This avoids repeated lookups. *)
let fs_ref : Js.Unsafe.any Js.Opt.t ref = ref Js.null

(** A helper to safely retrieve the cached FS object.
    @raise Failure if the FS has not been initialized by calling {!mount_drive}.
*)
let get_fs () =
  Js.Opt.case !fs_ref
    (fun () -> failwith "Xfs.mount_drive() was not called successfully.")
    (fun fs -> fs)

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
let mount_drive () =
  try
    (* Step 1: Find and cache the Emscripten FS object if not already done. *)
    if not (Js.Opt.test !fs_ref) then (
      try
        let module_obj = Js.Unsafe.get Js.Unsafe.global (Js.string "Module") in
        let fs_obj = Js.Unsafe.get module_obj (Js.string "FS") in
        fs_ref := Js.some fs_obj;
        log
          "[XFS] mount_drive: Successfully initialized and cached the \
           Emscripten FS object."
      with exn ->
        log
          (Printf.sprintf
             "[XFS] mount_drive: CRITICAL ERROR during FS initialization: %s"
             (Printexc.to_string exn));
        raise exn (* Re-raise the exception to halt setup *));

    (* Step 2: Construct the OCaml implementation of the VFS device. *)
    log "[XFS] mount_drive: Building and mounting Emscripten device...";
    let root_path = "/drive/" in
    let resolve_impl path = root_path ^ Js.to_string path in
    let exists_impl path =
      try
        Js.to_bool
          (Js.Unsafe.meth_call (get_fs ()) "existsSync"
             [| Js.Unsafe.inject (Js.string (resolve_impl path)) |])
      with _ -> false
    in
    let is_dir_impl path =
      try
        let stats =
          Js.Unsafe.meth_call (get_fs ()) "stat"
            [| Js.Unsafe.inject (Js.string (resolve_impl path)) |]
        in
        Js.to_bool
          (Js.Unsafe.meth_call (get_fs ()) "isDir"
             [| Js.Unsafe.inject stats##.mode |])
      with _ -> false
    in
    let readdir_impl path =
      try
        let entries =
          Js.Unsafe.meth_call (get_fs ()) "readdir"
            [| Js.Unsafe.inject (Js.string (resolve_impl path)) |]
          |> Js.to_array |> Array.map Js.to_string
        in
        let filtered =
          Array.to_list entries
          |> List.filter (fun s -> s <> "." && s <> "..")
          |> Array.of_list
        in
        Js.array filtered |> Js.Unsafe.inject
      with _ -> Js.array [||] |> Js.Unsafe.inject
    in
    let mkdir_impl path perms =
      ignore
        (Js.Unsafe.meth_call (get_fs ()) "mkdir"
           [|
             Js.Unsafe.inject (Js.string (resolve_impl path));
             Js.Unsafe.inject perms;
           |])
    in
    let rmdir_impl path =
      ignore
        (Js.Unsafe.meth_call (get_fs ()) "rmdir"
           [| Js.Unsafe.inject (Js.string (resolve_impl path)) |])
    in
    let unlink_impl path =
      ignore
        (Js.Unsafe.meth_call (get_fs ()) "unlink"
           [| Js.Unsafe.inject (Js.string (resolve_impl path)) |])
    in
    let rename_impl oldp newp =
      ignore
        (Js.Unsafe.meth_call (get_fs ()) "rename"
           [|
             Js.Unsafe.inject (Js.string (resolve_impl oldp));
             Js.Unsafe.inject (Js.string (resolve_impl newp));
           |])
    in

    let open_impl path f =
      let flags_str =
        let f_obj = Js.Unsafe.coerce f in
        if f_obj##.wronly && f_obj##.rdonly then
          if f_obj##.append then "a+" else "r+"
        else if f_obj##.wronly then if f_obj##.append then "a" else "w"
        else "r"
      in
      let stream =
        Js.Unsafe.meth_call (get_fs ()) "open"
          [|
            Js.Unsafe.inject (Js.string (resolve_impl path));
            Js.Unsafe.inject (Js.string flags_str);
          |]
      in
      let read_fd_impl buf pos len =
        Js.Unsafe.meth_call (get_fs ()) "read"
          [|
            Js.Unsafe.inject stream;
            Js.Unsafe.inject buf;
            Js.Unsafe.inject pos;
            Js.Unsafe.inject len;
            Js.Unsafe.inject Js.undefined;
          |]
      in
      let write_fd_impl (buf : Typed_array.uint8Array Js.t) pos len =
        let buffer_view = buf##subarray pos (pos + len) in
        Js.Unsafe.meth_call (get_fs ()) "write"
          [|
            Js.Unsafe.inject stream;
            Js.Unsafe.inject buffer_view;
            Js.Unsafe.inject 0;
            Js.Unsafe.inject len;
            Js.Unsafe.inject Js.undefined;
          |]
      in
      let length_fd_impl () =
        let stats =
          Js.Unsafe.meth_call (get_fs ()) "fstat"
            [| Js.Unsafe.inject stream##.fd |]
        in
        stats##.size
      in
      let close_fd_impl () =
        ignore
          (Js.Unsafe.meth_call (get_fs ()) "close"
             [| Js.Unsafe.inject stream |]);
        ignore
          (Js.Unsafe.meth_call (get_fs ()) "syncfs"
             [|
               Js.Unsafe.inject (Js.bool false);
               Js.Unsafe.inject (Js.wrap_callback (fun _ -> ()));
             |])
      in
      let seek_fd_impl offset whence =
        Js.Unsafe.meth_call (get_fs ()) "llseek"
          [|
            Js.Unsafe.inject stream;
            Js.Unsafe.inject offset;
            Js.Unsafe.inject whence;
          |]
      in
      let truncate_fd_impl len =
        ignore
          (Js.Unsafe.meth_call (get_fs ()) "ftruncate"
             [| Js.Unsafe.inject stream##.fd; Js.Unsafe.inject len |])
      in
      Js.Unsafe.obj
        [|
          ("stream", Js.Unsafe.inject stream);
          ("offset", Js.Unsafe.inject 0);
          ("flags", f);
          ("read", Js.Unsafe.inject (Js.wrap_callback read_fd_impl));
          ("write", Js.Unsafe.inject (Js.wrap_callback write_fd_impl));
          ("length", Js.Unsafe.inject (Js.wrap_callback length_fd_impl));
          ("close", Js.Unsafe.inject (Js.wrap_callback close_fd_impl));
          ("seek", Js.Unsafe.inject (Js.wrap_callback seek_fd_impl));
          ("truncate", Js.Unsafe.inject (Js.wrap_callback truncate_fd_impl));
          ( "err_closed",
            Js.Unsafe.inject
              (Js.wrap_callback (fun cmd ->
                   log ("[JSOO_VFS_ERROR] " ^ Js.to_string cmd))) );
          ( "check_stream_semantics",
            Js.Unsafe.inject (Js.wrap_callback (fun _ -> ())) );
        |]
    in
    let device_obj =
      Js.Unsafe.obj
        [|
          ("root", Js.Unsafe.inject (Js.string root_path));
          ("exists", Js.Unsafe.inject (Js.wrap_callback exists_impl));
          ("is_dir", Js.Unsafe.inject (Js.wrap_callback is_dir_impl));
          ("readdir", Js.Unsafe.inject (Js.wrap_callback readdir_impl));
          ("mkdir", Js.Unsafe.inject (Js.wrap_callback mkdir_impl));
          ("rmdir", Js.Unsafe.inject (Js.wrap_callback rmdir_impl));
          ("unlink", Js.Unsafe.inject (Js.wrap_callback unlink_impl));
          ("rename", Js.Unsafe.inject (Js.wrap_callback rename_impl));
          ("open", Js.Unsafe.inject (Js.wrap_callback open_impl));
        |]
    in

    (* Step 3: Mount the device into the js_of_ocaml runtime. *)
    let jsoo_runtime =
      Js.Unsafe.get Js.Unsafe.global (Js.string "jsoo_runtime")
    in
    let jsoo_mount_point =
      Js.Unsafe.get jsoo_runtime (Js.string "jsoo_mount_point")
    in
    ignore
      (Js.Unsafe.meth_call jsoo_mount_point "push"
         [|
           Js.Unsafe.inject
             (Js.Unsafe.obj
                [|
                  ("path", Js.Unsafe.inject (Js.string root_path));
                  ("device", Js.Unsafe.inject device_obj);
                |]);
         |]);
    log "[XFS] SUCCESS: Mounted Emscripten FS device from OCaml at /drive/";

    (* Step 4: Change the current working directory to the new mount point. *)
    try
      Sys.chdir "/drive/";
      log
        (Printf.sprintf "[Toplevel] Changed current working directory to: %s"
           (Sys.getcwd ()))
    with exn ->
      log
        (Printf.sprintf
           "[Toplevel] WARNING: Could not change CWD to /drive/: %s"
           (Printexc.to_string exn))
  with exn ->
    let error_msg =
      Printf.sprintf
        "[XFS] CRITICAL: Failed to mount Emscripten FS device from OCaml: %s"
        (Printexc.to_string exn)
    in
    log error_msg
