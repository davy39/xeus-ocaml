/***************************************************************************
 * Copyright (c) 2025, Davy Cottet
 * Copyright (c) 2024, The xeus-ocaml Authors
 *
 * Distributed under the terms of the BSD 3-Clause License.
 *
 * The full license is in the file LICENSE, distributed with this software.
 ****************************************************************************/

#include "xeus-ocaml/xinterpreter.hpp"

#include <iostream>
#include <sstream>
#include <stdexcept>
#include <utility>

#include "xeus/xhelper.hpp"
#include "xeus/xinput.hpp"

#include <emscripten/bind.h>
#include <emscripten.h>

namespace xeus_ocaml
{
    namespace
    {
        // A global pointer to the single interpreter instance is necessary because
        // Emscripten's C++ binding mechanism for JS callbacks works with free functions,
        // not member functions directly.
        interpreter* g_interpreter_instance = nullptr;
    }

    void global_on_message_callback(emscripten::val event)
    {
        if (g_interpreter_instance != nullptr)
        {
            std::string message_data = event["data"].as<std::string>();
            g_interpreter_instance->on_message_callback(message_data);
        }
    }

    // This binding exposes the `global_on_message_callback` function to the JavaScript
    // environment, allowing it to be assigned as the `onmessage` handler for the worker.
    EMSCRIPTEN_BINDINGS(ocaml_kernel_module)
    {
        emscripten::function("global_on_message_callback_js", &global_on_message_callback);
    }

    interpreter::interpreter() : m_request_id_counter(0)
    {
        // Register this instance with the xeus framework and set the global pointer.
        xeus::register_interpreter(this);
        g_interpreter_instance = this;
    }

    void interpreter::configure_impl()
    {
        // Retrieve the JavaScript worker object and our C++ callback function via Emscripten.
        emscripten::val ocamlWorker = emscripten::val::module_property("ocamlWorker");
        emscripten::val callback_fn = emscripten::val::module_property("global_on_message_callback_js");

        // Hook up the C++ callback to the worker's `onmessage` event.
        ocamlWorker.set("onmessage", callback_fn);

        // Send an initial "Setup" message to the OCaml worker to begin its initialization.
        nl::json setup_msg = {"Setup"};
        send_to_worker(setup_msg);

        // Register a comm target for receiving commands from the frontend (e.g., JupyterLab).
        // This allows for programmatic control of the frontend from the kernel.
        comm_manager().register_comm_target(
            "jupyterlab-commands-executor",
            [](xeus::xcomm&&, const xeus::xmessage&) {}
        );
    }

    void interpreter::send_to_worker(const nl::json& message)
    {
        std::clog << "[C++ -> OCaml] Sending message: " << message.dump() << std::endl;
        // This is a thin C++ wrapper around the JavaScript `worker.postMessage()` method.
        emscripten::val ocamlWorker = emscripten::val::module_property("ocamlWorker");
        ocamlWorker.call<void>("postMessage", emscripten::val(message.dump()));
    }

    void interpreter::on_message_callback(const std::string& message)
    {
        std::clog << "[OCaml -> C++] Received message: " << message << std::endl;
        // First, safely parse the incoming JSON string.
        nl::json response_json;
        try {
            response_json = nl::json::parse(message);
        } catch (const nl::json::parse_error& e) {
            std::cerr << "[C++] Failed to parse JSON from OCaml worker: " << e.what() << std::endl;
            return;
        }
        // Validate the basic structure of the response array.
        if (!response_json.is_array() || response_json.size() < 2) {
            std::cerr << "[C++] Invalid response format from OCaml worker." << std::endl;
            return;
        }

        // Dispatch the message based on its type tag.
        std::string response_type = response_json[0].get<std::string>();
        int request_id = response_json[1].get<int>();

        if (response_type == "Merlin_response") {
            handle_merlin_response(response_json[2]);
        } else if (response_type == "Top_response_at") {
            handle_execution_output(request_id, response_json[3]);
        } else if (response_type == "Top_response") {
            handle_final_response(request_id, "");
        } else if (response_type == "Formatted_source") {
        // We could format cell content ...
        } 
        else {
            std::string error_msg = "Received unhandled response type from OCaml worker: " + response_type;
            handle_final_response(request_id, error_msg);
        }
    }

    void interpreter::handle_merlin_response(const nl::json& merlin_answer)
    {
        if (!merlin_answer.is_array() || merlin_answer.empty()) return;

        // Sub-dispatch for different kinds of Merlin responses.
        const std::string& merlin_response_type = merlin_answer[0].get<std::string>();
        const nl::json& data = merlin_answer[1];

        if (merlin_response_type == "Completions") {
            handle_completion_response(data);
        } else if (merlin_response_type == "Typed_enclosings") {
            handle_inspection_response(data);
        }
    }

