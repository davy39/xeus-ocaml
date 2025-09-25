/***************************************************************************
* Copyright (c) 2025, Davy Cottet
*
* Distributed under the terms of the GNU General Public License v3.
*
* The full license is in the file LICENSE, distributed with this software.
****************************************************************************/

#include <string>
#include <vector>
#include <iostream>

#include "nlohmann/json.hpp"

#include "xeus/xinput.hpp"
#include "xeus/xinterpreter.hpp"
#include "xeus/xhelper.hpp"

#include "xeus-ocaml/xinterpreter.hpp"

// Include Emscripten headers for C++/JavaScript interaction
#include <emscripten/val.h>
#include <emscripten/bind.h>

// --- Global Buffers and C++ Functions Exposed to JavaScript ---

// Global buffers to hold the output from OCaml during execution
std::string global_stdout_buffer;
std::string global_stderr_buffer;

// C++ function to capture stdout from OCaml
void append_to_stdout(const std::string& s) {
    global_stdout_buffer += s;
}

// C++ function to capture stderr from OCaml
void append_to_stderr(const std::string& s) {
    global_stderr_buffer += s;
}

// Use EMSCRIPTEN_BINDINGS to expose the C++ functions to the JavaScript environment.
// This allows the OCaml kernel's redirected streams to call these C++ functions.
EMSCRIPTEN_BINDINGS(kernel_io_handlers) {
    emscripten::function("append_to_stdout", &append_to_stdout);
    emscripten::function("append_to_stderr", &append_to_stderr);
}

// --- Xeus Interpreter Implementation ---

namespace nl = nlohmann;

namespace xeus_ocaml
{
    interpreter::interpreter()
    {
        xeus::register_interpreter(this);
    }

    void interpreter::execute_request_impl(send_reply_callback cb,
                                  int execution_counter,
                                  const std::string& code,
                                  xeus::execute_request_config /*config*/,
                                  nl::json /*user_expressions*/)
    {
        // Clear the global buffers before each new execution
        global_stdout_buffer.clear();
        global_stderr_buffer.clear();

        try
        {
            std::string result_str = emscripten::val::global("ocaml_kernel").call<std::string>("exec", code);
            if (!global_stderr_buffer.empty())
            {
                std::string ename = "OCaml Toplevel Error";
                std::string evalue = global_stderr_buffer;
                std::vector<std::string> traceback = {evalue};

                publish_execution_error(ename, evalue, traceback);
                cb(xeus::create_error_reply(ename, evalue, traceback));
            }
            else
            {
                // First, publish anything that was printed to standard output
                if (!global_stdout_buffer.empty()) {
                    publish_stream("stdout", global_stdout_buffer);
                }

                // Then, publish the final result of the execution
                nl::json pub_data;
                pub_data["text/plain"] = result_str;
                publish_execution_result(execution_counter, std::move(pub_data), nl::json::object());

                cb(xeus::create_successful_reply());
            }
        }
        catch (const emscripten::val& e)
        {
            // This is a fallback for if the 'exec' call itself fails at the JS level
            std::string ename = "JavaScript Exception";
            std::string evalue = e.as<std::string>();
            std::vector<std::string> traceback = {evalue};

            publish_execution_error(ename, evalue, traceback);
            cb(xeus::create_error_reply(ename, evalue, traceback));
        }
    }

    void interpreter::configure_impl()
    {
        emscripten::val::global("ocaml_kernel").call<void>("init");
        emscripten::val cpp_stdout_handler = emscripten::val::module_property("append_to_stdout");
        emscripten::val cpp_stderr_handler = emscripten::val::module_property("append_to_stderr");
        emscripten::val::global("ocaml_kernel")["io"].set("stdout", cpp_stdout_handler);
        emscripten::val::global("ocaml_kernel")["io"].set("stderr", cpp_stderr_handler);
    }

    nl::json interpreter::is_complete_request_impl(const std::string& /*code*/)
    {
        return xeus::create_is_complete_reply("complete", "");
    }

    nl::json interpreter::complete_request_impl(const std::string& /*code*/,
                                                     int cursor_pos)
    {
        return xeus::create_complete_reply(
            nl::json::array(),
            cursor_pos,
            cursor_pos
        );
    }

    nl::json interpreter::inspect_request_impl(const std::string& /*code*/,
                                                      int /*cursor_pos*/,
                                                      int /*detail_level*/)
    {
        return xeus::create_inspect_reply(false, {}, {});
    }

    void interpreter::shutdown_request_impl() {
        // Perform any cleanup if necessary.
    }

    nl::json interpreter::kernel_info_request_impl()
    {
        const std::string  protocol_version = "5.3";
        const std::string  implementation = "xocaml";
        const std::string  implementation_version = "0.1.0";
        const std::string  language_name = "ocaml";
        const std::string  language_version = "5.1.0";
        const std::string  language_mimetype = "text/x-ocaml";
        const std::string  language_file_extension = ".ml";
        const std::string  language_pygments_lexer = "ocaml";
        const std::string  language_codemirror_mode = "ocaml";
        const std::string  language_nbconvert_exporter = "";
        const std::string  banner = "xeus-ocaml - A WebAssembly OCaml kernel for Jupyter";
        const bool         debugger = false;
        const nl::json     help_links = nl::json::array();

        return xeus::create_info_reply(
            protocol_version,
            implementation,
            implementation_version,
            language_name,
            language_version,
            language_mimetype,
            language_file_extension,
            language_pygments_lexer,
            language_codemirror_mode,
            language_nbconvert_exporter,
            banner,
            debugger,
            help_links
        );
    }
}