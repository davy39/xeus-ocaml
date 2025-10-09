/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#include "xinspection.hpp"
#include "xocaml_engine.hpp"

#include "xeus/xhelper.hpp"

#include <iostream>
#include <sstream>
#include <string>
#include <regex>

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
     * @brief Parses and reformats a raw Merlin docstring for Markdown display.
     * 
     * This helper function performs several transformations:
     * - Converts Merlin's bold syntax `{!...}` to Markdown code blocks `` `...` ``.
     * - Unwraps indented paragraphs by replacing newlines followed by spaces with a single space.
     * - Creates proper Markdown paragraph breaks by replacing single newlines with double newlines.
     *
     * @param doc The raw docstring received from the Merlin backend.
     * @return A cleaned and formatted string suitable for Markdown rendering.
     */
    static std::string parse_merlin_docstring(std::string doc)
    {
        // Convert Merlin's bold syntax e.g., {!val: int} to `val: int`
        const std::regex merlin_bold_regex("\\{\\!(.*?)\\}");
        doc = std::regex_replace(doc, merlin_bold_regex, "`$1`");
        
        // Unwrap paragraphs that are indented in the source code.
        const std::regex indent_regex("\n +");
        doc = std::regex_replace(doc, indent_regex, " ");

        // Create proper paragraph breaks in Markdown.
        const std::regex newline_regex("\n");
        doc = std::regex_replace(doc, newline_regex, "\n\n");
        
        return doc;
    }

    /**
     * @brief Handles a code inspection request.
     * @param code The code in the cell.
     * @param cursor_pos The cursor's position.
     * @param detail_level The requested detail level.
     * @return A JSON object for the `inspect_reply` message.
     */
    nl::json handle_inspection_request(const std::string& code, int cursor_pos, int detail_level)
    {
        XOCAML_LOG("inspect_request", "Handling inspection request of level: " + std::to_string(detail_level));
        std::string type_string, doc_string;

        // 1. Request type information from Merlin.
        nl::json type_request = {"Type_enclosing", {{"source", code}, {"position", {"Offset", cursor_pos}}}};
        nl::json type_response = ocaml_engine::call_merlin_sync(type_request);
        if (type_response.value("class", "") == "return")
        {
            const auto& value = type_response["value"];
            if (value.is_array() && !value.empty())
            {
                const auto& type_info = value[0];
                if (type_info.contains("type") && type_info["type"].is_string())
                {
                    type_string = type_info["type"].get<std::string>();
                }
            }
        }

        // 2. Request documentation from Merlin.
        nl::json doc_request = {"Document", {{"source", code}, {"position", {"Offset", cursor_pos}}}};
        nl::json doc_response = ocaml_engine::call_merlin_sync(doc_request);
        if (doc_response.value("class", "") == "return")
        {
            std::string temp_doc = doc_response["value"].get<std::string>();
            // Filter out unhelpful default responses from Merlin.
            if (!temp_doc.empty() && temp_doc != "No documentation available" && temp_doc != "Not a valid identifier" && temp_doc.rfind("Not in environment", 0) != 0)
            {
                doc_string = parse_merlin_docstring(temp_doc);
                XOCAML_LOG("inspect_request", "Parsed documentation.");
            }
        }

        // 3. If no information was found, return a "not found" reply.
        if (type_string.empty() && doc_string.empty())
        {
            nl::json reply = xeus::create_inspect_reply(false, {}, {});
            XOCAML_LOG("inspect_request", "Sending inspect_reply (not found): " + reply.dump(2));
            return reply;
        }

        // 4. Format the response for both plain text and Markdown.
        std::stringstream md_content, plain_content;
        if (!type_string.empty())
        {
            md_content << "```ocaml\n" << type_string << "\n```\n";
            plain_content << type_string << "\n";
        }
        if (!type_string.empty() && !doc_string.empty())
        {
            md_content << "\n---\n\n";
            plain_content << "\n-----------------\n\n";
        }
        if (!doc_string.empty())
        {
            md_content << doc_string;
            plain_content << doc_string;
        }

        // 5. Build and return the final `inspect_reply` message.
        nl::json data;
        data["text/plain"] = plain_content.str();
        data["text/markdown"] = md_content.str();
        nl::json reply = xeus::create_inspect_reply(true, data, {});
        
        XOCAML_LOG("inspect_request", "Sending inspect_reply (found): " + reply.dump(2));
        return reply;
    }

} // namespace xeus_ocaml