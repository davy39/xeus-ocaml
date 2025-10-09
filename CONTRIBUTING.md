# Contributing to xeus-ocaml

First off, thank you for considering contributing to `xeus-ocaml`! This project is a community effort, and we welcome any form of contribution, from bug reports to new features. This document provides a guide for developers who want to understand the project's internals and contribute to its development.

If you have questions, please feel free to open an issue on our [GitHub issue tracker](https://github.com/davy39/xeus-ocaml/issues).

## 🏗️ Project Architecture

`xeus-ocaml` utilizes a hybrid C++ and OCaml architecture, where both languages are compiled to run within a single browser execution context. This design avoids the overhead of web workers for communication, enabling fast and direct interaction between components.

1.  **C++ Kernel Core (`xocaml.wasm`)**: The kernel's foundation is a C++ application built with `xeus-lite`. It is compiled to a WebAssembly module (`xocaml.wasm`) and is responsible for handling the Jupyter messaging protocol. It acts as the central controller, receiving requests from the Jupyter frontend and dispatching them to the OCaml backend.

2.  **OCaml Backend (`xocaml.js`)**: The OCaml code, including the toplevel environment (`xtoplevel.ml`) and Merlin integration (`xmerlin.ml`), is compiled to a single JavaScript file (`xocaml.js`) using `js_of_ocaml`. This script exposes a clean API for executing code and performing code analysis.

3.  **Direct Communication via Embind**: The C++ kernel and OCaml backend communicate directly within the browser's main thread.
    *   The `xocaml.js` file is loaded before the WASM module, making its exported functions available globally.
    *   The C++ code uses Emscripten's `emscripten::val` API (`xocaml_engine.cpp`) to make direct calls to the JavaScript functions provided by the OCaml backend.
    *   **Synchronous calls** (e.g., code completion via `call_merlin_sync`) are handled with a simple function call and return.
    *   **Asynchronous calls** (e.g., code execution via `call_toplevel_async`) are managed by passing a C++ callback function to the OCaml/JS side. The OCaml code, using its `Lwt` library for concurrency, executes the task and invokes the C++ callback upon completion.

4.  **Standard Library Management**: To balance startup performance and functionality, the kernel uses a hybrid approach for the OCaml standard library.
    *   **Static**: A core set of modules is embedded directly into the `xocaml.js` bundle at compile time using `ppx_blob` (`ocaml/src/xmerlin/static`).
    *   **Dynamic**: Additional modules are fetched dynamically from the server on-demand when the kernel first initializes (`ocaml/src/xmerlin/dynamic`).

5.  **Dynamic Library Loading (`#require`)**: The kernel supports loading pre-compiled OCaml libraries using the `#require "my_lib";;` directive.
    *   The OCaml toplevel (`xtoplevel.ml`) intercepts this directive.
    *   It uses `Library_loader.ml` to fetch a corresponding JavaScript bundle (e.g., `my_lib.js`) from a pre-configured URL.
    *   The JavaScript is executed in the global scope using `Js.Unsafe.eval_string`, which registers the OCaml modules with the `js_of_ocaml` runtime.
    *   The toplevel environment is then updated to recognize the new modules.

## 📁 Project Structure

The repository is organized into several key directories:

-   `.github/`: Contains GitHub Actions workflows for CI/CD and issue templates.
-   `include/`: Public C++ header files for the kernel interpreter.
-   `src/`: C++ source code for the kernel, including the main entry points and the bridge to the OCaml engine.
-   `ocaml/`: The root directory for all OCaml source code.
    -   `ocaml/src/`: OCaml source modules.
        -   `protocol/`: Defines the JSON communication protocol between C++ and OCaml.
        -   `xlib/`: The rich display library automatically available to users.
        -   `xmerlin/`: Merlin integration logic.
        -   `xtoplevel/`: The core OCaml toplevel evaluation logic.
        -   `xbundle/`: A command-line tool to bundle OCaml libraries into single `.js` files for `#require`.
        -   `xocaml/`: The main entry point that exports the OCaml API to JavaScript.
    -   `ocaml/tests/`: Jest test suite for the compiled JavaScript API.
-   `recipe/`: The `rattler-build` recipe for creating the final conda package.
-   `scripts/`: Utility scripts, such as for version synchronization.
-   `share/`: Jupyter kernelspec files and logos.

## 🛠️ Local Development Setup

This project uses the `pixi` package and environment manager to streamline development for both OCaml and C++/WASM components.

### Prerequisites

*   Install `pixi` by following the official [installation guide](https://pixi.sh/latest/installation/).

### Build and Run Steps

1.  **Clone the Repository**
    ```bash
    git clone https://github.com/davy39/xeus-ocaml.git
    cd xeus-ocaml
    ```

2.  **Set up the OCaml Environment**
    This command initializes an `opam` switch inside the project's `.pixi` directory, installs the OCaml compiler, and locks the project's OCaml dependencies defined in `dune-project`.
    ```bash
    pixi run -e ocaml setup
    ```

3.  **Build the OCaml Backend to JavaScript**
    This compiles all the OCaml source code into the `ocaml/_build/default/src/xocaml/xocaml.bc.js` file, which is the primary backend component.
    ```bash
    pixi run -e ocaml build
    ```

4.  **Build the WASM Kernel Package**
    This task uses `rattler-build` to execute the instructions in `recipe/recipe.yaml`. It compiles the C++ source code into `xocaml.wasm`, bundles it with the `xocaml.bc.js` from the previous step, and creates a conda package in the `output/` directory.
    ```bash
    pixi run build-kernel
    ```

5.  **Install the Kernel for JupyterLite**
    This command creates a clean `kernel` environment and installs the locally built `.conda` package into it. This makes the kernel's assets (WASM, JS, etc.) available for JupyterLite.
    ```bash
    pixi run install-kernel
    ```

6.  **Build and Serve JupyterLite**
    This command builds the static JupyterLite site, injecting the kernel from the `kernel` environment, and starts a local web server.
    ```bash
    pixi run serve-jupyterlite
    ```
    You can now access the local JupyterLite instance in your browser, typically at `http://localhost:8000`.

7.  **All-in-One Command**
    For convenience, you can run the entire build and serve process with a single command:
    ```bash
    pixi run build-all-serve
    ```

## 🧪 Testing

The project includes a Jest test suite for the JavaScript API generated from the OCaml code. These tests verify the core functionality of code evaluation and Merlin integration in isolation.

The tests are located in the `ocaml/tests/` directory. To run them, first ensure the OCaml backend is built (`pixi run -e ocaml build`), then execute:
```bash
pixi run -e test test
```

## 📦 Continuous Integration and Deployment

This project uses GitHub Actions for automated builds, testing, and deployment:

*   **`ci.yml`**: Triggered on pushes to `main`. This workflow builds the OCaml and C++ components and runs the Jest test suite. If the version in `recipe/recipe.yaml` has been updated, it automatically creates and pushes a corresponding Git tag (e.g., `v0.2.0`).
*   **`release.yml`**: Triggered when a version tag is pushed. This workflow builds the final conda package, uploads it to the `xeus-ocaml` channel on prefix.dev, creates a GitHub Release with the package as an asset, and deploys the latest JupyterLite site to GitHub Pages.
*   **`page.yml`**: A manually triggered workflow to deploy the JupyterLite site to GitHub Pages on-demand.

##  submitting-changes

We follow the standard GitHub flow for contributions:

1.  **Fork** the repository.
2.  Create a new **branch** for your feature or bug fix.
3.  Make your changes and **commit** them with clear, descriptive messages.
4.  Push your branch to your fork.
5.  Open a **Pull Request** against the `main` branch of the `davy39/xeus-ocaml` repository.

We will review your PR as soon as possible. Thank you for your contribution!
