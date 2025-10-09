/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#include <iostream>
#include <memory>


#include <emscripten/bind.h>

#include "xinterpreter.hpp"
#include "xeus/xembind.hpp"


EMSCRIPTEN_BINDINGS(my_module) {
    xeus::export_core();
    using interpreter_type = xeus_ocaml::interpreter;
    xeus::export_kernel<interpreter_type>("xkernel");
}