    std::string interpreter::map_ocaml_kind_to_icon(const nl::json& kind_json)
    {
        if (!kind_json.is_array() || kind_json.empty()) {
            return "text";
        }
        const std::string& kind = kind_json[0].get<std::string>();

        // Map Merlin's type kinds to the icon names supported by JupyterLab's completer.
        if (kind == "Value") return "function";
        if (kind == "Module" || kind == "Modtype") return "module";
        if (kind == "Constructor" || kind == "Variant") return "class";
        if (kind == "Type") return "interface";
        if (kind == "Method" || kind == "Methodcall") return "method";
        if (kind == "Keyword") return "keyword";
        if (kind == "Label") return "field";
        if (kind == "Exn") return "event";

        return "text"; // A safe default.
    }

    void interpreter::handle_completion_response(const nl::json& completion_data)
    {
        nl::json matches = nl::json::array();
        nl::json rich_items = nl::json::array();

        if (completion_data.contains("entries"))
        {
            // Iterate through each completion suggestion from Merlin.
            for (const auto& entry : completion_data["entries"])
            {
                std::string name = entry.value("name", "");
                matches.push_back(name);

                // Build a rich completion item for JupyterLab's experimental completer API.
                nl::json rich_item;
                rich_item["text"] = name;
                rich_item["type"] = map_ocaml_kind_to_icon(entry.value("kind", nl::json::array()));
                rich_item["signature"] = entry.value("desc", ""); // The type signature.
                rich_item["documentation"] = entry.value("info", ""); // The docstring.

                rich_items.push_back(rich_item);
            }
        }

        int start = completion_data.value("from", -1);
        int end = completion_data.value("to_", -1);

        // Create the standard completion reply.
        nl::json reply = xeus::create_complete_reply(matches, start, end);
        // Attach the rich completion data to the experimental metadata field.
        reply["metadata"]["_jupyter_types_experimental"] = rich_items;

        // Cache the fully-formed reply.
        std::lock_guard<std::mutex> lock(m_completion_cache.m_mutex);
        m_completion_cache.m_reply = reply;

        // Programmatically trigger the completer in the frontend to display the results.
        send_jupyterlab_command("completer:invoke-notebook");
    }

    void interpreter::handle_inspection_response(const nl::json& inspection_data)
    {
        nl::json reply;
        if (!inspection_data.empty())
        {
            // Extract the type string from the Merlin response.
            const auto& type_info = inspection_data[0][1];
            if (type_info.is_array() && type_info.size() == 2 && type_info[0] == "String")
            {
                std::string type_str = type_info[1].get<std::string>();
                
                // Create a data bundle with plain text and a formatted HTML version for the tooltip.
                nl::json data;
                data["text/plain"] = type_str;
                data["text/html"] = "<div style=\"font-family: var(--jp-code-font-family);\"><strong>Type:</strong><code> " + type_str + "</code></div>";
                reply = xeus::create_inspect_reply(true, data, {});
            }
        }

        // If parsing failed or no type was found, create a "not found" reply.
        if (reply.is_null())
        {
            reply = xeus::create_inspect_reply(false, {}, {});
        }

        // Cache the reply and trigger.
        std::lock_guard<std::mutex> lock(m_inspection_cache.m_mutex);
        m_inspection_cache.m_reply = reply;
    }

    nl::json interpreter::inspect_request_impl(const std::string& code, int cursor_pos, int)
    {
        std::lock_guard<std::mutex> lock(m_inspection_cache.m_mutex);

        // Serve from cache if the request is identical to the previous one.
        if (m_inspection_cache.m_code == code && m_inspection_cache.m_cursor_pos == cursor_pos && !m_inspection_cache.m_reply.is_null())
        {
            return m_inspection_cache.m_reply;
        }

        // On cache miss, clear old data and send a new request to the worker.
        m_inspection_cache.m_code = code;
        m_inspection_cache.m_cursor_pos = cursor_pos;
        m_inspection_cache.m_reply = nullptr;

        int request_id = ++m_request_id_counter;
        nl::json merlin_action = {"Type_enclosing", code, {"Offset", cursor_pos}};
        nl::json request_json = {"Merlin", request_id, merlin_action};
        send_to_worker(request_json);

        // Return an empty reply immediately. Will need double SHIT+TAB.
        return xeus::create_inspect_reply(false, {}, {});
    }
    
    void interpreter::execute_request_impl(
        send_reply_callback cb,
        int execution_counter,
        const std::string& code,
        xeus::execute_request_config,
        nl::json
    )
    {
        // Create a mutable copy of the input code to be processed.
        std::string processed_code = code;

        // Store the callback and execution count to be used when the async response arrives.
        int request_id = ++m_request_id_counter;
        m_pending_requests[request_id] = {std::move(cb), execution_counter};

        // Send the modified code to the OCaml worker for evaluation.
        nl::json request_json = {"Eval", request_id, execution_counter, processed_code};
        send_to_worker(request_json);
    }

