    
<h1 align="center">
  <img src="https://raw.githubusercontent.com/jupyter-xeus/xeus/refs/heads/main/docs/source/xeus.svg" alt="xeus-logo" height="100" />
  <img src="https://upload.wikimedia.org/wikipedia/commons/f/ff/OCaml_Logo.svg" alt="xeus-ocaml logo" height="100"/>
</h1>

  

[![CI and Auto-Tagging](https://github.com/davy39/xeus-ocaml/actions/workflows/ci.yml/badge.svg)](https://github.com/davy39/xeus-ocaml/actions/workflows/ci.yml)
[![lite-badge](https://jupyterlite.rtfd.io/en/latest/_static/badge.svg)](https://davy39.github.io/xeus-ocaml/)

`xeus-ocaml` is a Jupyter kernel for the OCaml programming language that runs entirely in the web browser through WebAssembly. It is built on the `xeus-lite` library, a lightweight C++ implementation of the Jupyter protocol for WASM environments.

This kernel integrates the OCaml toplevel and the Merlin code analysis tool, providing an interactive and responsive development experience within JupyterLite without requiring a server-side backend.

## 🚀 Live Demo

Experience `xeus-ocaml` firsthand in your browser by visiting the JupyterLite deployment on GitHub Pages:

[**https://davy39.github.io/xeus-ocaml/**](https://davy39.github.io/xeus-ocaml/)


## 🐫 Build your own

You can use pixi to install jupyterlite, and then the xeus-ocaml wasm kernel :

```bash
curl -fsSL https://pixi.sh/install.sh | sh
mkdir my_jupyterlite && cd my_jupyterlite
printf "name: xeus-ocaml\nchannels:\n  - https://prefix.dev/emscripten-forge-dev\ndependencies:\n  - xeus-ocaml\n" > environment.yml
pixi init -c conda-forge -c https://repo.prefix.dev/emscripten-forge-dev
pixi add jupyterlite-core jupyterlite-xeus
pixi run jupyter lite serve --XeusAddon.environment_file=environment.yml
```


## ✨ Features

-   **Interactive OCaml Toplevel**: Execute OCaml code interactively, with persistent state between cells.
-   **Rich Language Intelligence**: Provides code completion and inspection (tooltips on hover/Shift+Tab) through an integrated Merlin engine.
-   **Virtual Filesystem**: Use standard OCaml I/O (`open_in`, `Sys.readdir`) for in-browser file operations.
-   **Dynamic Library Loading**: Load pre-compiled OCaml libraries dynamically using the `#require` directive.
-   **Rich Display Support**: Render HTML, Markdown, SVG, JSON, and even complex plots like Vega-Lite directly from your OCaml code.
-   **Graphviz Visualization**: Render graph descriptions written in the DOT language directly as SVG images.

### 💻 Interactive OCaml Toplevel

Evaluate OCaml expressions, define modules, and run functions in an interactive REPL environment. The state of your toplevel is preserved across cells, allowing you to build up your program incrementally.

#### Example

```ocaml
(* In one cell, define a function *)
let greet name = "Hello, " ^ name ^ "!";;
```
```text
val greet : string -> string = <fun>
```

```ocaml
(* In a subsequent cell, use that function *)
greet "Jupyter";;
```
```text
- : string = "Hello, Jupyter!"
```

### 🧠 Rich Language Intelligence

Leverage the power of Merlin directly in your notebook for a modern, editor-like experience.

-   **Code Completion**: Press `Tab` to get context-aware suggestions for module and function names.
-   **Code Inspection**: Press `Shift+Tab` or hover over an identifier to view its type signature and documentation.

#### Example

```ocaml
(* Place your cursor after the dot and press Tab *)
List.
```

```ocaml
(* Place your cursor on 'map' and press Shift+Tab *)
List.map
```
A tooltip will appear showing the function's signature, e.g., `('a -> 'b) -> 'a list -> 'b list`, along with its documentation.

### 💾 Virtual Filesystem

The kernel supports standard OCaml file I/O right in the browser. You can use familiar functions like `open_out`, `open_in`, and routines from the `Sys` module to create, read, and manage files in a virtual filesystem that persists for your session.

#### Example

```ocaml
(* Write to a file *)
let oc = open_out "my_data.txt" in
output_string oc "This is a test.";
close_out oc;;

(* Read it back *)
let ic = open_in "my_data.txt" in
let line = input_line ic in
close_in ic;
print_endline line;;
```

### 📦 Dynamic Libraries with `#require`

You can dynamically load additional OCaml libraries that have been pre-compiled to JavaScript. Use the standard toplevel directive `#require` followed by the library name.

```ocaml
(* Load the ocamlgraph library *)
#require "ocamlgraph";;
```
```text
Library 'ocamlgraph' loaded. New modules available: Graph, ...
```
```ocaml
(* Now you can use modules from the library *)
open Graph
```

This feature relies on the library being available as a `.js` file at a URL accessible to the kernel.

### 📊 Rich Display and Visualization

The kernel comes with a built-in `Xlib` library that is **automatically opened** on startup, so its functions are immediately available in the global scope. This library provides a simple API for rendering a wide variety of rich outputs in your notebook cells.

Here are some of the key functions available:

| Function                | Description                                                |
| ----------------------- | ---------------------------------------------------------- |
| `output_html s`         | Renders a raw HTML string `s`.                             |
| `output_markdown s`     | Renders a Markdown string `s`.                             |
| `output_svg s`          | Renders an SVG image from its XML string `s`.              |
| `output_dot s`          | Renders a Graphviz DOT language string `s` as an SVG graph.|
| `output_json s`         | Renders a JSON string `s` as a collapsible tree view.      |
| `output_vegalite s`     | Renders an interactive Vega-Lite plot from a JSON spec `s`.|
| `output_png_base64 s`   | Displays a PNG image from a Base64-encoded string `s`.     |
| `output_jpeg_base64 s`  | Displays a JPEG image from a Base64-encoded string `s`.    |

#### Example Usage

You can call these functions directly in any cell to produce rich outputs.

```ocaml
(* Render an interactive Vega-Lite chart *)
let vega_spec = {|
  {
    "$schema": "https://vega.github.io/schema/vega-lite/v5.json",
    "description": "A simple bar chart with embedded data.",
    "data": {
      "values": [
        {"a": "A", "b": 28}, {"a": "B", "b": 55}, {"a": "C", "b": 43},
        {"a": "D", "b": 91}, {"a": "E", "b": 81}, {"a": "F", "b": 53}
      ]
    },
    "mark": "bar",
    "encoding": {
      "x": {"field": "a", "type": "nominal", "axis": {"labelAngle": 0}},
      "y": {"field": "b", "type": "quantitative"}
    }
  }
|} in
output_vegalite vega_spec
```

#### Graphviz (DOT Language) Visualization

You can render graphs described in the DOT language using `output_dot`. The kernel includes a frontend extension that uses `viz.js` to render the DOT string into an SVG image.

```ocaml
(* Define a simple directed graph in DOT language *)
let dot_string = {|
  digraph G {
    rankdir="LR";
    a [label="Start"];
    b [label="Step 2"];
    c [label="End"];
    a -> b;
    b -> c;
    a -> c [label="shortcut"];
  }
|};;

(* Render the graph *)
output_dot dot_string;;
```

## 🛠️ Contributing and Development

We welcome contributions! If you're interested in the project's architecture, setting up a local development environment, or contributing code, please see our **[CONTRIBUTING.md](CONTRIBUTING.md)** guide for detailed information.

## 🗺️ Roadmap

### Implemented
-   [x] Interactive code execution via the `js_of_ocaml` toplevel.
-   [x] Code completion powered by an in-browser Merlin instance.
-   [x] Code inspection for tooltips (Shift+Tab) and the inspector panel.
-   [x] **Virtual Filesystem**: Read and write to the Emscripten virtual filesystem from OCaml using standard library functions (`open_in`, `Sys.readdir`, etc.).
-   [x] **Rich Outputs**: Display HTML, Markdown, SVG, JSON, Vega-Lite plots, and graphviz dot graphs directly from OCaml code using the auto-opened `Xlib` module.
-   [x] **Library Management**: Dynamically fetch and load pre-compiled OCaml libraries from within a notebook session via the `#require "my_lib";;` directive. Try it with `ocamlgraph`

### Future Work
-   [ ] **User Input**: Add support for Jupyter's `input_request` messages to allow interactive OCaml functions like `read_line()` that wait for user input from the console.
-   [ ] **Custom Widgets**: Develop a communication bridge (`Comm`) to enable OCaml code to interact with Jupyter Widgets for creating rich, interactive outputs.

## 🙏 Acknowledgements

This project is made possible by the outstanding work of several open-source communities:

*   **The `xeus` Project**: The core architecture relies on **[xeus](https://github.com/jupyter-xeus/xeus)** for its robust implementation of the Jupyter protocol and **[xeus-lite](https://github.com/jupyter-xeus/xeus-lite)** for the ability to compile to WebAssembly.
*   **The OCaml Toolchain**: The in-browser OCaml experience is powered by **[js_of_ocaml](https://github.com/ocsigen/js_of_ocaml)**, which compiles OCaml bytecode to efficient JavaScript, and the **[Merlin](https://github.com/ocaml/merlin)** project for code analysis.

## 📜 License

This project is distributed under the terms of the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for details.
