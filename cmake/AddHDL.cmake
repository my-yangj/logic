# Copyright 2017 Tymoteusz Blazejczyk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

find_package(ModelSim)
find_package(SystemC REQUIRED COMPONENTS SCV UVM)
find_package(Verilator REQUIRED)

set(HDL_TARGETS "" CACHE INTERNAL "RTL targets" FORCE)

file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/.hdl)
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/output)

if (MODELSIM_FOUND)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim/.modules)

    if (NOT EXISTS ${CMAKE_BINARY_DIR}/modelsim/work/_info)
        execute_process(COMMAND ${MODELSIM_VLIB} work
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim)
    endif()

    if (NOT EXISTS ${CMAKE_BINARY_DIR}/modelsim/modelsim.ini)
        execute_process(COMMAND ${MODELSIM_VMAP} work work
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim)
    endif()

    add_custom_target(modelsim-compile-all ALL)
endif()

function(add_hdl_source)
    set(state GET_SOURCE)
    set(hdl_name FALSE)
    set(hdl_type FALSE)
    set(hdl_source FALSE)
    set(hdl_library work)
    set(hdl_depends "")
    set(hdl_defines "")
    set(hdl_includes "")
    set(hdl_verilator_configurations "")

    if (HDL_LIBRARY)
        set(hdl_library ${HDL_LIBRARY})
    endif()

    if (HDL_DEPENDS)
        foreach (hdl_depend ${HDL_DEPENDS})
            list(APPEND hdl_depends ${hdl_depend})
        endforeach()
    endif()

    if (HDL_DEFINES)
        foreach (hdl_define ${HDL_DEFINES})
            list(APPEND hdl_defines ${hdl_define})
        endforeach()
    endif()

    if (HDL_INCLUDES)
        foreach (hdl_include ${HDL_INCLUDES})
            get_filename_component(hdl_include ${hdl_include} REALPATH)
            list(APPEND hdl_includes ${hdl_include})
        endforeach()
    endif()

    foreach (arg ${ARGN})
        # Argument
        if (arg MATCHES NAME)
            set(state GET_NAME)
        elseif (arg MATCHES TYPE)
            set(state GET_TYPE)
        elseif (arg MATCHES SOURCE)
            set(state GET_SOURCE)
        elseif (arg MATCHES LIBRARY)
            set(state GET_LIBRARY)
        elseif (arg MATCHES DEPENDS)
            set(state GET_DEPENDS)
        elseif (arg MATCHES DEFINES)
            set(state GET_DEFINES)
        elseif (arg MATCHES INCLUDES)
            set(state GET_INCLUDES)
        elseif (arg MATCHES VERILATOR_CONFIGURATIONS)
            set(state GET_VERILATOR_CONFIGURATIONS)

        # State
        elseif (state MATCHES GET_NAME)
            set(hdl_name ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_TYPE)
            set(hdl_type ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_SOURCE)
            set(hdl_source ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_LIBRARY)
            set(hdl_library ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_DEPENDS)
            list(APPEND hdl_depends ${arg})
        elseif (state MATCHES GET_DEFINES)
            list(APPEND hdl_defines ${arg})
        elseif (state MATCHES GET_INCLUDES)
            get_filename_component(arg ${arg} REALPATH)
            list(APPEND hdl_includes ${arg})
        elseif (state MATCHES GET_VERILATOR_CONFIGURATIONS)
            list(APPEND hdl_verilator_configurations ${arg})
        else ()
            message(FATAL_ERROR "Invalid argument: ${arg}")
        endif()
    endforeach()

    if (NOT hdl_source)
        message(FATAL_ERROR "HDL source is not defined")
    endif()

    get_filename_component(hdl_source ${hdl_source} REALPATH)

    if (NOT EXISTS ${hdl_source})
        message(FATAL_ERROR "HDL source doesn't exist: ${hdl_source}")
    endif()

    if (NOT ${hdl_name})
        get_filename_component(hdl_name ${hdl_source} NAME_WE)
    endif()

    if (NOT hdl_type)
        if (hdl_source MATCHES .sv)
            set(hdl_type SystemVerilog)
        elseif (hdl_source MATCHES .vhd)
            set(hdl_type VHDL)
        elseif (hdl_source MATCHES .v)
            set(hdl_type Verilog)
        endif()
    endif()

    set(HDL_TARGETS ${HDL_TARGETS} ${hdl_name}
        CACHE INTERNAL "RTL targets" FORCE)

    configure_file(${CMAKE_SOURCE_DIR}/cmake/AddHDL.cmake.in
        ${CMAKE_BINARY_DIR}/.hdl/${hdl_name})

    if (MODELSIM_FOUND)
        set(modelsim_compiler)
        set(modelsim_flags -work ${hdl_library})
        set(modelsim_source ${hdl_source})
        set(modelsim_depends)
        set(modelsim_libraries "")

        if (hdl_type MATCHES SystemVerilog OR hdl_type MATCHES Verilog)
            set(modelsim_compiler ${MODELSIM_VLOG})

            if (hdl_type MATCHES SystemVerilog)
                set(modelsim_flags ${modelsim_flags} -sv)
            endif()

            foreach (def ${hdl_defines})
                set(modelsim_flags ${modelsim_flags} +define+${def})
            endforeach()

            foreach (inc ${hdl_includes})
                set(modelsim_flags ${modelsim_flags} +incdir+${inc})
            endforeach()
        elseif (hdl_type MATCHES VHDL)
            set(modelsim_compiler ${MODELSIM_VCOM})
            set(modelsim_flags ${modelsim_flags} -2008)
        endif()

        foreach (hdl_depend ${hdl_depends})
            set(modelsim_depends ${modelsim_depends}
                modelsim-compile-${hdl_depend})
        endforeach()

        if (NOT EXISTS ${CMAKE_BINARY_DIR}/modelsim/${hdl_library})
            execute_process(COMMAND ${MODELSIM_VLIB} ${hdl_library}
                WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim)
        endif()

        if (CYGWIN)
            execute_process(COMMAND cygpath -m ${modelsim_source}
                OUTPUT_VARIABLE modelsim_source
                OUTPUT_STRIP_TRAILING_WHITESPACE)
        endif()

        get_hdl_depends(${hdl_name} hdl_depends_all)

        foreach (hdl_depend ${hdl_depends_all})
            get_hdl_properties(${hdl_depend} LIBRARY modelsim_library)
            list(APPEND modelsim_libraries ${modelsim_library})
        endforeach()

        list(REMOVE_DUPLICATES modelsim_libraries)

        foreach (modelsim_library ${modelsim_libraries})
            set(modelsim_flags ${modelsim_flags} -L ${modelsim_library})
        endforeach()

        add_custom_command(
            OUTPUT ${CMAKE_BINARY_DIR}/modelsim/.modules/${hdl_name}
            COMMAND ${CMAKE_COMMAND} -E touch ./.modules/${hdl_name}
            COMMAND ${modelsim_compiler} ${modelsim_flags} ${modelsim_source}
            DEPENDS ${hdl_source} ${modelsim_depends}
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim
            COMMENT "ModelSim compiling HDL: ${hdl_name}"
        )

        add_custom_target(modelsim-compile-${hdl_name}
            DEPENDS ${CMAKE_BINARY_DIR}/modelsim/.modules/${hdl_name})

        add_dependencies(modelsim-compile-all modelsim-compile-${hdl_name})
    endif()
