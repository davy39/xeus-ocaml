/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#ifndef XEUS_OCAML_ENGINE_HPP
#define XEUS_OCAML_ENGINE_HPP

#include <string>
#include "nlohmann/json.hpp"
#include <emscripten/val.h>


namespace nl = nlohmann;

/**
 * @namespace xeus_ocaml
 * @brief The main namespace for the xeus-ocaml kernel.
 */
namespace xeus_ocaml
{
    /**
     * @namespace ocaml_engine
     * @brief Provides a C++ bridge for interacting with the OCaml backend compiled to JavaScript.
     *
     * This namespace abstracts away the Emscripten/Embind specifics of calling
     * into the JavaScript environment, offering a clean, type-safe C++ API for
     * Merlin (synchronous) and Toplevel (asynchronous) actions.
     */
    namespace ocaml_engine
    {
        /**
         * @brief Synchronously executes a Merlin command and returns the result.
         *
         * This function is intended for quick, non-blocking operations like code
         * completion or type inspection. It directly calls the `processMerlinAction`
         * function exported by the OCaml/JS module.
         *
         * @param request A JSON object representing the Merlin action and its payload,
         *                conforming to the protocol defined in `protocol.ml`.
         * @return A JSON object containing the response from the Merlin backend.
         *         In case of an error, it returns a JSON object with a "class" of "error".
         */
        nl::json call_merlin_sync(const nl::json& request);

        /**
         * @brief Asynchronously executes a Toplevel command.
         *
         * This function is used for potentially long-running operations like code
         * execution (`Eval`) or environment setup (`Setup`). It calls the
         * `processToplevelAction` function exported by the OCaml/JS module and
         * passes a C++ callback function that will be invoked upon completion.
         *
         * @param request A JSON object representing the Toplevel action and its payload.
         * @param callback An Emscripten value (`emscripten::val`) representing the
         *                 JavaScript-bound callback function to be executed with the result.
         */
        void call_toplevel_async(const nl::json& request, emscripten::val callback);
    }
}

#endif // XEUS_OCAML_ENGINE_HPP