/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#ifndef XEUS_OCAML_INSPECTION_HPP
#define XEUS_OCAML_INSPECTION_HPP

#include <string>
#include "nlohmann/json.hpp"

namespace nl = nlohmann;

namespace xeus_ocaml
{
    /**
     * @brief Handles a code inspection request from the Jupyter frontend.
     *
     * This function queries the Merlin backend for both the type signature and
     * the documentation of the identifier under the cursor. It then formats this
     * information into a rich `inspect_reply` message containing both plain text
     * and Markdown representations.
     *
     * @param code The entire code content of the cell.
     * @param cursor_pos The position of the cursor within the code.
     * @param detail_level The level of detail requested by the frontend (currently unused).
     * @return A JSON object representing the `inspect_reply` message.
     */
    nl::json handle_inspection_request(const std::string& code, int cursor_pos, int detail_level);

} // namespace xeus_ocaml

#endif // XEUS_OCAML_INSPECTION_HPP