endfunction()

function(get_hdl_properties hdl_name)
    set(state UNKNOWN)
    set(hdl_type FALSE)
    set(hdl_source FALSE)
    set(hdl_library work)
    set(hdl_depends "")
    set(hdl_defines "")
    set(hdl_includes "")
    set(hdl_verilator_configurations "")

    file(READ ${CMAKE_BINARY_DIR}/.hdl/${hdl_name} hdl_file)

    string(REGEX REPLACE "\n" ";" hdl_file "${hdl_file}")

    foreach (arg ${hdl_file})
        # Argument
        if (arg STREQUAL "")
            # Empty argument
        elseif (arg MATCHES NAME)
            set(state GET_NAME)
        elseif (arg MATCHES TYPE)
            set(state GET_TYPE)
        elseif (arg MATCHES SOURCE)
            set(state GET_SOURCE)
        elseif (arg MATCHES LIBRARY)
            set(state GET_LIBRARY)
        elseif (arg MATCHES DEPENDS)
            set(state GET_DEPENDS)
        elseif (arg MATCHES DEFINES)
            set(state GET_DEFINES)
        elseif (arg MATCHES INCLUDES)
            set(state GET_INCLUDES)
        elseif (arg MATCHES VERILATOR_CONFIGURATIONS)
            set(state GET_VERILATOR_CONFIGURATIONS)

        # State
        elseif (state MATCHES GET_NAME)
            set(hdl_name ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_TYPE)
            set(hdl_type ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_SOURCE)
            set(hdl_source ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_LIBRARY)
            set(hdl_library ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_DEPENDS)
            list(APPEND hdl_depends ${arg})
        elseif (state MATCHES GET_DEFINES)
            list(APPEND hdl_defines ${arg})
        elseif (state MATCHES GET_INCLUDES)
            list(APPEND hdl_includes ${arg})
        elseif (state MATCHES GET_VERILATOR_CONFIGURATIONS)
            list(APPEND hdl_verilator_configurations ${arg})
        else ()
            message(FATAL_ERROR "Invalid argument: ${arg}")
        endif()
    endforeach()

    set(state UNKNOWN)

    foreach (arg ${ARGN})
        # Argument
        if (arg MATCHES NAME)
            set(state GET_NAME)
        elseif (arg MATCHES TYPE)
            set(state GET_TYPE)
        elseif (arg MATCHES SOURCE)
            set(state GET_SOURCE)
        elseif (arg MATCHES LIBRARY)
            set(state GET_LIBRARY)
        elseif (arg MATCHES DEPENDS)
            set(state GET_DEPENDS)
        elseif (arg MATCHES DEFINES)
            set(state GET_DEFINES)
        elseif (arg MATCHES INCLUDES)
            set(state GET_INCLUDES)
        elseif (arg MATCHES VERILATOR_CONFIGURATIONS)
            set(state GET_VERILATOR_CONFIGURATIONS)

        # State
        elseif (state MATCHES GET_NAME)
            set(${arg} ${hdl_name} PARENT_SCOPE)
            set(state UNKNOWN)
        elseif (state MATCHES GET_TYPE)
            set(${arg} ${hdl_type} PARENT_SCOPE)
            set(state UNKNOWN)
        elseif (state MATCHES GET_SOURCE)
            set(${arg} ${hdl_source} PARENT_SCOPE)
            set(state UNKNOWN)
        elseif (state MATCHES GET_LIBRARY)
            set(${arg} ${hdl_library} PARENT_SCOPE)
            set(state UNKNOWN)
        elseif (state MATCHES GET_DEPENDS)
            set(${arg} ${hdl_depends} PARENT_SCOPE)
            set(state UNKNOWN)
        elseif (state MATCHES GET_DEFINES)
            set(${arg} ${hdl_defines} PARENT_SCOPE)
            set(state UNKNOWN)
        elseif (state MATCHES GET_INCLUDES)
            set(${arg} ${hdl_includes} PARENT_SCOPE)
            set(state UNKNOWN)
        else ()
            message(FATAL_ERROR "Invalid argument: ${arg}")
        endif()
    endforeach()
