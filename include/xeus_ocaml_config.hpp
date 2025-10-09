/***************************************************************************
* Copyright (c) 2025, Davy Cottet                                  
*                                                                          
* Distributed under the terms of the GNU General Public License v3.                 
*                                                                          
* The full license is in the file LICENSE, distributed with this software. 
****************************************************************************/

#ifndef XEUS_OCAML_CONFIG_HPP
#define XEUS_OCAML_CONFIG_HPP

// Project version
#define XEUS_OCAML_VERSION_MAJOR 0
#define XEUS_OCAML_VERSION_MINOR 2
#define XEUS_OCAML_VERSION_PATCH 2

// Composing the version string from major, minor and patch
#define XEUS_OCAML_CONCATENATE(A, B) XEUS_OCAML_CONCATENATE_IMPL(A, B)
#define XEUS_OCAML_CONCATENATE_IMPL(A, B) A##B
#define XEUS_OCAML_STRINGIFY(a) XEUS_OCAML_STRINGIFY_IMPL(a)
#define XEUS_OCAML_STRINGIFY_IMPL(a) #a

#define XEUS_OCAML_VERSION XEUS_OCAML_STRINGIFY(XEUS_OCAML_CONCATENATE(XEUS_OCAML_VERSION_MAJOR,   \
                 XEUS_OCAML_CONCATENATE(.,XEUS_OCAML_CONCATENATE(XEUS_OCAML_VERSION_MINOR,   \
                                  XEUS_OCAML_CONCATENATE(.,XEUS_OCAML_VERSION_PATCH)))))

#ifdef _WIN32
    #ifdef XEUS_OCAML_EXPORTS
        #define XEUS_OCAML_API __declspec(dllexport)
    #else
        #define XEUS_OCAML_API __declspec(dllimport)
    #endif
#else
    #define XEUS_OCAML_API
#endif

#endif