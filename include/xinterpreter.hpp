/***************************************************************************
* Copyright (c) 2025, Davy Cottet
*
* Distributed under the terms of the GNU General Public License v3.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#ifndef XEUS_OCAML_INTERPRETER_HPP
#define XEUS_OCAML_INTERPRETER_HPP

#include <map>
#include <string>

#include "nlohmann/json.hpp"
#include "xeus/xinterpreter.hpp"
#include "xeus_ocaml_config.hpp"

namespace nl = nlohmann;

namespace xeus_ocaml
{
    namespace nl = nlohmann;

    /**
     * @class interpreter
     * @brief The main xeus interpreter for the OCaml kernel.
     *
     * This class is responsible for handling Jupyter protocol messages, managing
     * the execution lifecycle, and coordinating with the underlying OCaml engine.
     * It delegates specific tasks like code completion and inspection to dedicated modules.
     */
    class XEUS_OCAML_API interpreter : public xeus::xinterpreter
    {
    public:
        interpreter();
        virtual ~interpreter() = default;

        // Ensure the interpreter is non-copyable and non-movable, as there should
        // only be one instance per kernel session.
        interpreter(const interpreter&) = delete;
        interpreter& operator=(const interpreter&) = delete;
        interpreter(interpreter&&) = delete;
        interpreter& operator=(interpreter&&) = delete;

        /**
         * @brief Public callback handler for asynchronous execution results from JavaScript.
         *
         * This method is invoked by the global C-style callback function when a response
         * from an asynchronous 'Eval' action is received from the OCaml/JS backend.
         *
         * @param request_id The unique ID of the original execution request.
         * @param result_str The JSON string result from the JavaScript backend.
         */
        void handle_eval_callback(int request_id, const std::string& result_str);

    private:
        // Implementation of the xinterpreter interface
        void configure_impl() override;
        void execute_request_impl(send_reply_callback cb, int execution_counter, const std::string& code, xeus::execute_request_config config, nl::json user_expressions) override;
        nl::json complete_request_impl(const std::string& code, int cursor_pos) override;
        nl::json inspect_request_impl(const std::string& code, int cursor_pos, int detail_level) override;
        nl::json is_complete_request_impl(const std::string& code) override;
        nl::json kernel_info_request_impl() override;
        void shutdown_request_impl() override;

        /**
         * @brief Processes and publishes outputs from a successful execution.
         * @param request_id The ID of the original request.
         * @param outputs A JSON array of outputs from the OCaml toplevel.
         */
        void handle_execution_output(int request_id, const nl::json& outputs);

        /**
         * @brief Sends the final reply (success or error) for an execution request.
         * @param request_id The ID of the original request.
         * @param error_summary A summary of the error, if one occurred. An empty string signifies success.
         */
        void handle_final_response(int request_id, const std::string& error_summary);

        // Structure to hold state for pending asynchronous requests.
        struct pending_request
        {
            send_reply_callback m_callback;
            int m_execution_count;
        };

        std::map<int, pending_request> m_pending_requests;
        int m_request_id_counter;
    };
}

#endif // XEUS_OCAML_INTERPRETER_HPP