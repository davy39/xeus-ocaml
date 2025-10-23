---
title: 'xeus-ocaml: A Hybrid WebAssembly and JavaScript Kernel for OCaml in the Browser'
tags:
  - ocaml
  - jupyter
  - jupyterlite
  - webassembly
  - javascript
  - functional programming
  - education
  - reproducible science
authors:
  - name: Davy Cottet
    orcid: 0009-0006-5378-1295
    corresponding: true
    affiliation: 1
affiliations:
 - name: Lycée Expérimental de Saint-Nazaire, France 
   index: 1
date: 23 October 2025 
bibliography: paper.bib
---

# Summary

`xeus-ocaml` is a Jupyter kernel for the OCaml programming language that runs entirely within a web browser using a hybrid WebAssembly (WASM) and JavaScript architecture. Its foundation is a C++ application built with `xeus-lite` [@xeus-lite], which handles the Jupyter protocol and is compiled to WASM. All OCaml logic—the interactive toplevel, the Merlin code analysis tool [@merlin], and support libraries—is compiled to a separate JavaScript bundle via `js_of_ocaml` [@js_of_ocaml]. These two components communicate directly in the browser using the Emscripten API [@emscripten], providing a responsive, serverless OCaml environment for JupyterLite [@jupyterlite].

# Statement of Need

The OCaml programming language is widely used in academia and industry for its strong type system and performance. However, setting up a local development environment, including the compiler, package manager, and build tools, can be a significant barrier for newcomers, particularly in educational contexts where students use diverse and often restricted computing environments.

`xeus-ocaml` directly addresses this challenge for a key educational demographic: students in the French *Classes Préparatoires aux Grandes Écoles* (CPGE). In the MP2I and MPI tracks, OCaml is the mandatory programming language for the computer science curriculum. `xeus-ocaml` provides a transformative solution by offering a standardized, equitable, and instantly accessible OCaml environment through a simple URL. This eliminates setup friction, allowing educators to focus on pedagogy and students to begin coding immediately, regardless of their operating system or device.

Furthermore, `xeus-ocaml` offers a compelling alternative to resource-intensive, server-based infrastructure like JupyterHub [@jupyterhub]. By performing all computations on the client-side—through a combination of WebAssembly for the kernel machinery and JavaScript for OCaml execution—this model offers substantial benefits:
-   **Reduced Administrative Overhead:** It eliminates the need to deploy, manage, and scale centralized servers, as deployment consists of simple static file hosting.
-   **Scalability and Cost-Effectiveness:** The computational load is distributed across users' machines, allowing the system to scale to a large number of concurrent users without incurring proportional server costs.
-   **Energy Efficiency:** By offloading computation from centralized, always-on servers to the client device, this model can significantly reduce the energy consumption and carbon footprint of the supporting IT infrastructure, contributing to more sustainable scientific computing practices.

# Core Features

`xeus-ocaml` implements the full Jupyter Messaging Protocol to deliver a modern, interactive experience:

*   **Interactive Toplevel Execution**: Code is evaluated via the `js_of_ocaml-toplevel` JavaScript library, with persistent state between notebook cells.
*   **Merlin Code Intelligence**: An integrated Merlin instance, running as JavaScript, provides context-aware code completion and on-demand documentation/type inspection.
*   **Virtual Filesystem**: The kernel maps OCaml's standard file I/O operations to an in-memory Emscripten filesystem, allowing both the WASM and JavaScript components to interact with files in the browser.
*   **Dynamic Library Loading**: Through the standard `#require` directive, users can dynamically load third-party OCaml libraries that have been pre-compiled to JavaScript.
*   **Rich Display System**: A built-in `Xlib` library is automatically opened on startup, allowing users to render a variety of MIME types, including HTML, Markdown, SVG, Graphviz, and interactive Vega-Lite plots, directly from their OCaml code.

# Availability

The source code for `xeus-ocaml` is available on GitHub ([https://github.com/davy39/xeus-ocaml](https://github.com/davy39/xeus-ocaml)) under the GNU General Public License v3.0. The project is developed with a mature CI/CD pipeline that automates testing, packaging, and deployment, ensuring software reliability and reproducibility.

For developers building custom JupyterLite websites, `xeus-ocaml` is packaged and distributed as a WebAssembly-native conda package. In line with other `xeus-lite` kernels, it is available from the `emscripten-forge` channel on `prefix.dev`. This standardized distribution simplifies integration into JupyterLite builds.

The easiest way for end-users to interact with the kernel is through the official JupyterLite demo, which is kept up-to-date with the latest release and hosted on GitHub Pages.

# Acknowledgements

This project builds on the foundational work of the `xeus`, `js_of_ocaml`, `Merlin`, and `Emscripten` open-source projects. We thank their developers and communities for creating the powerful tools that made `xeus-ocaml` possible.

# References