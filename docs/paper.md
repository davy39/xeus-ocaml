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
This serverless approach addresses the critical challenge of environment setup in educational and research settings. It provides an instantly accessible, reproducible, and scalable OCaml environment, lowering barriers to entry for students and enhancing the reproducibility of computational artifacts.

# Statement of Need

Jupyter notebooks have become a standard for creating reproducible scientific workflows in various fields [@Beg2021; @Siddik2025]. In particular, they have been adopted as a powerful tool in education science research across numerous STEM disciplines such as robotics [@Ruiz-Sarmiento2021], structural analysis [@Suárez2021], materials informatics [@Chen2022], physics [@Sutrini2022], bioinformatics [@Gupta2023], as well as algorithm design [@Topsakal2023]. By integrating code, narrative, and visualizations, notebooks facilitate active learning and make complex computational topics more accessible [@Fruchart2022].

However, a significant barrier persists for compiled languages like OCaml: the complex local setup. This "setup friction" particularly impacts educational programs like the French Classes Préparatoires aux Grandes Écoles (CPGE), where OCaml is a mandatory language for approximately 2500 students annually [@Schul2024]. Students across diverse computing environments often lack the permissions or experience to manage complex toolchains, diverting classroom time from core learning objectives to technical troubleshooting.

xeus-ocaml is research software designed to eliminate this barrier by providing a zero-installation, browser-based OCaml environment. It offers a complete, self-hosted JupyterLab experience that distinguishes it from alternatives. Unlike tools limited to simple expressions (e.g., *Try OCaml*) or those lacking full Jupyter integration and code intelligence (e.g., *Basthon.fr*), xeus-ocaml provides a persistent, feature-rich environment. Furthermore, its serverless, client-side architecture avoids the infrastructure overhead of Docker-based solutions, the commercial dependency of cloud platforms like *GitHub Colab*, and provides full offline capability.

This design allows educators to deploy standardized learning environments via a simple URL, enabling them to focus on pedagogical research rather than infrastructure management. Beyond education, the serverless architecture provides key advantages for research, including the creation of durable, self-contained artifacts, scalable access for large user bases without proportional server costs, and reduced energy consumption by distributing computation to user devices.


# Features and applications

`xeus-ocaml` implements the full Jupyter Messaging Protocol to deliver a modern, interactive experience, with features that directly support educational and research goals:

*   **Interactive Toplevel Execution**: Code is evaluated in a persistent toplevel, enabling the exploratory, iterative workflow that is central to both functional programming research and inquiry-based learning.
*   **Merlin Code Intelligence**: The integrated Merlin [@merlin] instance provides context-aware code completion and on-demand type inspection. This support lowers the barrier for newcomers, allowing them to focus on algorithmic concepts rather than syntactic details.
*   **Virtual Filesystem**: The kernel's in-memory filesystem is critical for packaging code and data together. This allows for the creation of self-contained, reproducible artifacts where the computational environment is fully encapsulated.
*   **Dynamic Library Loading**: The ability to load pre-compiled OCaml libraries via the `#require` directive allows instructors and researchers to craft domain-specific environments for teaching data structures, graphics, or other specialized topics.
*   **Rich Display System**: A built-in `Xlib` library facilitates the rendering of diverse MIME types (HTML, SVG, Graphviz, Vega-Lite). This is crucial for creating the rich, narrative-driven notebooks that are effective for both modern pedagogy and reproducible research communication.

# Availability

The source code for `xeus-ocaml` is available on GitHub ([https://github.com/davy39/xeus-ocaml](https://github.com/davy39/xeus-ocaml)) under the GNU General Public License v3.0. A mature CI/CD pipeline ensures software reliability and reproducibility. `xeus-ocaml` is distributed as a WebAssembly-native conda package on the `emscripten-forge` channel, simplifying its integration into custom JupyterLite deployments. An official demo provides an up-to-date, interactive environment for end-users.

# Acknowledgements

This project builds on the foundational work of the `xeus`, `js_of_ocaml`, `Merlin`, and `Emscripten` open-source projects. We thank their developers and communities for creating the powerful tools that made `xeus-ocaml` possible.

# References