endfunction()

function(get_hdl_depends hdl_name hdl_depends_var)
    set(hdl_depends "")
    set(hdl_depends_list)

    get_hdl_properties(${hdl_name} DEPENDS hdl_depends_list)

    foreach (hdl_name ${hdl_depends_list})
        set(hdl_depends_next)

        get_hdl_depends(${hdl_name} hdl_depends_next)

        list(APPEND hdl_depends ${hdl_name})
        list(APPEND hdl_depends ${hdl_depends_next})
    endforeach()

    list(REMOVE_DUPLICATES hdl_depends)

    set(${hdl_depends_var} ${hdl_depends} PARENT_SCOPE)
endfunction()

function(add_hdl_systemc target_name)
    set(state GET_SOURCES)
    set(target_sources "")
    set(target_depends "")
    set(target_defines "")
    set(target_includes "")
    set(target_top_module ${target_name})
    set(target_output_directory
        ${CMAKE_BINARY_DIR}/systemc/${target_top_module})

    foreach (arg ${ARGN})
        # Handle argument
        if (arg MATCHES OUTPUT_DIRECTORY)
            set(state GET_OUTPUT_DIRECTORY)
        elseif (arg MATCHES DEFINES)
            set(state GET_DEFINES)
        elseif (arg MATCHES INCLUDES)
            set(state GET_INCLUDES)
        elseif (arg MATCHES DEPENDS)
            set(state GET_DEPENDS)
        elseif (arg MATCHES TOP_MODULE)
            set(state GET_TOP_MODULE)
        # Handle state
        elseif (state MATCHES GET_SOURCES)
            list(APPEND target_sources ${arg})
        elseif (state MATCHES GET_DEFINES)
            list(APPEND target_defines ${arg})
        elseif (state MATCHES GET_DEPENDS)
            list(APPEND target_depends ${arg})
        elseif (state MATCHES GET_INCLUDES)
            list(APPEND target_includes ${arg})
        elseif (state MATCHES GET_OUTPUT_DIRECTORY)
            set(target_output_directory ${arg})
            set(state UNKNOWN)
        elseif (state MATCHES GET_TOP_MODULE)
            set(target_top_module ${arg})
            set(state UNKNOWN)
        else()
            message(FATAL_ERROR "Unknown argument")
        endif()
    endforeach()

    get_hdl_depends(${target_top_module} hdl_depends)

    foreach (hdl_name ${hdl_depends} ${target_top_module})
        get_hdl_properties(${hdl_name}
            NAME hdl_name
            TYPE hdl_type
            SOURCE hdl_source
            DEFINES hdl_defines
            DEPENDS hdl_depends
            INCLUDES hdl_includes
        )

        list(APPEND target_sources ${hdl_source})
        list(APPEND target_defines ${hdl_defines})
        list(APPEND target_includes ${hdl_includes})
    endforeach()

    list(REMOVE_DUPLICATES target_defines)
    list(REMOVE_DUPLICATES target_includes)

    set(target_library ${target_top_module}__ALL.a)

    set(target_includes_expand "")
    foreach (inc ${target_includes})
        list(APPEND target_includes_expand -I${inc})
    endforeach()

    set(target_defines_expand "")
    foreach (def ${target_defines})
        list(APPEND target_defines_expand -D${def})
    endforeach()

    file(MAKE_DIRECTORY ${target_output_directory})

    add_custom_command(
        OUTPUT
            ${target_output_directory}/${target_library}
        COMMAND
            ${VERILATOR_EXECUTABLE}
        ARGS
            --sc
            -O2
            -CFLAGS '-std=c++11 -O2 -fdata-sections -ffunction-sections'
            --trace
            --coverage
            --prefix ${target_top_module}
            --top-module ${target_top_module}
            -Mdir ${target_output_directory}
            ${target_defines_expand}
            ${target_includes_expand}
            ${target_sources}
        COMMAND
            $(MAKE)
        ARGS
            -f ${target_output_directory}/${target_top_module}.mk
        DEPENDS
            ${target_depends}
            ${target_sources}
            ${target_includes}
        WORKING_DIRECTORY ${target_output_directory}
        COMMENT
            "Creating SystemC ${target_top_module} module"
    )

    add_custom_target(${target_name}
        DEPENDS ${target_output_directory}/${target_library})

    add_library(verilated_${target_name} STATIC IMPORTED)

    add_dependencies(verilated_${target_name} ${target_name})

    set_target_properties(verilated_${target_name} PROPERTIES
        IMPORTED_LOCATION ${target_output_directory}/${target_library}
    )

    set(module_libraries
        verilated_${target_name}
        verilated
        ${SYSTEMC_LIBRARIES}
    )

    set(module_include_directories
        ${VERILATOR_INCLUDE_DIR}
        ${SYSTEMC_INCLUDE_DIRS}
        ${target_output_directory}
    )

    set_target_properties(${target_name} PROPERTIES
        LIBRARIES "${module_libraries}"
        INCLUDE_DIRECTORIES "${module_include_directories}"
    )
