# ![xeus-ocaml logo](https://raw.githubusercontent.com/davy39/xeus-ocaml/refs/heads/main/share/jupyter/kernels/xocaml/logo-64x64.png)

[![CI Workflow](https://github.com/davy39/xeus-ocaml/actions/workflows/ci.yml/badge.svg)](https://github.com/davy39/xeus-ocaml/actions/workflows/ci.yml)
[![Release Workflow](https://github.com/davy39/xeus-ocaml/actions/workflows/release.yml/badge.svg)](https://github.com/davy39/xeus-ocaml/actions/workflows/release.yml)
[![GitHub Pages](https://img.shields.io/badge/github--pages-deployed-success)](https://davy39.github.io/xeus-ocaml/)

`xeus-ocaml` is a modern Jupyter kernel for the OCaml programming language, designed to run entirely in the web browser using WebAssembly. It is built upon the `xeus` C++ library, a native implementation of the Jupyter protocol.

This kernel provides a lightweight, serverless OCaml environment within JupyterLite, offering features like code completion and inspection powered by OCaml's Merlin toolchain.

## ✨ Features

*   **Fully Browser-Based**: Runs entirely in the browser with no server-side setup required, thanks to WebAssembly.
*   **Interactive OCaml Toplevel**: Execute OCaml code interactively in a Jupyter notebook.
*   **Rich Language Features**: Provides code completion and inspection (tooltips) by communicating with an in-browser Merlin worker.
*   **JupyterLite Integration**: Designed from the ground up for seamless integration with JupyterLite.
*   **Frontend-Kernel Communication**: Includes a JupyterLab extension to execute frontend commands (e.g., triggering the completer) directly from the kernel.

## 🚀 Live Demo

You can try `xeus-ocaml` live in your browser by visiting the JupyterLite deployment on GitHub Pages:

[**https://davy39.github.io/xeus-ocaml/**](https://davy39.github.io/xeus-ocaml/)

## 🙏 Acknowledgements

This project stands on the shoulders of giants and would not be possible without the incredible work of the following projects:

*   **The `xeus` Project**: `xeus-ocaml` is built directly on top of the **[xeus](https://github.com/jupyter-xeus/xeus)** C++ library. The ability to compile this kernel to WebAssembly and run it entirely in the browser is made possible by **[xeus-lite](https://github.com/jupyter-xeus/xeus-lite)**, a project specifically designed for creating WASM-based Jupyter kernels. The `xeus` ecosystem is foundational to this kernel's existence.

*   **The OCaml Web Worker**: Much credit is due to Arthur Wendling for his **[x-ocaml worker](https://github.com/art-w/x-ocaml)**, which provides the OCaml toplevel and Merlin integration compiled to JavaScript with **[js_of_ocaml](https://github.com/ocsigen/js_of_ocaml)**.

## 🛠️ Getting Started & Local Development

This project uses the `pixi` package manager to handle both the native (Linux) and WebAssembly environments.

### Prerequisites

You need to have `pixi` installed. You can find installation instructions [here](https://pixi.sh/latest/installation/).

### Running Locally

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/davy39/xeus-ocaml.git
    cd xeus-ocaml
    ```

2.  **Install all dependencies:**
    This command will set up the necessary environments, including the WASM toolchain and Node.js dependencies for the extension.
    ```bash
    pixi install
    ```

3.  **Run the local JupyterLite server:**
    This command will build the kernel and the JupyterLab extension, then launch a local JupyterLite instance with the `xeus-ocaml` kernel.
    ```bash
    pixi run build-all
    pixi run serve-jupyterlite
    ```
    You can now access the JupyterLite interface in your web browser.

## 🏗️ How It Works

The `xeus-ocaml` kernel has a unique architecture that combines C++, OCaml, and TypeScript, all compiled to run in the browser.

1.  **C++ Kernel Core (`xeus-lite`)**: The core of the kernel is written in C++ using the `xeus` framework. It is compiled to WebAssembly (`xocaml.wasm`) and runs in the main browser thread, handling Jupyter protocol messages.
2.  **OCaml Web Worker**: The OCaml toplevel and the Merlin inspection/completion engine run in a separate Web Worker (`x-ocaml.worker+effects.js`). This prevents the UI from freezing during code execution or analysis.
3.  **JupyterLab Extension**: A small companion JupyterLab extension (`/extension`) establishes a communication channel (`Comm`) that allows the kernel to send commands back to the JupyterLab frontend, for instance, to programmatically trigger the autocompleter UI.

### The OCaml Web Worker

A critical component of `xeus-ocaml` is the OCaml Web Worker, which handles all the language-specific heavy lifting. This worker runs the OCaml runtime, toplevel, and analysis tools in a separate browser thread.

*   **Code Execution**: It uses the standard OCaml `toplevel/toploop` library to execute code entered into notebook cells.
*   **Autocompletion and Typing**: For rich language features, it leverages a `js_of_ocaml` port of the Merlin inspection tool, available at **[voodoos/merlin-js](https://github.com/voodoos/merlin-js)**.

The C++ kernel communicates with this worker by sending and receiving **JSON messages** via the browser's `postMessage` API. The kernel sends requests for execution, completion, or inspection, and the worker sends back results, outputs (`stdout`/`stderr`), or Merlin analysis data. This decoupled architecture ensures a responsive user experience.

## 🔧 Building from Source

The project is configured with `pixi` tasks to simplify the build process.

*   **Build everything (Extension, Kernel, and JupyterLite site):**
    ```bash
    pixi run build-all
    ```
    This command runs the following steps in sequence:
    1.  `build-extension`: Compiles the TypeScript JupyterLab extension.
    2.  `build-kernel`: Compiles the C++ kernel to WebAssembly using `rattler-build` and the recipe in `/recipe`.
    3.  `install-kernel`: Installs the compiled WASM artifacts into a local `pixi` environment.
    4.  `build-jupyterlite`: Bundles the kernel and extension into a static JupyterLite site in the `_output` directory.

## 📦 Continuous Integration and Deployment

The project uses GitHub Actions for CI/CD:

*   **`ci.yml`**: On every push to `main`, this workflow builds and tests the kernel and extension. If the version in `recipe/recipe.yaml` is updated, it automatically creates and pushes a new version tag (e.g., `v0.1.0`).
*   **`release.yml`**: When a new version tag is pushed, this workflow:
    1.  Builds the Conda package for the kernel.
    2.  Uploads the package to the `xeus-ocaml` channel on `prefix.dev`.
    3.  Creates a new GitHub Release with the package as an asset.
    4.  Builds and deploys the JupyterLite site to GitHub Pages.

## 📜 License

This software is licensed under the **GNU General Public License v3**. See the [LICENSE](LICENSE) file for details.