    void interpreter::handle_execution_output(int request_id, const nl::json& outputs)
    {
        auto it = m_pending_requests.find(request_id);
        if (it == m_pending_requests.end()) return;
        
        int execution_count = it->second.m_execution_count;

        // Process each output item (stdout, stderr, etc.) from the worker's response.
        for (const auto& output_item : outputs)
        {
            if (!output_item.is_array() || output_item.size() < 2) continue;
            
            const std::string& output_type = output_item[0].get<std::string>();
            const nl::json& output_content = output_item[1];

            if (output_type == "Stdout") {
                publish_stream("stdout", output_content.get<std::string>());
            } else if (output_type == "Stderr") {
                std::string err_msg = output_content.get<std::string>();
                std::vector<std::string> traceback;
                std::stringstream ss(err_msg);
                std::string line;
                while (std::getline(ss, line, '\n')) {
                    traceback.push_back(line);
                }
                publish_execution_error("OCaml Error", err_msg.substr(0, err_msg.find('\n')), traceback);
            } else if (output_type == "Html") {
                display_data({{"text/html", output_content.get<std::string>()}}, {}, {});
            } else if (output_type == "Meta") {
                publish_execution_result(execution_count, {{"text/plain", output_content.get<std::string>()}}, {});
            }
        }
    }

    void interpreter::handle_final_response(int request_id, const std::string& error_summary)
    {
        auto it = m_pending_requests.find(request_id);
        if (it == m_pending_requests.end()) return;

        // Retrieve the original callback and send the final execution reply.
        auto& cb = it->second.m_callback;
        if (!error_summary.empty()) {
            cb(xeus::create_error_reply("OCaml Execution Error", "", {error_summary}));
        } else {
            cb(xeus::create_successful_reply());
        }
        // Clean up the pending request.
        m_pending_requests.erase(it);
    }

    void interpreter::send_jupyterlab_command(const std::string& command)
    {
        try
        {
            nl::json data;
            data["command"] = command;

            // Create a new, temporary comm channel to send the command.
            auto it = m_ephemeral_comms.emplace(
                std::piecewise_construct,
                std::forward_as_tuple(xeus::new_xguid()),
                std::forward_as_tuple(comm_manager().target("jupyterlab-commands-executor"))
            ).first;

            xeus::xcomm& comm = it->second;
            xeus::xguid id = comm.id();

            // The frontend will immediately close the comm; this handler cleans it up on our side.
            comm.on_close([this, id](const xeus::xmessage&) {
                this->m_ephemeral_comms.erase(id);
            });

            // Opening the comm sends the command data to the frontend.
            comm.open({}, data, {});
        }
        catch (const std::exception& e)
        {
            std::cerr << "[C++] ERROR during comm message send: " << e.what() << std::endl;
        }
    }

    nl::json interpreter::complete_request_impl(const std::string& code, int cursor_pos)
    {
        m_completion_cache.m_asked = true;
        std::lock_guard<std::mutex> lock(m_completion_cache.m_mutex);

        // Serve from cache if the request is identical to the previous one.
        if (m_completion_cache.m_code == code && m_completion_cache.m_cursor_pos == cursor_pos)
        {
            send_jupyterlab_command("tooltip:dismiss");
            return m_completion_cache.m_reply;
        }

        // On cache miss, send a new request to the worker.
        m_completion_cache.m_code = code;
        m_completion_cache.m_cursor_pos = cursor_pos;
        int completion_id = ++m_request_id_counter;

        nl::json merlin_action = {"Complete_prefix", code, {"Offset", cursor_pos}};
        nl::json request_json = {"Merlin", completion_id, merlin_action};
        send_to_worker(request_json);

        // Return an empty reply immediately. The completer will be populated asynchronously.
        return xeus::create_complete_reply(nl::json::array(), cursor_pos, cursor_pos);
    }

    nl::json interpreter::is_complete_request_impl(const std::string& code)
    {
        // Use a simple heuristic: OCaml toplevel code is considered complete if it ends with ';;'.
        auto first_char = code.find_first_not_of(" \t\n\r");
        if (first_char == std::string::npos)
        {
            return xeus::create_is_complete_reply("complete");
        }

        auto last_char = code.find_last_not_of(" \t\n\r");
        if (last_char == std::string::npos || last_char < 1)
        {
            return xeus::create_is_complete_reply("incomplete", "  ");
        }

        if (code[last_char] == ';' && code[last_char - 1] == ';')
        {
            return xeus::create_is_complete_reply("complete");
        }

        return xeus::create_is_complete_reply("incomplete", "  ");
    }

    void interpreter::shutdown_request_impl()
    {
        // No specific shutdown actions are needed for this simple wasm kernel.
    }

    nl::json interpreter::kernel_info_request_impl()
    {
        // Provide standard information about the kernel.
        return xeus::create_info_reply(
            "5.3", "xocaml", "0.1.0", "ocaml", "5.1.0", "text/x-ocaml", ".ml",
            "ocaml", "ocaml", "", "xeus-ocaml - A WebAssembly OCaml kernel for Jupyter",
            false, nl::json::array()
        );
    }
}