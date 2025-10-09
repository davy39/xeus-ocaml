/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#include "xcompletion.hpp"
#include "xocaml_engine.hpp"

#include "xeus/xhelper.hpp"

#include <iostream>
#include <string>
#include <vector>

// Enables detailed logging for debugging purposes.
#define DEBUG_XOCAML

#ifdef DEBUG_XOCAML
#define XOCAML_LOG(channel, message) std::cout << "[xeus-ocaml][" << channel << "] " << message << std::endl
#else
#define XOCAML_LOG(channel, message)
#endif

namespace xeus_ocaml
{
    /**
     * @brief Maps OCaml entity kinds from Merlin to Jupyter's completion item types.
     *
     * This enhances the user experience in frontends that support rich completion
     * suggestions by displaying appropriate icons for functions, modules, etc.
     *
     * @param kind_json The JSON string representing the entity kind from Merlin's response.
     * @return A string representing the corresponding Jupyter completion item type (e.g., "function", "module").
     *         Defaults to "text" for unknown kinds.
     */
    static std::string map_ocaml_kind_to_icon(const nl::json& kind_json)
    {
        if (!kind_json.is_string()) return "text";
        const std::string& kind = kind_json.get<std::string>();
        if (kind == "Value") return "function";
        if (kind == "Module" || kind == "Modtype") return "module";
        if (kind == "Constructor" || kind == "Variant") return "class";
        if (kind == "Type") return "interface";
        if (kind == "Method" || kind == "MethodCall") return "method";
        if (kind == "Keyword") return "keyword";
        if (kind == "Label") return "field";
        if (kind == "Exn") return "event";
        return "text";
    }

    /**
     * @brief Handles a code completion request.
     * @param code The code in the cell.
     * @param cursor_pos The cursor's position.
     * @return A JSON object for the `complete_reply` message.
     */
    nl::json handle_completion_request(const std::string& code, int cursor_pos)
    {
        // 1. Prepare the request for the Merlin backend.
        nl::json request = {
            "Complete_prefix",
            {
                {"source", code},
                {"position", {"Offset", cursor_pos}}
            }
        };

        // 2. Call the Merlin backend synchronously via the OCaml engine.
        nl::json response = ocaml_engine::call_merlin_sync(request);

        // 3. If the backend returns an error or an unexpected response, send an empty reply.
        if (response.value("class", "") != "return")
        {
            XOCAML_LOG("complete_request", "Merlin returned an error or unexpected response.");
            return xeus::create_complete_reply({}, cursor_pos, cursor_pos);
        }

        // 4. Parse the successful response from Merlin.
        const nl::json& value = response["value"];
        int start = value.value("from", cursor_pos);
        int end = value.value("to_", cursor_pos);
        
        nl::json matches = nl::json::array();
        nl::json rich_items = nl::json::array(); // For rich completion metadata.

        // 5. Build the list of completion matches.
        for (const auto& entry : value.value("entries", nl::json::array()))
        {
            std::string name = entry.value("name", "");
            matches.push_back(name);

            // Build rich completion item for frontends that support it (_jupyter_types_experimental).
            nl::json rich_item;
            rich_item["text"] = name;
            rich_item["type"] = map_ocaml_kind_to_icon(entry.value("kind", ""));
            rich_item["signature"] = entry.value("desc", "");
            rich_item["documentation"] = entry.value("info", "");
            rich_items.push_back(rich_item);
        }

        // 6. Create the final Jupyter reply message.
        nl::json reply = xeus::create_complete_reply(matches, start, end);
        reply["metadata"]["_jupyter_types_experimental"] = rich_items;
        
        XOCAML_LOG("complete_request", "Sending complete_reply: " + reply.dump(2));
        return reply;
    }

} // namespace xeus_ocaml