endfunction()

function(add_hdl_test test_name)
    if (MODELSIM_FOUND)
        set(MODELSIM_RUN_TCL ${CMAKE_SOURCE_DIR}/scripts/modelsim_run.tcl)

        if (CYGWIN)
            execute_process(COMMAND cygpath -m ${MODELSIM_RUN_TCL}
                OUTPUT_VARIABLE MODELSIM_RUN_TCL
                OUTPUT_STRIP_TRAILING_WHITESPACE)
        endif()

        set(hdl_depends "")
        set(hdl_libraries "")
        set(modelsim_flags "")

        list(APPEND modelsim_flags -c)
        list(APPEND modelsim_flags -wlf ../output/${test_name}.wlf)
        list(APPEND modelsim_flags -do ${MODELSIM_RUN_TCL})

        get_hdl_depends(${test_name} hdl_depends)

        foreach (hdl_name ${hdl_depends} ${test_name})
            get_hdl_properties(${hdl_name} LIBRARY hdl_library)
            list(APPEND hdl_libraries ${hdl_library})
        endforeach()

        list(REMOVE_DUPLICATES hdl_libraries)

        foreach (hdl_library ${hdl_libraries})
            list(APPEND modelsim_flags -L ${hdl_library})
        endforeach()

        add_test(NAME ${test_name}
            COMMAND ${MODELSIM_VSIM} ${modelsim_flags} ${test_name}
            WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/modelsim
        )
    endif()
endfunction()