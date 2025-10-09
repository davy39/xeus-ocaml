/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#ifndef XEUS_OCAML_COMPLETION_HPP
#define XEUS_OCAML_COMPLETION_HPP

#include <string>
#include "nlohmann/json.hpp"

namespace nl = nlohmann;

namespace xeus_ocaml
{
    /**
     * @brief Handles a code completion request from the Jupyter frontend.
     *
     * This function orchestrates the process of getting completion suggestions
     * from the Merlin backend via the `ocaml_engine` and formatting the response
     * into a valid Jupyter `complete_reply` message.
     *
     * @param code The entire code content of the cell.
     * @param cursor_pos The position of the cursor within the code.
     * @return A JSON object representing the `complete_reply` message,
     *         containing the list of matches and cursor positions.
     */
    nl::json handle_completion_request(const std::string& code, int cursor_pos);

} // namespace xeus_ocaml

#endif // XEUS_OCAML_COMPLETION_HPP