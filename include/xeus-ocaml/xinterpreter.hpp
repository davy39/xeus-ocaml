/***************************************************************************
 * Copyright (c) 2025, Davy Cottet
 * Copyright (c) 2024, The xeus-ocaml Authors
 *
 * Distributed under the terms of the BSD 3-Clause License.
 *
 * The full license is in the file LICENSE, distributed with this software.
 ****************************************************************************/

/**
 * @file xinterpreter.hpp
 * @brief Contains the declaration of the xeus-ocaml interpreter.
 *
 * This file defines the main `interpreter` class for the xeus-ocaml kernel,
 * which handles communication with a WebAssembly OCaml worker to execute code,
 * provide completions, and perform inspections.
 */

#ifndef XEUS_OCAML_INTERPRETER_HPP
#define XEUS_OCAML_INTERPRETER_HPP

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "nlohmann/json.hpp"
#include "xeus/xcomm.hpp"
#include "xeus/xguid.hpp"
#include "xeus/xinterpreter.hpp"

#include <emscripten/val.h>

namespace emscripten { class val; }

/**
 * @brief Global callback function exposed to JavaScript.
 *
 * This function serves as the C++ entry point for messages sent from the OCaml
 * Web Worker. It forwards the message data to the singleton `interpreter` instance.
 * @param event The JavaScript message event from the worker.
 * @see EMSCRIPTEN_BINDINGS
 */
void global_on_message_callback(emscripten::val event);

/**
 * @namespace xeus_ocaml
 * @brief The main namespace for the xeus-ocaml kernel implementation.
 */
namespace xeus_ocaml
{
    namespace nl = nlohmann;

    /**
     * @class interpreter
     * @brief The OCaml interpreter for the xeus kernel.
     *
     * The `interpreter` class inherits from `xeus::xinterpreter` and implements
     * the core logic for an OCaml Jupyter kernel running in WebAssembly. It acts as a
     * bridge between the Jupyter protocol (managed by xeus) and an OCaml Web Worker,
     * which runs the Merlin and OCaml toplevel.
     */
    class interpreter : public xeus::xinterpreter
    {
    public:
        /**
         * @brief Constructs the interpreter and registers it with xeus.
         */
        interpreter();
        
        /**
         * @brief Default virtual destructor.
         */
        virtual ~interpreter() = default;

        /**
         * @brief Handles incoming messages from the OCaml Web Worker.
         *
         * This is the central message processing function. It parses the JSON message
         * from the worker and dispatches it to the appropriate handler (e.g., for
         * execution results, completions, or inspections).
         *
         * @param message A JSON string received from the worker.
         */
        void on_message_callback(const std::string& message);

    private:
        /**
         * @name xeus::xinterpreter implementation
         * @{
         */

        /**
         * @brief Configures the interpreter, setting up the OCaml worker communication.
         */
        void configure_impl() override;

        /**
         * @brief Forwards a code execution request to the OCaml worker.
         */
        void execute_request_impl(send_reply_callback cb, int execution_counter, const std::string& code, xeus::execute_request_config config, nl::json user_expressions) override;
        
        /**
         * @brief Forwards a code completion request to the OCaml worker.
         */
        nl::json complete_request_impl(const std::string& code, int cursor_pos) override;

        /**
         * @brief Forwards a code inspection (tooltip) request to the OCaml worker.
         */
        nl::json inspect_request_impl(const std::string& code, int cursor_pos, int detail_level) override;

        /**
         * @brief Determines if a code block is complete and ready for execution.
         */
        nl::json is_complete_request_impl(const std::string& code) override;

        /**
         * @brief Provides information about the kernel.
         */
        nl::json kernel_info_request_impl() override;

        /**
         * @brief Handles a shutdown request from the client.
         */
        void shutdown_request_impl() override;

        /** @} */

        /**
         * @name OCaml worker message handlers
         * @{
         */

        /**
         * @brief Dispatches a Merlin-specific response to the correct handler.
         * @param merlin_answer The JSON payload of the Merlin response.
         */
        void handle_merlin_response(const nl::json& merlin_answer);

        /**
         * @brief Processes a `Completions` response from Merlin.
         * @param completion_data The JSON data for the completions.
         */
        void handle_completion_response(const nl::json& completion_data);

        /**
         * @brief Processes a `Typed_enclosings` response from Merlin for inspections.
         * @param inspection_data The JSON data for the type information.
         */
        void handle_inspection_response(const nl::json& inspection_data);

        /**
         * @brief Processes stdout/stderr/results from code execution.
         * @param request_id The ID of the original execution request.
         * @param outputs A JSON array of outputs.
         */
        void handle_execution_output(int request_id, const nl::json& outputs);

        /**
         * @brief Sends the final reply for an execution request.
         * @param request_id The ID of the original execution request.
         * @param error_summary A summary of errors, if any.
         */
        void handle_final_response(int request_id, const std::string& error_summary);

        /** @} */

        /**
         * @name Communication helpers
         * @{
         */

        /**
         * @brief Sends a JSON message to the OCaml Web Worker.
         * @param message The JSON object to send.
         */
        void send_to_worker(const nl::json& message);

        /**
         * @brief Sends a command to the JupyterLab frontend via a temporary comm channel.
         * @param command The JupyterLab command ID to execute (e.g., "completer:invoke-notebook").
         */
        void send_jupyterlab_command(const std::string& command);

        /**
         * @brief Maps a Merlin completion kind to a JupyterLab completion icon name.
         * @param kind_json The JSON representation of the Merlin completion kind.
         * @return A string representing the icon type (e.g., "function", "module").
         */
        std::string map_ocaml_kind_to_icon(const nl::json& kind_json);

        /** @} */

        /**
         * @name Internal State
         * @{
         */

        /**
         * @struct pending_request
         * @brief Stores information about an ongoing `execute_request`.
         */
        struct pending_request
        {
            send_reply_callback m_callback; ///< The callback to send the final reply.
            int m_execution_count;          ///< The execution counter for this request.
        };

        /**
         * @struct completion_cache
         * @brief Caches the last completion request and its reply to avoid redundant calls.
         */
        struct completion_cache
        {
            std::mutex m_mutex;         ///< Mutex to protect concurrent access.
            std::string m_code;         ///< The code for which completion was requested.
            int m_cursor_pos = -1;      ///< The cursor position.
            nl::json m_reply;           ///< The cached reply.
            bool m_asked = false;       ///< Flag to coordinate with inspection requests.
        };

        /**
         * @struct inspection_cache
         * @brief Caches the last inspection request and its reply.
         */
        struct inspection_cache
        {
            std::mutex m_mutex;         ///< Mutex to protect concurrent access.
            std::string m_code;         ///< The code for which inspection was requested.
            int m_cursor_pos = -1;      ///< The cursor position.
            nl::json m_reply;           ///< The cached reply.
        };

        /// Map of request IDs to pending execution requests.
        std::map<int, pending_request> m_pending_requests;
        /// A counter to generate unique IDs for requests sent to the worker.
        int m_request_id_counter;
        /// Cache for completion results.
        completion_cache m_completion_cache;
        /// Cache for inspection results.
        inspection_cache m_inspection_cache;
        /// Manages the lifecycle of temporary comms used for sending commands to the frontend.
        std::map<xeus::xguid, xeus::xcomm> m_ephemeral_comms;

        /** @} */

        /**
         * @brief Friend declaration to allow the global C-style callback to access
         *        the `on_message_callback` member function.
         */
        friend void ::global_on_message_callback(emscripten::val event);
    };
} // namespace xeus_ocaml

#endif // XEUS_OCAML_INTERPRETER_HPP