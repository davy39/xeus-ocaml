/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#include "xocaml_engine.hpp"

#include <iostream>
#include <emscripten/bind.h>

// Enables detailed logging for debugging purposes.
#define DEBUG_XOCAML

#ifdef DEBUG_XOCAML
#define XOCAML_LOG(channel, message) std::cout << "[xeus-ocaml][" << channel << "] " << message << std::endl
#else
#define XOCAML_LOG(channel, message)
#endif

namespace xeus_ocaml
{
    namespace ocaml_engine
    {
        /**
         * @brief Synchronously executes a Merlin command.
         * @param request The JSON request payload for the Merlin action.
         * @return A JSON object with the result.
         */
        nl::json call_merlin_sync(const nl::json& request)
        {
            XOCAML_LOG("Merlin Sync Request", request.dump(2));
            try
            {
                // Get a handle to the globally exported 'xocaml' JavaScript object.
                emscripten::val xocaml = emscripten::val::global("xocaml");
                
                // Call the synchronous Merlin action handler and get the JSON string response.
                std::string response_str = xocaml.call<std::string>("processMerlinAction", request.dump());
                
                XOCAML_LOG("Merlin Sync Response", response_str);
                return nl::json::parse(response_str);
            }
            catch (const std::exception& e)
            {
                std::cerr << "[xeus-ocaml] Exception in call_merlin_sync: " << e.what() << std::endl;
                // Return a structured error to ensure the caller can handle it gracefully.
                return {{"class", "error"}, {"value", "C++ exception during Merlin sync call."}};
            }
        }

        /**
         * @brief Asynchronously executes a Toplevel command.
         * @param request The JSON request payload for the Toplevel action.
         * @param callback The JavaScript-bound callback to invoke with the result.
         */
        void call_toplevel_async(const nl::json& request, emscripten::val callback)
        {
            XOCAML_LOG("Toplevel Async Request", request.dump(2));
            try
            {
                // Get a handle to the globally exported 'xocaml' JavaScript object.
                emscripten::val xocaml = emscripten::val::global("xocaml");
                
                // Call the asynchronous Toplevel action handler, passing the request and the callback.
                xocaml.call<void>("processToplevelAction", request.dump(), callback);
            }
            catch (const std::exception& e)
            {
                std::cerr << "[xeus-ocaml] Exception in call_toplevel_async: " << e.what() << std::endl;
                // As this is an async call, we cannot return an error directly.
                // The OCaml/JS side is expected to handle its own errors and report them
                // via the callback mechanism. This catch block is for C++-side exceptions only.
            }
        }
    } // namespace ocaml_engine
} // namespace xeus_ocaml