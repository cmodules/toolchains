# Mark variables as used so cmake doesn't complain about them
mark_as_advanced(CMAKE_TOOLCHAIN_FILE)

# if (${CMAKE_BINARY_DIR} STREQUAL ${CMAKE_SOURCE_DIR})
#     message (WARNING "Configuring into source tree - please choose a different binary directory!")
#     return ()
# endif ()

set(CONFIG_FATAL_ERROR)
set(CONFIG_HAS_FATAL_ERROR OFF)
function(add_fatal_error ERROR)
    if(NOT CONFIG_HAS_FATAL_ERROR)
        set(CONFIG_HAS_FATAL_ERROR ON PARENT_SCOPE)
        set(CONFIG_FATAL_ERROR "${ERROR}" PARENT_SCOPE)
    else()
        string(APPEND CONFIG_FATAL_ERROR "\n${ERROR}")
    endif()
endfunction()

set(CMAKE_REQUIRED_MINIMUM_VERSION "3.7.2")
if(CMAKE_VERSION VERSION_LESS CMAKE_REQUIRED_MINIMUM_VERSION)
    message(FATAL_ERROR "Toolchain requires at least CMake ${CMAKE_REQUIRED_MINIMUM_VERSION}.")
endif()
cmake_policy(PUSH)
cmake_policy(VERSION 3.7.2)

option(VERBOSE "Enables output while configuring." ON)
mark_as_advanced(VERBOSE)
if($ENV{VERBOSE})
    set(VERBOSE "$ENV{VERBOSE}")
    set(CMAKE_VERBOSE_MAKEFILE ON CACHE BOOL "Enable verbose output from Makefile builds.")
else()
    set(VERBOSE ON)
endif()

option(APPLOCAL_DEPS "Automatically copy dependencies to output dir for executables (not functioning)." ON)

if(NOT DEFINED TARGET_TRIPLET)
    message(STATUS "No TARGET_TRIPLET passed in during invocation. Using detected triplet...")
endif()


if(DEFINED ENV{WindowsSDKVersion})
    if(NOT DEFINED WINSDK_VERSION)
        if("$ENV{WindowsSDKVersion}" MATCHES [[^([0-9.]*)\\?$]])
            set(WINSDK_VERSION "$ENV{WindowsSDKVersion}" CACHE STRING "Windows SDK version.")
            message(STATUS "WINSDK_VERSION = ${WINSDK_VERSION}")
        else()
            message(FATAL_ERROR "Unexpected format for ENV{WindowsSDKVersion} ($ENV{WindowsSDKVersion})")
        endif()
    endif()
endif()

function(escaped out_var value)
    string(REPLACE "\\" "\\\\" value "${value}")
    string(REPLACE "\"" "\\\"" value "${value}")
    string(REPLACE "\$" "\\\$" value "${value}")
    set(${out_var} "${value}" PARENT_SCOPE)
endfunction()

macro(function_arguments OUT_VAR)
    if("${ARGC}" EQUAL "1")
        set(function_arguments_FIRST_ARG "0")
    elseif("${ARGC}" EQUAL "2")
        set(function_arguments_FIRST_ARG "${ARGV1}")
    else()
        # bug
        message(FATAL_ERROR "function_arguments: invalid arguments (${ARGV})")
    endif()

    set("${OUT_VAR}" "")

    # this allows us to get the value of the enclosing function's ARGC
    set(function_arguments_ARGC_NAME "ARGC")
    set(function_arguments_ARGC "${${function_arguments_ARGC_NAME}}")

    math(EXPR function_arguments_LAST_ARG "${function_arguments_ARGC} - 1")
    if(function_arguments_LAST_ARG GREATER_EQUAL function_arguments_FIRST_ARG)
        foreach(function_arguments_N RANGE "${function_arguments_FIRST_ARG}" "${function_arguments_LAST_ARG}")
            string(REPLACE ";" "\\;" function_arguments_ESCAPED_ARG "${ARGV${function_arguments_N}}")
            # adds an extra `;` on the first time through
            set("${OUT_VAR}" "${${OUT_VAR}};${function_arguments_ESCAPED_ARG}")
        endforeach()
        # remove leading `;`
        string(SUBSTRING "${${OUT_VAR}}" "1" "-1" "${OUT_VAR}")
    endif()
endmacro()

#[===[.md:
# set_powershell_path

Gets either the path to powershell or powershell core,
and places it in the variable POWERSHELL_PATH.
#]===]
function(set_powershell_path)
    # Attempt to use pwsh if it is present; otherwise use powershell
    if(NOT DEFINED POWERSHELL_PATH)
        find_program(PWSH_PATH pwsh)
        if(PWSH_PATH)
            set(POWERSHELL_PATH "${PWSH_PATH}" CACHE INTERNAL "The path to the PowerShell implementation to use.")
            message(STATUS "POWERSHELL_PATH = ${PWSH_PATH}")
        else()
            message(DEBUG "Could not find PowerShell Core; falling back to PowerShell")
            find_program(BUILTIN_POWERSHELL_PATH powershell REQUIRED)
            if(BUILTIN_POWERSHELL_PATH)
                set(POWERSHELL_PATH "${BUILTIN_POWERSHELL_PATH}" CACHE INTERNAL "The path to the PowerShell implementation to use.")
                message(STATUS "POWERSHELL_PATH = ${BUILTIN_POWERSHELL_PATH}")
            else()
                message(WARNING "Could not find PowerShell; using static string 'powershell.exe'")
                set(POWERSHELL_PATH "powershell.exe" CACHE INTERNAL "The path to the PowerShell implementation to use.")
                message(STATUS "POWERSHELL_PATH = 'powershell.exe'")
            endif()
        endif()
    endif() # POWERSHELL_PATH
endfunction()

# Outputs to Cache: TARGET_COMPILER
function(detect_compiler)
    if(NOT DEFINED CACHE{TARGET_COMPILER})
        message(STATUS "Detecting the C++ compiler in use")

        if(CMAKE_GENERATOR STREQUAL "Ninja" AND CMAKE_SYSTEM_NAME STREQUAL "Windows")
            set(CMAKE_C_COMPILER_WORKS 1)
            set(CMAKE_C_COMPILER_FORCED 1)
            set(CMAKE_CXX_COMPILER_WORKS 1)
            set(CMAKE_CXX_COMPILER_FORCED 1)
        endif()

        if(NOT DEFINED LANGUAGES)
            set(LANGUAGES C CXX CACHE STRING "Enabled languages.")
        endif()

        enable_language("${LANGUAGES}")

        # foreach(LANGUAGE IN LANGUAGES)
        #     file(SHA1 "${CMAKE_${LANGUAGE}_COMPILER}" ${LANGUAGE}_HASH)
        # endforeach()

        # enable_language(C)
        # enable_language(CXX)

        file(SHA1 "${CMAKE_CXX_COMPILER}" CXX_HASH)
        file(SHA1 "${CMAKE_C_COMPILER}" C_HASH)
        string(SHA1 COMPILER_HASH "${C_HASH}${CXX_HASH}")

        if(VERBOSE)
            message(STATUS "COMPILER_HASH = ${COMPILER_HASH}")
            message(STATUS "COMPILER_C_HASH = ${C_HASH}")
            message(STATUS "COMPILER_C_VERSION = ${CMAKE_C_COMPILER_VERSION}")
            message(STATUS "COMPILER_C_ID = ${CMAKE_C_COMPILER_ID}")
            message(STATUS "COMPILER_CXX_HASH = ${CXX_HASH}")
            message(STATUS "COMPILER_CXX_VERSION = ${CMAKE_CXX_COMPILER_VERSION}")
            message(STATUS "COMPILER_CXX_ID = ${CMAKE_CXX_COMPILER_ID}")
        endif()

        if(CMAKE_COMPILER_IS_GNUXX OR CMAKE_CXX_COMPILER_ID MATCHES "GNU")
            if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 6.0)
                message(FATAL_ERROR [[
The g++ version picked up is too old; please install a newer compiler such as g++-7.
On Ubuntu try the following:
    sudo add-apt-repository ppa:ubuntu-toolchain-r/test -y
    sudo apt-get update -y
    sudo apt-get install g++-7 -y
On CentOS try the following:
    sudo yum install centos-release-scl
    sudo yum install devtoolset-7
    scl enable devtoolset-7 bash
]])
            endif()

            set(COMPILER "gcc")
        elseif(CMAKE_CXX_COMPILER_ID MATCHES "AppleClang")
            set(COMPILER "clang")
        elseif(CMAKE_CXX_COMPILER_ID MATCHES "[Cc]lang")
            set(COMPILER "clang")
        elseif(MSVC)
            set(COMPILER "msvc")
        else()
            message(FATAL_ERROR "Unknown compiler: ${CMAKE_CXX_COMPILER_ID}")
        endif()

        set(TARGET_COMPILER ${COMPILER} CACHE STRING "The compiler in use; one of gcc, clang, msvc")
        message(STATUS "Detecting the C++ compiler in use - ${TARGET_COMPILER}")
    endif()
endfunction()


macro(get_cmake_vars)

    if(NOT FLAGS_OUTPUT_FILE)
        set(FLAGS_OUTPUT_FILE "${CMAKE_CURRENT_BINARY_DIR}/flags.cmake")
    endif()

    set(OUTPUT_STRING "# Generator: ${CMAKE_CURRENT_LIST_FILE}\n")

    # Build default checklists
    list(APPEND DEFAULT_VARS_TO_CHECK
        CMAKE_CROSSCOMPILING
        CMAKE_SYSTEM_NAME
        CMAKE_HOST_SYSTEM_NAME
        CMAKE_SYSTEM_PROCESSOR
        CMAKE_HOST_SYSTEM_PROCESSOR
    )
    if(APPLE)
        list(APPEND DEFAULT_VARS_TO_CHECK
            CMAKE_OSX_DEPLOYMENT_TARGET
            CMAKE_OSX_SYSROOT
        )
    endif()

    # Programs to check
    set(PROGLIST AR RANLIB STRIP NM OBJDUMP DLLTOOL MT LINKER)
    foreach(prog IN LISTS PROGLIST)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${prog})
    endforeach()
    set(COMPILERS ${LANGUAGES} RC)
    foreach(prog IN LISTS COMPILERS)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${prog}_COMPILER CMAKE_${prog}_COMPILER_ID CMAKE_${prog}_COMPILER_FRONTEND_VARIANT)
    endforeach()

    # Variables to check
    foreach(_lang IN LISTS LANGUAGES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_STANDARD_INCLUDE_DIRECTORIES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_STANDARD_LIBRARIES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_STANDARD)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_COMPILE_FEATURES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_EXTENSION)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_IMPLICIT_LINK_FRAMEWORK_DIRECTORIES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_COMPILER_TARGET)

        # Probably never required since implicit.
        # list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_IMPLICIT_LINK_FRAMEWORK_DIRECTORIES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_IMPLICIT_INCLUDE_DIRECTORIES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_IMPLICIT_LINK_DIRECTORIES)
        list(APPEND DEFAULT_VARS_TO_CHECK CMAKE_${_lang}_IMPLICIT_LINK_LIBRARIES)
    endforeach()
    list(REMOVE_DUPLICATES DEFAULT_VARS_TO_CHECK)

    # Environment variables to check.
    list(APPEND DEFAULT_ENV_VARS_TO_CHECK PATH INCLUDE C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIB LIBPATH LIBRARY_PATH LD_LIBRARY_PATH CC CXX CPP CCFLAGS CXXFLAGS CPPFLAGS LDFLAGS ASM RC)
    list(REMOVE_DUPLICATES DEFAULT_ENV_VARS_TO_CHECK)

    #Flags to check. Flags are a bit special since they are configuration aware.
    set(FLAGS ${LANGUAGES} RC SHARED_LINKER STATIC_LINKER EXE_LINKER MODULE_LINKER)
    foreach(flag IN LISTS FLAGS)
        list(APPEND DEFAULT_FLAGS_TO_CHECK CMAKE_${flag}_FLAGS)
    endforeach()
    list(REMOVE_DUPLICATES DEFAULT_FLAGS_TO_CHECK)

    #Language-specific flags.
    foreach(_lang IN LISTS LANGUAGES)
        list(APPEND LANG_FLAGS CMAKE_${_lang}_FLAGS)
    endforeach()
    list(REMOVE_DUPLICATES LANG_FLAGS)

    # TODO if ever necessary: Properties to check

    set(VAR_PREFIX "DETECTED" CACHE STRING "Variable prefix to use for detected flags")
    set(VARS_TO_CHECK "${DEFAULT_VARS_TO_CHECK}" CACHE STRING "Variables to check. If not given there is a list of defaults")
    set(FLAGS_TO_CHECK "${DEFAULT_FLAGS_TO_CHECK}" CACHE STRING "Variables to check. If not given there is a list of defaults")
    set(ENV_VARS_TO_CHECK "${DEFAULT_ENV_VARS_TO_CHECK}" CACHE STRING "Variables to check. If not given there is a list of defaults")

    foreach(VAR IN LISTS VARS_TO_CHECK)
        escaped(value "${${VAR}}")
        string(APPEND OUTPUT_STRING "set(${VAR_PREFIX}_${VAR} \"${value}\")\n")
    endforeach()

    foreach(_env IN LISTS ENV_VARS_TO_CHECK)
        if(CMAKE_HOST_WIN32)
            string(REPLACE "\\" "/" value "$ENV{${_env}}")
            escaped(value "${value}")
        else()
            escaped(value "$ENV{${_env}}")
        endif()
        string(APPEND OUTPUT_STRING "set(${VAR_PREFIX}_ENV_${_env} \"${value}\")\n")
    endforeach()

    set(extra_flags "")
    if(CMAKE_CXX_COMPILER_EXTERNAL_TOOLCHAIN)
        if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
            string(APPEND extra_flags " \"${CMAKE_CXX_COMPILE_OPTIONS_EXTERNAL_TOOLCHAIN}${CMAKE_CXX_COMPILER_EXTERNAL_TOOLCHAIN}\"")
        else()
            string(APPEND extra_flags " ${CMAKE_CXX_COMPILE_OPTIONS_EXTERNAL_TOOLCHAIN} \"${CMAKE_CXX_COMPILER_EXTERNAL_TOOLCHAIN}\"")
        endif()
    endif()
    if(CMAKE_SYSROOT AND CMAKE_CXX_COMPILE_OPTIONS_SYSROOT)
        string(APPEND extra_flags " \"${CMAKE_CXX_COMPILE_OPTIONS_SYSROOT}${CMAKE_SYSROOT}\"")
    endif()

    macro(adjust_flags flag_var)
        if(MSVC) # Transform MSVC /flags to -flags due to msys2 runtime intepreting /flag as a path.
            string(REGEX REPLACE "(^| )/" "\\1-" ${flag_var} "${${flag_var}}")
            if(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
                if("${flag_var}" STREQUAL "CMAKE_CXX_FLAGS")
                    string(APPEND ${flag_var} " -ZW:nostdlib")
                endif()
            endif()
        endif()
        if(APPLE)
            set(flags_to_add_osx_arch_sysroot "${LANG_FLAGS}" CMAKE_SHARED_LINKER_FLAGS CMAKE_MODULE_LINKER_FLAGS CMAKE_EXE_LINKER_FLAGS)
            if("${flag_var}" IN_LIST flags_to_add_osx_arch_sysroot)
                # macOS - append arch and isysroot if cross-compiling
                if(NOT "${CMAKE_OSX_ARCHITECTURES}" STREQUAL "${CMAKE_HOST_SYSTEM_PROCESSOR}")
                    foreach(arch IN LISTS CMAKE_OSX_ARCHITECTURES)
                        string(APPEND ${flag_var} " -arch ${arch}")
                    endforeach()
                endif()
                string(APPEND ${flag_var} " -isysroot ${CMAKE_OSX_SYSROOT}")
                if (CMAKE_OSX_DEPLOYMENT_TARGET)
                    list(GET LANGUAGES 0 lang)
                    string(APPEND ${flag_var} " ${CMAKE_${lang}_OSX_DEPLOYMENT_TARGET_FLAG}${CMAKE_OSX_DEPLOYMENT_TARGET}")
                    unset(lang)
                endif()
            endif()
            unset(flags_to_add_osx_arch_sysroot)
        endif()
        set(flags_to_add_target "${LANG_FLAGS}" CMAKE_SHARED_LINKER_FLAGS CMAKE_MODULE_LINKER_FLAGS CMAKE_EXE_LINKER_FLAGS)
        list(GET LANGUAGES 0 lang)
        if(CMAKE_${lang}_COMPILER_TARGET AND "${flag_var}" IN_LIST flags_to_add_target)
            if (CMAKE_${lang}_COMPILER_ID STREQUAL Clang)
                string(PREPEND ${flag_var} "${CMAKE_${lang}_COMPILE_OPTIONS_TARGET}${CMAKE_${lang}_COMPILER_TARGET} ")
            elseif(CMAKE_${lang}_COMPILE_OPTIONS_TARGET)
                string(PREPEND ${flag_var} "${CMAKE_${lang}_COMPILE_OPTIONS_TARGET} ${CMAKE_${lang}_COMPILER_TARGET} ")
            endif()
        endif()
        if("${flag_var}" IN_LIST flags_to_add_target)
            string(APPEND ${flag_var} " ${extra_flags}")
        endif()
        unset(lang)
        unset(flags_to_add_target)
    endmacro()


    foreach(flag IN LISTS FLAGS_TO_CHECK)
        string(STRIP "${${flag}}" ${flag}) # Strip leading and trailing whitespaces
        adjust_flags(${flag})
        escaped(value "${${flag}}")
        string(APPEND OUTPUT_STRING "set(${VAR_PREFIX}_RAW_${flag} \" ${value}\")\n")
        foreach(config IN LISTS CMAKE_CONFIGURATION_TYPES)
            escaped(raw_value "${CMAKE_${flag}_FLAGS_${config}}")
            string(APPEND OUTPUT_STRING "set(${VAR_PREFIX}_RAW_${flag}_${config} \"${raw_value}\")\n")
            string(STRIP "${${flag}_${config}}" ${flag}_${config})
            adjust_flags(${flag}_${config})
            escaped(combined_value "${${flag}} ${${flag}_${config}}")
            string(STRIP "${combined_value}" combined_value)
            string(APPEND OUTPUT_STRING "set(${VAR_PREFIX}_${flag}_${config} \"${combined_value}\")\n")
        endforeach()
    endforeach()

    file(WRITE "${FLAGS_OUTPUT_FILE}" "${OUTPUT_STRING}")


    # include("${FLAGS_OUTPUT_FILE}")

    # Programs:
    # CMAKE_AR
    # CMAKE_<LANG>_COMPILER_AR (Wrapper)
    # CMAKE_RANLIB
    # CMAKE_<LANG>_COMPILER_RANLIB
    # CMAKE_STRIP
    # CMAKE_NM
    # CMAKE_OBJDUMP
    # CMAKE_DLLTOOL
    # CMAKE_MT
    # CMAKE_LINKER
    # CMAKE_C_COMPILER
    # CMAKE_CXX_COMPILER
    # CMAKE_RC_COMPILER

    # Flags:
    # CMAKE_<LANG>_FLAGS
    # CMAKE_<LANG>_FLAGS_<CONFIG>
    # CMAKE_RC_FLAGS
    # CMAKE_SHARED_LINKER_FLAGS
    # CMAKE_STATIC_LINKER_FLAGS
    # CMAKE_STATIC_LINKER_FLAGS_<CONFIG>
    # CMAKE_EXE_LINKER_FLAGS
    # CMAKE_EXE_LINKER_FLAGS_<CONFIG>

endmacro()




if(TARGET_IS_MINGW)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/mingw.cmake")
    if(NOT _MINGW_TOOLCHAIN)
        set(_MINGW_TOOLCHAIN 1)
        message(STATUS "Loading toolchain: MinGW")
        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
            set(CMAKE_CROSSCOMPILING OFF CACHE BOOL "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")
        endif()

        # Need to override MinGW from CMAKE_SYSTEM_NAME
        set(CMAKE_SYSTEM_NAME Windows CACHE STRING "The name of the operating system for which CMake is to build" FORCE)

        if(TARGET_TRIPLET_ARCH STREQUAL "x86")
            set(CMAKE_SYSTEM_PROCESSOR i686 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "x64")
            set(CMAKE_SYSTEM_PROCESSOR x86_64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm")
            set(CMAKE_SYSTEM_PROCESSOR armv7 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm64")
            set(CMAKE_SYSTEM_PROCESSOR aarch64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        endif()

        foreach(lang C CXX)
            set(CMAKE_${lang}_COMPILER_TARGET "${CMAKE_SYSTEM_PROCESSOR}-windows-gnu" CACHE STRING "The target for cross-compiling, if supported.")
        endforeach()

        find_program(CMAKE_C_COMPILER "${CMAKE_SYSTEM_PROCESSOR}-w64-mingw32-gcc")
        find_program(CMAKE_CXX_COMPILER "${CMAKE_SYSTEM_PROCESSOR}-w64-mingw32-g++")
        find_program(CMAKE_RC_COMPILER "${CMAKE_SYSTEM_PROCESSOR}-w64-mingw32-windres")
        if(NOT CMAKE_RC_COMPILER)
            find_program(CMAKE_RC_COMPILER "windres")
        endif()

        if(MSVC) # Transform MSVC /flags to -flags due to msys2 runtime intepreting /flag as a path.
            string(REGEX REPLACE "(^| )/" "\\1-" ${flag_var} "${${flag_var}}")
            if(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
                if("${flag_var}" STREQUAL "CMAKE_CXX_FLAGS")
                    string(APPEND ${flag_var} " -ZW:nostdlib")
                endif()
            endif()
        endif()

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)
            string(APPEND CMAKE_C_FLAGS_INIT " ${C_FLAGS} ")
            string(APPEND CMAKE_CXX_FLAGS_INIT " ${CXX_FLAGS} ")
            string(APPEND CMAKE_C_FLAGS_DEBUG_INIT " ${C_FLAGS_DEBUG} ")
            string(APPEND CMAKE_CXX_FLAGS_DEBUG_INIT " ${CXX_FLAGS_DEBUG} ")
            string(APPEND CMAKE_C_FLAGS_RELEASE_INIT " ${C_FLAGS_RELEASE} ")
            string(APPEND CMAKE_CXX_FLAGS_RELEASE_INIT " ${CXX_FLAGS_RELEASE} ")

            string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${LINKER_FLAGS} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${LINKER_FLAGS} ")
            if(CRT_LINKAGE STREQUAL "static")
                string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT "-static ")
                string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT "-static ")
            endif()
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " ${LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " ${LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT " ${LINKER_FLAGS_RELEASE} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT " ${LINKER_FLAGS_RELEASE} ")
        endif()
    endif()
elseif(TARGET_IS_XBOX)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/xbox.cmake")
    message(STATUS "Loading toolchain: XBox")
elseif(TARGET_IS_UWP)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/uwp.cmake")
    message(STATUS "Loading toolchain: UWP")
    if(NOT _WINDOWS_TOOLCHAIN)
        set(_WINDOWS_TOOLCHAIN 1)
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>$<$<STREQUAL:${CRT_LINKAGE},dynamic>:DLL>" CACHE STRING "")

        set(CMAKE_SYSTEM_NAME WindowsStore CACHE STRING "The name of the operating system for which CMake is to build.")

        if(TARGET_TRIPLET_ARCH STREQUAL "x86")
            set(CMAKE_SYSTEM_PROCESSOR x86 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "x64")
            set(CMAKE_SYSTEM_PROCESSOR AMD64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm")
            set(CMAKE_SYSTEM_PROCESSOR ARM CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm64")
            set(CMAKE_SYSTEM_PROCESSOR ARM64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        endif()

        if(DEFINED CMAKE_SYSTEM_VERSION)
            set(CMAKE_SYSTEM_VERSION "${CMAKE_SYSTEM_VERSION}" CACHE STRING "The version of the operating system for which CMake is to build." FORCE)
        endif()

        set(CMAKE_CROSSCOMPILING ON CACHE STRING "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")

        if(NOT DEFINED CMAKE_SYSTEM_VERSION)
            set(CMAKE_SYSTEM_VERSION "${CMAKE_HOST_SYSTEM_VERSION}" CACHE STRING "The version of the operating system for which CMake is to build.")
        endif()

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)

            if(NOT (DEFINED MSVC_CXX_WINRT_EXTENSIONS))
                set(MSVC_CXX_WINRT_EXTENSIONS ON)
            endif()

            if(CRT_LINKAGE STREQUAL "dynamic")
                set(CRT_LINK_FLAG_PREFIX "/MD")
            elseif(CRT_LINKAGE STREQUAL "static")
                set(CRT_LINK_FLAG_PREFIX "/MT")
            else()
                message(FATAL_ERROR "Invalid setting for CRT_LINKAGE: \"${CRT_LINKAGE}\". It must be \"static\" or \"dynamic\"")
            endif()

            set(CHARSET_FLAG "/utf-8")
            if (NOT SET_CHARSET_FLAG OR PLATFORM_TOOLSET MATCHES "v120")
                # VS 2013 does not support /utf-8
                set(CHARSET_FLAG)
            endif()

            set(MP_BUILD_FLAG "")
            if(NOT (CMAKE_CXX_COMPILER MATCHES "clang-cl.exe"))
                set(MP_BUILD_FLAG "/MP")
            endif()

            set(_cpp_flags "/DWIN32 /D_WINDOWS /D_UNICODE /DUNICODE /DWINAPI_FAMILY=WINAPI_FAMILY_APP /D__WRL_NO_DEFAULT_LIB__" ) # VS adds /D "_WINDLL" for DLLs;
            set(_common_flags "/nologo /Z7 ${MP_BUILD_FLAG} /GS /Gd /Gm- /W3 /WX- /Zc:wchar_t /Zc:inline /Zc:forScope /fp:precise /Oy- /EHsc")

            #/ZW:nostdlib -> ZW is added by CMake # VS also normally adds /sdl but not cmake MSBUILD
            set(_winmd_flag "")
            if(MSVC_CXX_WINRT_EXTENSIONS)
                file(TO_CMAKE_PATH "$ENV{VCToolsInstallDir}" _vctools)
                set(ENV{_CL_} "/FU\"${_vctools}/lib/x86/store/references/platform.winmd\" $ENV{_CL_}")
                # CMake has problems to correctly pass this in the compiler test so probably need special care in get_cmake_vars
                #set(_vcpkg_winmd_flag "/FU\\\\\"${_vcpkg_vctools}/lib/x86/store/references/platform.winmd\\\\\"") # VS normally passes /ZW for Apps
            endif()

            set(CMAKE_CXX_FLAGS "${_cpp_flags} ${_common_flags} ${_winmd_flag} ${CHARSET_FLAG} ${CXX_FLAGS}" CACHE STRING "Flags for all build types.")
            set(CMAKE_C_FLAGS "${_cpp_flags} ${_common_flags} ${_winmd_flag} ${CHARSET_FLAG} ${C_FLAGS}" CACHE STRING "Flags for all build types.")
            set(CMAKE_RC_FLAGS "-c65001 ${_cpp_flags}" CACHE STRING "Flags for all build types.")

            unset(CHARSET_FLAG)
            unset(_cpp_flags)
            unset(_common_flags)
            unset(_winmd_flag)

            set(CMAKE_CXX_FLAGS_DEBUG "/D_DEBUG ${CRT_LINK_FLAG_PREFIX}d /Od /RTC1 ${CXX_FLAGS_DEBUG}" CACHE STRING "Flags for language CXX when building for the 'DEBUG' configuration.")
            set(CMAKE_C_FLAGS_DEBUG "/D_DEBUG ${CRT_LINK_FLAG_PREFIX}d /Od /RTC1 ${C_FLAGS_DEBUG}" CACHE STRING "Flags for language C when building for the 'DEBUG' configuration.")

            set(CMAKE_CXX_FLAGS_RELEASE "${CRT_LINK_FLAG_PREFIX} /O2 /Oi /Gy /DNDEBUG ${CXX_FLAGS_RELEASE}" CACHE STRING "") # VS adds /GL
            set(CMAKE_C_FLAGS_RELEASE "${CRT_LINK_FLAG_PREFIX} /O2 /Oi /Gy /DNDEBUG ${C_FLAGS_RELEASE}" CACHE STRING "")

            string(APPEND CMAKE_STATIC_LINKER_FLAGS_RELEASE_INIT " /nologo ") # VS adds /LTCG

            if(MSVC_CXX_WINRT_EXTENSIONS)
                set(additional_dll_flags "/WINMD:NO")
                if(CMAKE_GENERATOR MATCHES "Ninja")
                    set(additional_exe_flags "/WINMD") # VS Generator chokes on this in the compiler detection
                endif()
            endif()
            string(APPEND CMAKE_SHARED_LINKER_FLAGS " /MANIFEST:NO /NXCOMPAT /DYNAMICBASE /DEBUG ${additional_dll_flags} /APPCONTAINER /SUBSYSTEM:CONSOLE /MANIFESTUAC:NO ${LINKER_FLAGS}")
            # VS adds /DEBUG:FULL /TLBID:1.    WindowsApp.lib is in CMAKE_C|CXX_STANDARD_LIBRARIES
            string(APPEND CMAKE_EXE_LINKER_FLAGS " /MANIFEST:NO /NXCOMPAT /DYNAMICBASE /DEBUG ${additional_exe_flags} /APPCONTAINER /MANIFESTUAC:NO ${LINKER_FLAGS}")

            set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "/DEBUG /INCREMENTAL:NO /OPT:REF /OPT:ICF ${LINKER_FLAGS_RELEASE}" CACHE STRING "") # VS uses /LTCG:incremental
            set(CMAKE_EXE_LINKER_FLAGS_RELEASE "/DEBUG /INCREMENTAL:NO /OPT:REF /OPT:ICF ${LINKER_FLAGS_RELEASE}" CACHE STRING "")
            string(APPEND CMAKE_STATIC_LINKER_FLAGS_DEBUG_INIT " /nologo ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " /nologo ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " /nologo ${LINKER_FLAGS} ${LINKER_FLAGS_DEBUG} ")
        endif()
    endif()

elseif(TARGET_IS_WINDOWS) # This is also true for MinGW and UWP targets, so place it after those...
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/windows.cmake")
    if(NOT _WINDOWS_TOOLCHAIN)
        set(_WINDOWS_TOOLCHAIN 1)
        message(STATUS "Loading toolchain: Windows")
        set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>$<$<STREQUAL:${CRT_LINKAGE},dynamic>:DLL>" CACHE STRING "Select the MSVC runtime library for use by compilers targeting the MSVC ABI.")

        set(CMAKE_SYSTEM_NAME Windows CACHE STRING "The name of the operating system for which CMake is to build.")

        if(TARGET_TRIPLET_ARCH STREQUAL "x86")
            set(CMAKE_SYSTEM_PROCESSOR x86 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "x64")
            set(CMAKE_SYSTEM_PROCESSOR AMD64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm")
            set(CMAKE_SYSTEM_PROCESSOR ARM CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm64")
            set(CMAKE_SYSTEM_PROCESSOR ARM64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
        endif()

        if(DEFINED CMAKE_SYSTEM_VERSION)
            set(CMAKE_SYSTEM_VERSION "${CMAKE_SYSTEM_VERSION}" CACHE STRING "The version of the operating system for which CMake is to build." FORCE)
        endif()

        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
            if(CMAKE_SYSTEM_PROCESSOR STREQUAL CMAKE_HOST_SYSTEM_PROCESSOR)
                set(CMAKE_CROSSCOMPILING OFF CACHE STRING "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")
            elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86")
                # any of the four platforms can run x86 binaries
                set(CMAKE_CROSSCOMPILING OFF CACHE STRING "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")
            elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "ARM64")
                # arm64 can run binaries of any of the four platforms after Windows 11
                set(CMAKE_CROSSCOMPILING OFF CACHE STRING "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")
            endif()

            if(NOT DEFINED CMAKE_SYSTEM_VERSION)
                set(CMAKE_SYSTEM_VERSION "${CMAKE_HOST_SYSTEM_VERSION}" CACHE STRING "The version of the operating system for which CMake is to build.")
            endif()
        endif()

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)

            if(CRT_LINKAGE STREQUAL "dynamic")
                set(CRT_LINK_FLAG_PREFIX "/MD")
            elseif(CRT_LINKAGE STREQUAL "static")
                set(CRT_LINK_FLAG_PREFIX "/MT")
            else()
                message(FATAL_ERROR "Invalid setting for CRT_LINKAGE: \"${CRT_LINKAGE}\". It must be \"static\" or \"dynamic\"")
            endif()

            set(CHARSET_FLAG "/utf-8")
            if (NOT SET_CHARSET_FLAG OR PLATFORM_TOOLSET MATCHES "v120")
                # VS 2013 does not support /utf-8
                set(CHARSET_FLAG)
            endif()

            set(MP_BUILD_FLAG "")
            if(NOT (CMAKE_CXX_COMPILER MATCHES "clang-cl.exe"))
                set(MP_BUILD_FLAG "/MP")
            endif()

            set(CMAKE_CXX_FLAGS " /nologo /DWIN32 /D_WINDOWS /W3 ${CHARSET_FLAG} /GR /EHsc ${MP_BUILD_FLAG} ${CXX_FLAGS}" CACHE STRING "Flags for all build types.")
            set(CMAKE_C_FLAGS " /nologo /DWIN32 /D_WINDOWS /W3 ${CHARSET_FLAG} ${MP_BUILD_FLAG} ${C_FLAGS}" CACHE STRING "Flags for all build types.")

            if(TARGET_TRIPLET_ARCH STREQUAL "arm64ec")
                string(APPEND CMAKE_CXX_FLAGS " /arm64EC /D_AMD64_ /DAMD64 /D_ARM64EC_ /DARM64EC")
                string(APPEND CMAKE_C_FLAGS " /arm64EC /D_AMD64_ /DAMD64 /D_ARM64EC_ /DARM64EC")
            endif()
            set(CMAKE_RC_FLAGS "-c65001 /DWIN32" CACHE STRING "RC flags for all build types.")

            unset(CHARSET_FLAG)

            set(CMAKE_CXX_FLAGS_DEBUG "/D_DEBUG ${CRT_LINK_FLAG_PREFIX}d /Z7 /Ob0 /Od /RTC1 ${CXX_FLAGS_DEBUG}" CACHE STRING "Flags for language CXX when building for the 'DEBUG' configuration.")
            set(CMAKE_C_FLAGS_DEBUG "/D_DEBUG ${CRT_LINK_FLAG_PREFIX}d /Z7 /Ob0 /Od /RTC1 ${C_FLAGS_DEBUG}" CACHE STRING "Flags for language C when building for the 'DEBUG' configuration.")
            set(CMAKE_CXX_FLAGS_RELEASE "${CRT_LINK_FLAG_PREFIX} /O2 /Oi /Gy /DNDEBUG /Z7 ${CXX_FLAGS_RELEASE}" CACHE STRING "Flags for language CXX when building for the 'RELEASE' configuration.")
            set(CMAKE_C_FLAGS_RELEASE "${CRT_LINK_FLAG_PREFIX} /O2 /Oi /Gy /DNDEBUG /Z7 ${C_FLAGS_RELEASE}" CACHE STRING "Flags for language C when building for the 'RELEASE' configuration.")

            string(APPEND CMAKE_STATIC_LINKER_FLAGS_RELEASE_INIT " /nologo ")
            set(CMAKE_SHARED_LINKER_FLAGS_RELEASE "/nologo /DEBUG /INCREMENTAL:NO /OPT:REF /OPT:ICF ${LINKER_FLAGS} ${LINKER_FLAGS_RELEASE}" CACHE STRING "Flags to be used when linking a shared library.")
            set(CMAKE_EXE_LINKER_FLAGS_RELEASE "/nologo /DEBUG /INCREMENTAL:NO /OPT:REF /OPT:ICF ${LINKER_FLAGS} ${LINKER_FLAGS_RELEASE}" CACHE STRING "Flags to be used when linking an executable.")

            string(APPEND CMAKE_STATIC_LINKER_FLAGS_DEBUG_INIT " /nologo ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " /nologo ${LINKER_FLAGS} ${LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " /nologo ${LINKER_FLAGS} ${LINKER_FLAGS_DEBUG} ")
        endif()
    endif()

elseif(TARGET_IS_LINUX)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/linux.cmake")
    message(STATUS "Loading toolchain: Linux")
    if(NOT _LINUX_TOOLCHAIN)
        set(_LINUX_TOOLCHAIN 1)
        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
            set(CMAKE_CROSSCOMPILING OFF CACHE BOOL "")
        endif()
        set(CMAKE_SYSTEM_NAME Linux CACHE STRING "")
        if(TARGET_TRIPLET_ARCH STREQUAL "x64")
            set(CMAKE_SYSTEM_PROCESSOR x86_64 CACHE STRING "")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "x86")
            set(CMAKE_SYSTEM_PROCESSOR x86 CACHE STRING "")
            string(APPEND VCPKG_C_FLAGS " -m32")
            string(APPEND VCPKG_CXX_FLAGS " -m32")
            string(APPEND VCPKG_LINKER_FLAGS " -m32")
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm")
            set(CMAKE_SYSTEM_PROCESSOR armv7l CACHE STRING "")
            if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "x86_64")
                if(NOT DEFINED CMAKE_CXX_COMPILER)
                    set(CMAKE_CXX_COMPILER "arm-linux-gnueabihf-g++")
                endif()
                if(NOT DEFINED CMAKE_C_COMPILER)
                    set(CMAKE_C_COMPILER "arm-linux-gnueabihf-gcc")
                endif()
                if(NOT DEFINED CMAKE_ASM_COMPILER)
                    set(CMAKE_ASM_COMPILER "arm-linux-gnueabihf-gcc")
                endif()
                if(NOT DEFINED CMAKE_ASM-ATT_COMPILER)
                    set(CMAKE_ASM-ATT_COMPILER "arm-linux-gnueabihf-as")
                endif()
                message(STATUS "Cross compiling arm on host x86_64, use cross compiler: ${CMAKE_CXX_COMPILER}/${CMAKE_C_COMPILER}")
            endif()
        elseif(TARGET_TRIPLET_ARCH STREQUAL "arm64")
            set(CMAKE_SYSTEM_PROCESSOR aarch64 CACHE STRING "")
            if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux"  AND CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "x86_64")
                if(NOT DEFINED CMAKE_CXX_COMPILER)
                    set(CMAKE_CXX_COMPILER "aarch64-linux-gnu-g++")
                endif()
                if(NOT DEFINED CMAKE_C_COMPILER)
                    set(CMAKE_C_COMPILER "aarch64-linux-gnu-gcc")
                endif()
                if(NOT DEFINED CMAKE_ASM_COMPILER)
                    set(CMAKE_ASM_COMPILER "aarch64-linux-gnu-gcc")
                endif()
                if(NOT DEFINED CMAKE_ASM-ATT_COMPILER)
                    set(CMAKE_ASM-ATT_COMPILER "aarch64-linux-gnu-as")
                endif()
                message(STATUS "Cross compiling arm64 on host x86_64, use cross compiler: ${CMAKE_CXX_COMPILER}/${CMAKE_C_COMPILER}")
            endif()
        endif()

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)
            string(APPEND CMAKE_C_FLAGS_INIT " -fPIC ${VCPKG_C_FLAGS} ")
            string(APPEND CMAKE_CXX_FLAGS_INIT " -fPIC ${VCPKG_CXX_FLAGS} ")
            string(APPEND CMAKE_C_FLAGS_DEBUG_INIT " ${VCPKG_C_FLAGS_DEBUG} ")
            string(APPEND CMAKE_CXX_FLAGS_DEBUG_INIT " ${VCPKG_CXX_FLAGS_DEBUG} ")
            string(APPEND CMAKE_C_FLAGS_RELEASE_INIT " ${VCPKG_C_FLAGS_RELEASE} ")
            string(APPEND CMAKE_CXX_FLAGS_RELEASE_INIT " ${VCPKG_CXX_FLAGS_RELEASE} ")

            string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            if(VCPKG_CRT_LINKAGE STREQUAL "static")
                string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT "-static ")
                string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT "-static ")
            endif()
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
        endif()
    endif()

elseif(TARGET_IS_ANDROID)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/android.cmake")
    set(ANDROID_CPP_FEATURES "rtti exceptions" CACHE STRING "")
    set(CMAKE_SYSTEM_NAME Android CACHE STRING "")
    set(ANDROID_TOOLCHAIN clang CACHE STRING "")
    set(ANDROID_NATIVE_API_LEVEL ${CMAKE_SYSTEM_VERSION} CACHE STRING "")
    if(CMAKE_SYSTEM_VERSION MATCHES "^[0-9]+$")
        set(ANDROID_PLATFORM android-${CMAKE_SYSTEM_VERSION} CACHE STRING "")
    else()
        set(ANDROID_PLATFORM ${CMAKE_SYSTEM_VERSION} CACHE STRING "")
    endif()
    set(CMAKE_ANDROID_NDK_TOOLCHAIN_VERSION clang CACHE STRING "")

    if (CRT_LINKAGE STREQUAL "dynamic")
        set(ANDROID_STL c++_shared CACHE STRING "")
    else()
        set(ANDROID_STL c++_static CACHE STRING "")
    endif()

    if(DEFINED ENV{ANDROID_NDK_HOME})
        set(ANDROID_NDK_HOME $ENV{ANDROID_NDK_HOME})
    else()
        set(ANDROID_NDK_HOME "$ENV{ProgramData}/Microsoft/AndroidNDK64/android-ndk-r13b/")
        if(NOT EXISTS "${ANDROID_NDK_HOME}")
            # Use Xamarin default installation folder
            set(ANDROID_NDK_HOME "$ENV{ProgramFiles\(x86\)}/Android/android-sdk/ndk-bundle")
        endif()
    endif()

    if(NOT EXISTS "${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake")
        message(FATAL_ERROR "Could not find android ndk. Searched at ${ANDROID_NDK_HOME}")
    endif()

    include("${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake")

    if(NOT _VCPKG_ANDROID_TOOLCHAIN)
        set(_VCPKG_ANDROID_TOOLCHAIN 1)
        message(STATUS "Loading toolchain: Android")
        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)
            string(APPEND CMAKE_C_FLAGS " -fPIC ${VCPKG_C_FLAGS} ")
            string(APPEND CMAKE_CXX_FLAGS " -fPIC ${VCPKG_CXX_FLAGS} ")
            string(APPEND CMAKE_C_FLAGS_DEBUG " ${VCPKG_C_FLAGS_DEBUG} ")
            string(APPEND CMAKE_CXX_FLAGS_DEBUG " ${VCPKG_CXX_FLAGS_DEBUG} ")
            string(APPEND CMAKE_C_FLAGS_RELEASE " ${VCPKG_C_FLAGS_RELEASE} ")
            string(APPEND CMAKE_CXX_FLAGS_RELEASE " ${VCPKG_CXX_FLAGS_RELEASE} ")

            string(APPEND CMAKE_SHARED_LINKER_FLAGS " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE " ${VCPKG_LINKER_FLAGS_RELEASE} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE " ${VCPKG_LINKER_FLAGS_RELEASE} ")
        endif()
    endif()
elseif(TARGET_IS_OSX)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/osx.cmake")
    if(NOT _OSX_TOOLCHAIN)
        set(_OSX_TOOLCHAIN 1)
        message(STATUS "Loading toolchain: OSX")

        set(CMAKE_SYSTEM_NAME Darwin CACHE STRING "")

        set(CMAKE_MACOSX_RPATH ON CACHE BOOL "Whether to use rpaths on macOS and iOS.")

        if(NOT DEFINED CMAKE_SYSTEM_PROCESSOR)
            if(TARGET_TRIPLET_ARCH STREQUAL "x64")
                set(CMAKE_SYSTEM_PROCESSOR x86_64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
            elseif(TARGET_TRIPLET_ARCH STREQUAL "x86")
                set(CMAKE_SYSTEM_PROCESSOR x86 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
            elseif(TARGET_TRIPLET_ARCH STREQUAL "arm64")
                set(CMAKE_SYSTEM_PROCESSOR arm64 CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
            else()
                set(CMAKE_SYSTEM_PROCESSOR "${CMAKE_HOST_SYSTEM_PROCESSOR}" CACHE STRING "When not cross-compiling, this variable has the same value as the ``CMAKE_HOST_SYSTEM_PROCESSOR`` variable.")
            endif()
        endif()

        if(DEFINED CMAKE_SYSTEM_VERSION)
            set(CMAKE_SYSTEM_VERSION "${CMAKE_SYSTEM_VERSION}" CACHE STRING "The version of the operating system for which CMake is to build." FORCE)
        endif()

        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
            if(CMAKE_SYSTEM_PROCESSOR STREQUAL CMAKE_HOST_SYSTEM_PROCESSOR)
                set(CMAKE_CROSSCOMPILING OFF CACHE STRING "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")
            elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "ARM64")
                # arm64 macOS can run x64 binaries
                set(CMAKE_CROSSCOMPILING OFF CACHE STRING "Intended to indicate whether CMake is cross compiling, but note limitations discussed below.")
            endif()

            if(NOT DEFINED CMAKE_SYSTEM_VERSION)
                set(CMAKE_SYSTEM_VERSION "${CMAKE_HOST_SYSTEM_VERSION}" CACHE STRING "The version of the operating system for which CMake is to build.")
            endif()
        endif()

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)
            string(APPEND CMAKE_C_FLAGS_INIT " -fPIC ${VCPKG_C_FLAGS} ")
            string(APPEND CMAKE_CXX_FLAGS_INIT " -fPIC ${VCPKG_CXX_FLAGS} ")
            string(APPEND CMAKE_C_FLAGS_DEBUG_INIT " ${VCPKG_C_FLAGS_DEBUG} ")
            string(APPEND CMAKE_CXX_FLAGS_DEBUG_INIT " ${VCPKG_CXX_FLAGS_DEBUG} ")
            string(APPEND CMAKE_C_FLAGS_RELEASE_INIT " ${VCPKG_C_FLAGS_RELEASE} ")
            string(APPEND CMAKE_CXX_FLAGS_RELEASE_INIT " ${VCPKG_CXX_FLAGS_RELEASE} ")

            string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
        endif()
    endif()
    # End of OSX toolchain.

elseif(TARGET_IS_IOS)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/ios.cmake")
    message(STATUS "Using toolchain: iOS")
elseif(TARGET_IS_FREEBSD)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/freebsd.cmake")
    if(NOT _FREEBSD_TOOLCHAIN)
        set(_FREEBSD_TOOLCHAIN 1)
        message(STATUS "Using toolchain: FreeBSD")
        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "FreeBSD")
            set(CMAKE_CROSSCOMPILING OFF CACHE BOOL "")
        endif()
        set(CMAKE_SYSTEM_NAME FreeBSD CACHE STRING "")

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)
            string(APPEND CMAKE_C_FLAGS_INIT " -fPIC ${VCPKG_C_FLAGS} ")
            string(APPEND CMAKE_CXX_FLAGS_INIT " -fPIC ${VCPKG_CXX_FLAGS} ")
            string(APPEND CMAKE_C_FLAGS_DEBUG_INIT " ${VCPKG_C_FLAGS_DEBUG} ")
            string(APPEND CMAKE_CXX_FLAGS_DEBUG_INIT " ${VCPKG_CXX_FLAGS_DEBUG} ")
            string(APPEND CMAKE_C_FLAGS_RELEASE_INIT " ${VCPKG_C_FLAGS_RELEASE} ")
            string(APPEND CMAKE_CXX_FLAGS_RELEASE_INIT " ${VCPKG_CXX_FLAGS_RELEASE} ")

            string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
        endif()
    endif()
    # End of FreeBSD toolchain.

elseif(TARGET_IS_OPENBSD)
    # set(TOOLCHAIN_FILE "${TOOLCHAIN_FILES_DIR}/openbsd.cmake")
    if(NOT _OPENBSD_TOOLCHAIN)
        set(_OPENBSD_TOOLCHAIN 1)
        message(STATUS "Loading toolchain: OpenBSD")

        if(CMAKE_HOST_SYSTEM_NAME STREQUAL "OpenBSD")
            set(CMAKE_CROSSCOMPILING OFF CACHE BOOL "")
        endif()
        set(CMAKE_SYSTEM_NAME OpenBSD CACHE STRING "")

        if(NOT DEFINED CMAKE_CXX_COMPILER)
            set(CMAKE_CXX_COMPILER "/usr/bin/clang++")
        endif()
        if(NOT DEFINED CMAKE_C_COMPILER)
            set(CMAKE_C_COMPILER "/usr/bin/clang")
        endif()

        get_property( _TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE )
        if(NOT _TOOLCHAIN_IN_TRY_COMPILE)
            string(APPEND CMAKE_C_FLAGS_INIT " -fPIC ${VCPKG_C_FLAGS} ")
            string(APPEND CMAKE_CXX_FLAGS_INIT " -fPIC ${VCPKG_CXX_FLAGS} ")
            string(APPEND CMAKE_C_FLAGS_DEBUG_INIT " ${VCPKG_C_FLAGS_DEBUG} ")
            string(APPEND CMAKE_CXX_FLAGS_DEBUG_INIT " ${VCPKG_CXX_FLAGS_DEBUG} ")
            string(APPEND CMAKE_C_FLAGS_RELEASE_INIT " ${VCPKG_C_FLAGS_RELEASE} ")
            string(APPEND CMAKE_CXX_FLAGS_RELEASE_INIT " ${VCPKG_CXX_FLAGS_RELEASE} ")

            string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT " ${VCPKG_LINKER_FLAGS} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_DEBUG_INIT " ${VCPKG_LINKER_FLAGS_DEBUG} ")
            string(APPEND CMAKE_SHARED_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
            string(APPEND CMAKE_EXE_LINKER_FLAGS_RELEASE_INIT " ${VCPKG_LINKER_FLAGS_RELEASE} ")
        endif(NOT _TOOLCHAIN_IN_TRY_COMPILE)
    endif(NOT _OPENBSD_TOOLCHAIN)
    # End of OpenBSD toolchain.

elseif(TARGET_IS_EMSCRIPTEN)
    # set(TOOLCHAIN_FILE "${EMSCRIPTEN_ROOT}/cmake/Modules/Platform/Emscripten.cmake")
    message(STATUS "Loading toolchain: Emscripten")
    include("${EMSCRIPTEN_ROOT}/cmake/Modules/Platform/Emscripten.cmake")
    # End of WebAssembly toolchain.
endif()


# Determine whether the toolchain is loaded during a try-compile configuration
get_property(TOOLCHAIN_IN_TRY_COMPILE GLOBAL PROPERTY IN_TRY_COMPILE)

if(USE_TOOLCHAIN)
    cmake_policy(POP)
    message(STATUS "Toolchain returning as expected.")
    return()
endif()

function(_add_executable)
    add_executable(${ARGS})
endfunction()

function(_add_library)
    add_library(${ARGS})
endfunction()

#If CMake does not have a mapping for MinSizeRel and RelWithDebInfo in imported targets
#it will map those configuration to the first valid configuration in CMAKE_CONFIGURATION_TYPES or the targets IMPORTED_CONFIGURATIONS.
#In most cases this is the debug configuration which is wrong.
# if(NOT DEFINED CMAKE_MAP_IMPORTED_CONFIG_MINSIZEREL)
#     set(CMAKE_MAP_IMPORTED_CONFIG_MINSIZEREL "MinSizeRel;Release;")
#     if(VERBOSE)
#         message(STATUS "CMAKE_MAP_IMPORTED_CONFIG_MINSIZEREL set to MinSizeRel;Release;")
#     endif()
# endif()
# if(NOT DEFINED CMAKE_MAP_IMPORTED_CONFIG_RELWITHDEBINFO)
#     set(CMAKE_MAP_IMPORTED_CONFIG_RELWITHDEBINFO "RelWithDebInfo;Release;")
#     if(VERBOSE)
#         message(STATUS "CMAKE_MAP_IMPORTED_CONFIG_RELWITHDEBINFO set to RelWithDebInfo;Release;")
#     endif()
# endif()

######
# If tripet was passed in, use it and move on. Else, detect triplet arch from current generator...
if(TARGET_TRIPLET)

    # This is required since a user might do: 'set(VCPKG_TARGET_TRIPLET somevalue)' [no CACHE] before the first project() call
    # Latter within the toolchain file we do: 'set(VCPKG_TARGET_TRIPLET somevalue CACHE STRING "")' which
    # will otherwise override the user setting of VCPKG_TARGET_TRIPLET in the current scope of the toolchain since the CACHE value
    # did not exist previously. Since the value is newly created CMake will use the CACHE value within this scope since it is the more
    # recently created value in directory scope. This 'strange' behaviour only happens on the very first configure call since subsequent
    # configure call will see the user value as the more recent value. The same logic must be applied to all cache values within this file!
    # The FORCE keyword is required to ALWAYS lift the user provided/previously set value into a CACHE value.
    set(TARGET_TRIPLET "${TARGET_TRIPLET}" CACHE STRING "Target triplet (ex. x86-windows)" FORCE)

# If TARGET_TRIPLET wasn't passed in on the command line, search for reasonable defaults...
endif()

if(CMAKE_GENERATOR_PLATFORM MATCHES "^[Ww][Ii][Nn]32$")
    set(TARGET_TRIPLET_ARCH x86)
elseif(CMAKE_GENERATOR_PLATFORM MATCHES "^[Xx]64$")
    set(TARGET_TRIPLET_ARCH x64)
elseif(CMAKE_GENERATOR_PLATFORM MATCHES "^[Aa][Rr][Mm]$")
    set(TARGET_TRIPLET_ARCH arm)
elseif(CMAKE_GENERATOR_PLATFORM MATCHES "^[Aa][Rr][Mm]64$")
    set(TARGET_TRIPLET_ARCH arm64)
else()
    if(CMAKE_GENERATOR STREQUAL "Visual Studio 14 2015 Win64")
        set(TARGET_TRIPLET_ARCH x64)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 14 2015 ARM")
        set(TARGET_TRIPLET_ARCH arm)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 14 2015")
        set(TARGET_TRIPLET_ARCH x86)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 15 2017 Win64")
        set(TARGET_TRIPLET_ARCH x64)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 15 2017 ARM")
        set(TARGET_TRIPLET_ARCH arm)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 15 2017")
        set(TARGET_TRIPLET_ARCH x86)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 16 2019" AND CMAKE_VS_PLATFORM_NAME_DEFAULT STREQUAL "ARM64")
        set(TARGET_TRIPLET_ARCH arm64)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 16 2019")
        set(TARGET_TRIPLET_ARCH x64)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 17 2022" AND CMAKE_VS_PLATFORM_NAME_DEFAULT STREQUAL "ARM64")
        set(TARGET_TRIPLET_ARCH arm64)
    elseif(CMAKE_GENERATOR STREQUAL "Visual Studio 17 2022")
        set(TARGET_TRIPLET_ARCH x64)
    else()
        find_program(CL cl)
        if(CL MATCHES "amd64/cl.exe$" OR CL MATCHES "x64/cl.exe$")
            set(TARGET_TRIPLET_ARCH x64)
        elseif(CL MATCHES "arm/cl.exe$")
            set(TARGET_TRIPLET_ARCH arm)
        elseif(CL MATCHES "arm64/cl.exe$")
            set(TARGET_TRIPLET_ARCH arm64)
        elseif(CL MATCHES "bin/cl.exe$" OR CL MATCHES "x86/cl.exe$")
            set(TARGET_TRIPLET_ARCH x86)
        elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin" AND DEFINED CMAKE_SYSTEM_NAME AND NOT CMAKE_SYSTEM_NAME STREQUAL "Darwin")
            list(LENGTH OSX_ARCHITECTURES OSX_ARCH_COUNT)
            if(OSX_ARCH_COUNT EQUAL "0")
                message(WARNING "Unable to determine target architecture. "
                                "Consider providing a value for the OSX_ARCHITECTURES cache variable. "
                                "Continuing without toolchain.")
                set(USE_TOOLCHAIN ON)
                cmake_policy(POP)
                message(WARNING "Toolchain returning unusually at line ${CMAKE_CURRENT_LIST_LINE}")
                return()
            endif()

            if(OSX_ARCH_COUNT GREATER "1")
                message(WARNING "Detected more than one target architecture. Using the first one.")
            endif()
            list(GET CMAKE_OSX_ARCHITECTURES "0" OSX_TARGET_ARCH)
            if(OSX_TARGET_ARCH STREQUAL "arm64")
                set(TARGET_TRIPLET_ARCH arm64)
            elseif(OSX_TARGET_ARCH STREQUAL "arm64s")
                set(TARGET_TRIPLET_ARCH arm64s)
            elseif(OSX_TARGET_ARCH STREQUAL "armv7s")
                set(TARGET_TRIPLET_ARCH armv7s)
            elseif(OSX_TARGET_ARCH STREQUAL "armv7")
                set(TARGET_TRIPLET_ARCH arm)
            elseif(OSX_TARGET_ARCH STREQUAL "x86_64")
                set(TARGET_TRIPLET_ARCH x64)
            elseif(OSX_TARGET_ARCH STREQUAL "i386")
                set(TARGET_TRIPLET_ARCH x86)
            else()
                message(WARNING "Unable to determine target architecture, continuing without toolchain.")
                set(USE_TOOLCHAIN ON)
                cmake_policy(POP)
                message(WARNING "Toolchain returning unusually at line ${CMAKE_CURRENT_LIST_LINE}")
                return()
            endif()
        elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "x86_64" OR
               CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "AMD64" OR
                # CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "x64" OR
               CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "amd64")
            set(TARGET_TRIPLET_ARCH x64)
        elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "s390x")
            set(TARGET_TRIPLET_ARCH s390x)
        elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "ppc64le")
            set(TARGET_TRIPLET_ARCH ppc64le)
        elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "armv7l")
            set(TARGET_TRIPLET_ARCH arm)
        elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
            set(TARGET_TRIPLET_ARCH arm64)
	elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "riscv32")
	    set(TARGET_TRIPLET_ARCH riscv32)
	elseif(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "riscv64")
	    set(TARGET_TRIPLET_ARCH riscv64)
        else()
            if(TOOLCHAIN_IN_TRY_COMPILE)
                message(STATUS "Unable to determine target architecture.")
            else()
                message(WARNING "Unable to determine target architecture.")
            endif()
            set(USE_TOOLCHAIN ON)
            cmake_policy(POP)
            message(WARNING "Toolchain returning unsually at line ${CMAKE_CURRENT_LIST_LINE}")
            return()
        endif()
    endif()
endif()


#######

# Set target triplet platform from deduced CMake system name...
if(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore" OR CMAKE_SYSTEM_NAME STREQUAL "WindowsPhone")
    set(TARGET_TRIPLET_PLATFORM uwp)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR (NOT CMAKE_SYSTEM_NAME AND CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux"))
    set(TARGET_TRIPLET_PLATFORM linux)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR (NOT CMAKE_SYSTEM_NAME AND CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin"))
    set(TARGET_TRIPLET_PLATFORM osx)
elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(TARGET_TRIPLET_PLATFORM ios)
elseif(MINGW OR (CMAKE_SYSTEM_NAME OR CMAKE_HOST_SYSTEM_NAME STREQUAL "MSYS"))
    message(WARNING "Detected Mingw")
    set(TARGET_TRIPLET_PLATFORM mingw-dynamic)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR (NOT CMAKE_SYSTEM_NAME AND CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows"))
    if(XBOX_CONSOLE_TARGET STREQUAL "scarlett")
        set(TARGET_TRIPLET_PLATFORM xbox-scarlett)
    elseif(XBOX_CONSOLE_TARGET STREQUAL "xboxone")
        set(TARGET_TRIPLET_PLATFORM xbox-xboxone)
    else()
        set(TARGET_TRIPLET_PLATFORM windows)
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD" OR (NOT CMAKE_SYSTEM_NAME AND CMAKE_HOST_SYSTEM_NAME STREQUAL "FreeBSD"))
    set(TARGET_TRIPLET_PLATFORM freebsd)
endif()

if(EMSCRIPTEN)
    set(TARGET_TRIPLET_ARCH wasm32)
    set(TARGET_TRIPLET_PLATFORM emscripten)
endif()

set(TARGET_TRIPLET_ARCH "${TARGET_TRIPLET_ARCH}" CACHE STRING "")
set(TARGET_TRIPLET_PLATFORM "${TARGET_TRIPLET_PLATFORM}" CACHE STRING "")
set(TARGET_TRIPLET "${TARGET_TRIPLET_ARCH}-${TARGET_TRIPLET_PLATFORM}" CACHE STRING "Target triplet (ex. x86-windows)")

message(STATUS "TARGET_TRIPLET = ${TARGET_TRIPLET}")
message(STATUS "TARGET_TRIPLET_ARCH = ${TARGET_TRIPLET_ARCH}")
message(STATUS "TARGET_TRIPLET_PLATFORM = ${TARGET_TRIPLET_PLATFORM}")

# Set target (triplet?) architecture from detected target triplet...
if(TARGET_TRIPLET STREQUAL "x64-windows-dynamic" OR TARGET_TRIPLET STREQUAL "x64-windows")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x64-windows.cmake")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
elseif(TARGET_TRIPLET STREQUAL "x64-windows-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x64-windows-static.cmake")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "x64-windows-static-md")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/x64-windows-static-md.cmake")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "x86-windows-dynamic" OR TARGET_TRIPLET STREQUAL "x86-windows")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x86-windows.cmake")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
elseif(TARGET_TRIPLET STREQUAL "x86-windows-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/x86-windows-static.cmake")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "x86-windows-static-md")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/x86-windows-static-md.cmake")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "arm64-windows-dynamic" OR TARGET_TRIPLET STREQUAL "arm64-windows")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/arm64-windows.cmake")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
elseif(TARGET_TRIPLET STREQUAL "arm64-windows-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/arm64-windows-static.cmake")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "arm64-windows-static-md")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/arm64-windows-static-md.cmake")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "arm-windows-dynamic" OR TARGET_TRIPLET STREQUAL "arm-windows")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/arm-windows.cmake")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
elseif(TARGET_TRIPLET STREQUAL "arm-windows-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/arm-windows-static.cmake")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
elseif(TARGET_TRIPLET STREQUAL "arm-windows-static-md")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/arm-windows-static-md.cmake")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)

    # Linux triplets
elseif(TARGET_TRIPLET STREQUAL "x64-linux-dynamic" OR TARGET_TRIPLET STREQUAL "x64-linux") #this is not correct...
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x64-linux.cmake")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "x64-linux-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x64-linux-static.cmake")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "x86-linux-dynamic" OR TARGET_TRIPLET STREQUAL "x86-linux")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/x86-linux.cmake")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "x86-linux-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x64-linux-static.cmake")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "arm-linux-dynamic" OR TARGET_TRIPLET STREQUAL "arm-linux")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/x64-linux.cmake")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "arm-linux-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/arm-linux-static.cmake")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "arm64-linux-dynamic" OR TARGET_TRIPLET STREQUAL "arm64-linux")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/x86-linux.cmake")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "arm64-linux-static")
    # set(TRIPLET_FILE "${TRIPLET_FILES_DIR}/community/x64-linux-static.cmake")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)

    # Darwin triplets
elseif(TARGET_TRIPLET STREQUAL "x64-osx-static" OR TARGET_TRIPLET STREQUAL "x64-osx") #inverted defaults for osx...
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Darwin)
    set(OSX_ARCHITECTURES x86_64)
elseif(TARGET_TRIPLET STREQUAL "x64-osx-dynamic")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME Darwin)
    set(OSX_ARCHITECTURES x86_64)
elseif(TARGET_TRIPLET STREQUAL "x86-osx-static" OR TARGET_TRIPLET STREQUAL "x86-osx")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Darwin)
    set(OSX_ARCHITECTURES x86_64)
elseif(TARGET_TRIPLET STREQUAL "x86-osx-dynamic")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME Darwin)
    set(OSX_ARCHITECTURES x86_64)
elseif(TARGET_TRIPLET STREQUAL "arm64-osx-static" OR TARGET_TRIPLET STREQUAL "arm64-osx")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Darwin)
    set(OSX_ARCHITECTURES arm64)
elseif(TARGET_TRIPLET STREQUAL "arm64-osx-dynamic")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME Darwin)
    set(OSX_ARCHITECTURES arm64)
    # On macOS, two architecture are supported: x86_64 is the architecture of Intel's 64-bit CPUs, sometimes also simply referred to as x64. It is the architecture for all Intel Macs shipped between 2005 and 2021. arm64 is the architecture used by newer Macs built on Apple Silicon, shipped in late 2020 and beyond.

    # MinGW triplets
elseif(TARGET_TRIPLET STREQUAL "x64-mingw-dynamic" OR TARGET_TRIPLET STREQUAL "x64-mingw")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
    # set(VCPKG_POLICY_DLLS_WITHOUT_LIBS enabled)
elseif(TARGET_TRIPLET STREQUAL "x64-mingw-static")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
elseif(TARGET_TRIPLET STREQUAL "x86-mingw-dynamic" OR TARGET_TRIPLET STREQUAL "x86-mingw")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
    # set(VCPKG_POLICY_DLLS_WITHOUT_LIBS enabled)
elseif(TARGET_TRIPLET STREQUAL "x86-mingw-static")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
elseif(TARGET_TRIPLET STREQUAL "arm64-mingw-dynamic" OR TARGET_TRIPLET STREQUAL "arm64-mingw")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
    # set(VCPKG_POLICY_DLLS_WITHOUT_LIBS enabled)
elseif(TARGET_TRIPLET STREQUAL "arm64-mingw-static")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
elseif(TARGET_TRIPLET STREQUAL "arm-mingw-dynamic" OR TARGET_TRIPLET STREQUAL "arm-mingw")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)
    # set(VCPKG_POLICY_DLLS_WITHOUT_LIBS enabled)
elseif(TARGET_TRIPLET STREQUAL "arm-mingw-static")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME MinGW)
    # set(VCPKG_ENV_PASSTHROUGH PATH)

    # Misc. triplets
elseif(TARGET_TRIPLET STREQUAL "x64-freebsd")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME FreeBSD)
elseif(TARGET_TRIPLET STREQUAL "x86-freebsd")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME FreeBSD)
elseif(TARGET_TRIPLET STREQUAL "x64-openbsd") # No x86 OpenBSD support?
    # Use with VCPKG_FORCE_SYSTEM_BINARIES=1 ./vcpkg install brotli
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME OpenBSD)
elseif(TARGET_TRIPLET STREQUAL "ppc64le-linux")
    set(TARGET_TRIPLET_ARCH ppc64le)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "riscv32-linux")
    set(TARGET_TRIPLET_ARCH riscv32)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "riscv64-linux")
    set(TARGET_TRIPLET_ARCH riscv64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "s390x-linux")
    set(TARGET_TRIPLET_ARCH s390x)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Linux)
elseif(TARGET_TRIPLET STREQUAL "x86-windows-v120")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(PLATFORM_TOOLSET "v120")
    # set(VCPKG_DEP_INFO_OVERRIDE_VARS "v120")

    # uwp triplets
elseif(TARGET_TRIPLET STREQUAL "x64-uwp-dynamic" OR TARGET_TRIPLET STREQUAL "x64-uwp") # No 'static' CRT for uwp targets...
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME WindowsStore)
    set(CMAKE_SYSTEM_VERSION 10.0)
elseif(TARGET_TRIPLET STREQUAL "x64-uwp-static-md")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME WindowsStore)
    set(CMAKE_SYSTEM_VERSION 10.0)
elseif(TARGET_TRIPLET STREQUAL "x686-uwp-dynamic" OR TARGET_TRIPLET STREQUAL "x86-uwp")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(CMAKE_SYSTEM_NAME WindowsStore)
    set(CMAKE_SYSTEM_VERSION 10.0)
elseif(TARGET_TRIPLET STREQUAL "x86-uwp-static-md")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME WindowsStore)
    set(CMAKE_SYSTEM_VERSION 10.0)

    # android triplets
elseif(TARGET_TRIPLET STREQUAL "x64-android")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Android)
    set(MAKEFILE_BUILD_TRIPLET "--host=x86_64-linux-android")
    set(ANDROID_ABI x86_64)
elseif(TARGET_TRIPLET STREQUAL "x86-android")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Android)
    set(MAKEFILE_BUILD_TRIPLET "--host=x86_64-linux-android")
    set(ANDROID_ABI x86)
elseif(TARGET_TRIPLET STREQUAL "arm64-android")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Android)
    set(MAKEFILE_BUILD_TRIPLET "--host=aarch64-linux-android")
    set(ANDROID_ABI arm64-v8a)
elseif(TARGET_TRIPLET STREQUAL "arm-android")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Android)
    set(MAKEFILE_BUILD_TRIPLET "--host=armv7a-linux-androideabi")
    set(ANDROID_ABI armeabi-v7a)
    set(ANDROID_ARM_NEON OFF)
elseif(TARGET_TRIPLET STREQUAL "arm-neon-android")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Android)
    set(MAKEFILE_BUILD_TRIPLET "--host=armv7a-linux-androideabi")
    set(ANDROID_ABI armeabi-v7a)
    set(ANDROID_ARM_NEON ON)
elseif(TARGET_TRIPLET STREQUAL "armv6-android")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE static)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Android)
    set(ANDROID_ABI armeabi)
    set(ANDROID_ARM_MODE arm)

    # iOS triplets
elseif(TARGET_TRIPLET STREQUAL "x64-ios")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME iOS)
elseif(TARGET_TRIPLET STREQUAL "x86-ios")
    set(TARGET_TRIPLET_ARCH x86)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME iOS)
elseif(TARGET_TRIPLET STREQUAL "arm64-ios")
    set(TARGET_TRIPLET_ARCH arm64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME iOS)
elseif(TARGET_TRIPLET STREQUAL "arm-ios")
    set(TARGET_TRIPLET_ARCH arm)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME iOS)

    # Xbox triplets
elseif(TARGET_TRIPLET STREQUAL "x64-xbox-xboxone-dynamic" OR TARGET_TRIPLET STREQUAL "x64-xbox-xboxone")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(XBOX_CONSOLE_TARGET xboxone)
elseif(TARGET_TRIPLET STREQUAL "x64-xbox-xboxone-static")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(XBOX_CONSOLE_TARGET xboxone)
elseif(TARGET_TRIPLET STREQUAL "x64-xbox-scarlett-dynamic" OR TARGET_TRIPLET STREQUAL "x64-xbox-scarlett")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE dynamic)
    set(XBOX_CONSOLE_TARGET scarlett)
elseif(TARGET_TRIPLET STREQUAL "x64-xbox-scarlett-static")
    set(TARGET_TRIPLET_ARCH x64)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(XBOX_CONSOLE_TARGET scarlett)

elseif(TARGET_TRIPLET STREQUAL "wasm32-emscripten")
    # set(VCPKG_ENV_PASSTHROUGH_UNTRACKED EMSCRIPTEN_ROOT EMSDK PATH)
    set(TARGET_TRIPLET_ARCH wasm32)
    set(CRT_LINKAGE dynamic)
    set(LIBRARY_LINKAGE static)
    set(CMAKE_SYSTEM_NAME Emscripten)

    # end vcpkg-supported triplets

else()
    message(FATAL_ERROR "Triplet not defined (or found?)")
endif()

if(DEFINED TARGET_TRIPLET_ARCH)
    set(TARGET_TRIPLET_ARCH "${TARGET_TRIPLET_ARCH}" CACHE STRING "")
endif()
if(DEFINED CRT_LINKAGE)
    set(CRT_LINKAGE "${CRT_LINKAGE}" CACHE STRING "")
endif()
if(DEFINED LIBRARY_LINKAGE)
    set(LIBRARY_LINKAGE "${LIBRARY_LINKAGE}" CACHE STRING "")
endif()

if(DEFINED OSX_ARCHITECTURES)
    set(OSX_ARCHITECTURES "${OSX_ARCHITECTURES}" CACHE STRING "OSX Architectures available.")
    set(CMAKE_OSX_ARCHITECTURES "${OSX_ARCHITECTURES}")
endif()
if(DEFINED ANDROID_ABI)
    set(ANDROID_ABI "${ANDROID_ABI}" CACHE STRING "Android binary interface to use.")
    # set(CMAKE_ANDROID_API "${ANDROID_ABI}")
endif()
if(DEFINED ANDROID_ARM_NEON)
    set(ANDROID_ARM_NEON "${ANDROID_ARM_NEON}" CACHE BOOL "True if using Neon for arm-based android targets.")
    set(CMAKE_ANDROID_ARM_NEON "${ANDROID_ARM_NEON}" CACHE STRING "When :`Cross Compiling for Android` and ``CMAKE_ANDROID_ARCH_ABI`` is set to ``armeabi-v7a`` set ``CMAKE_ANDROID_ARM_NEON`` to ``ON`` to target ARM NEON devices.")
endif()
if(DEFINED ANDROID_ARM_MODE)
    set(ANDROID_ARM_MODE "${ANDROID_ARM_MODE}" CACHE STRING "Mode to use for arm-based android targets.")
    set(CMAKE_ANDROID_ARM_MODE "${ANDROID_ARM_MODE}" CACHE STRING "When :`Cross Compiling for Android` and ``CMAKE_ANDROID_ARCH_ABI`` is set to one of the ``armeabi`` architectures, set ``CMAKE_ANDROID_ARM_MODE`` to ``ON`` to target 32-bit ARM processors (``-marm``).")
endif()
if(DEFINED MAKEFILE_BUILD_TRIPLET)
    list(APPEND CMAKE_USER_MAKE_RULES_OVERRIDE "${MAKEFILE_BUILD_TRIPLET}")
endif()
if(XBOX_CONSOLE_TARGET STREQUAL "xboxone" OR XBOX_CONSOLE_TARGET STREQUAL "xboxone")
    set(XBOX_CONSOLE_TARGET "${XBOX_CONSOLE_TARGET}" CACHE STRING "Xbox console target. Can be 'xboxone' or 'scarlett'.")
endif()
if(TARGET_TRIPLET STREQUAL "wasm32-emscripten")
    # set(VCPKG_ENV_PASSTHROUGH_UNTRACKED EMSCRIPTEN_ROOT EMSDK PATH)

    if(NOT DEFINED ENV{EMSCRIPTEN_ROOT})
        find_path(EMSCRIPTEN_ROOT "emcc")
    else()
        set(EMSCRIPTEN_ROOT "$ENV{EMSCRIPTEN_ROOT}")
    endif()

    if(NOT EMSCRIPTEN_ROOT)
        if(NOT DEFINED ENV{EMSDK})
            message(FATAL_ERROR "The emcc compiler not found in PATH")
        endif()
        set(EMSCRIPTEN_ROOT "$ENV{EMSDK}/upstream/emscripten")
    endif()

    if(NOT EXISTS "${EMSCRIPTEN_ROOT}/cmake/Modules/Platform/Emscripten.cmake")
        message(FATAL_ERROR "Emscripten.cmake toolchain file not found")
    endif()
endif()





# set(TRIPLET_FILE "${TRIPLET_FILE}" CACHE FILEPATH "The triplet file." FORCE)
# if(TARGET_TRIPLET NOT STREQUAL "")
#     include("${TRIPLET_FILE}")
# else()
#     message(FATAL_ERROR "No triplet specified (or found?)")
# endif()

###################################################

#Helper variable to identify the Target system. TARGET_IS_<targetname>
if (NOT DEFINED CMAKE_SYSTEM_NAME OR CMAKE_SYSTEM_NAME STREQUAL "")
    set(TARGET_IS_WINDOWS ON)

    if(DEFINED XBOX_CONSOLE_TARGET AND NOT "${XBOX_CONSOLE_TARGET}" STREQUAL "")
        set(TARGET_IS_XBOX ON)
    endif()
elseif(CMAKE_SYSTEM_NAME STREQUAL "WindowsStore")
    set(TARGET_IS_WINDOWS ON)
    set(TARGET_IS_UWP ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(TARGET_IS_OSX ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(TARGET_IS_IOS ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(TARGET_IS_LINUX ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Android")
    set(TARGET_IS_ANDROID ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "FreeBSD")
    set(TARGET_IS_FREEBSD ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "OpenBSD")
    set(TARGET_IS_OPENBSD ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "MinGW")
    set(TARGET_IS_WINDOWS ON)
    set(TARGET_IS_MINGW ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
    set(TARGET_IS_EMSCRIPTEN ON)
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows") # Needed since this option isn't specified above...
    set(TARGET_IS_WINDOWS ON)
endif()

#Helper variables to identify the host system name
if (CMAKE_HOST_WIN32)
    set(HOST_IS_WINDOWS ON)
elseif (CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(HOST_IS_OSX ON)
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    set(HOST_IS_LINUX ON)
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "FreeBSD")
    set(HOST_IS_FREEBSD ON)
elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "OpenBSD")
    set(HOST_IS_OPENBSD ON)
endif()

set(CMAKE_HOST_SYSTEM_NAME "${CMAKE_HOST_SYSTEM_NAME}" CACHE STRING "Name of the OS CMake is running on.")

#Helper variable to identify the host path separator.
if(CMAKE_HOST_WIN32)
    set(HOST_PATH_SEPARATOR ";")
elseif(CMAKE_HOST_UNIX)
    set(HOST_PATH_SEPARATOR ":")
endif()

#Helper variables to identify executables on host/target
if(CMAKE_HOST_WIN32)
    set(HOST_EXECUTABLE_SUFFIX ".exe")
else()
    set(HOST_EXECUTABLE_SUFFIX "")
endif()
#set(CMAKE_EXECUTABLE_SUFFIX ${VCPKG_HOST_EXECUTABLE_SUFFIX}) not required by find_program

#Helper variables to identify bundles on host/target
if(HOST_IS_OSX)
    set(HOST_BUNDLE_SUFFIX ".app")
else()
    set(HOST_BUNDLE_SUFFIX "")
endif()

########################### Targets

if(TARGET_IS_WINDOWS)
    set(TARGET_EXECUTABLE_SUFFIX ".exe")
else()
    set(TARGET_EXECUTABLE_SUFFIX "")
endif()

if(TARGET_IS_OSX OR TARGET_IS_IOS)
    set(TARGET_BUNDLE_SUFFIX ".app")
else()
    set(TARGET_BUNDLE_SUFFIX "")
endif()

#Helper variables for libraries
if(TARGET_IS_MINGW)
    set(TARGET_STATIC_LIBRARY_SUFFIX ".a")
    set(TARGET_IMPORT_LIBRARY_SUFFIX ".dll.a")
    set(TARGET_SHARED_LIBRARY_SUFFIX ".dll")
    set(TARGET_STATIC_LIBRARY_PREFIX "lib")
    set(TARGET_SHARED_LIBRARY_PREFIX "lib")
    set(TARGET_IMPORT_LIBRARY_PREFIX "lib")
    set(FIND_LIBRARY_SUFFIXES ".dll" ".dll.a" ".a" ".lib")
    set(FIND_LIBRARY_PREFIXES "lib" "")
elseif(TARGET_IS_WINDOWS)
    set(TARGET_STATIC_LIBRARY_SUFFIX ".lib")
    set(TARGET_IMPORT_LIBRARY_SUFFIX ".lib")
    set(TARGET_SHARED_LIBRARY_SUFFIX ".dll")
    set(TARGET_IMPORT_LIBRARY_SUFFIX ".lib")
    set(TARGET_STATIC_LIBRARY_PREFIX "")
    set(TARGET_SHARED_LIBRARY_PREFIX "")
    set(TARGET_IMPORT_LIBRARY_PREFIX "")
    set(FIND_LIBRARY_SUFFIXES ".lib" ".dll") #This is a slight modification to CMakes value which does not include ".dll".
    set(FIND_LIBRARY_PREFIXES "" "lib") #This is a slight modification to CMakes value which does not include "lib".
elseif(TARGET_IS_OSX)
    set(TARGET_STATIC_LIBRARY_SUFFIX ".a")
    set(TARGET_IMPORT_LIBRARY_SUFFIX "")
    set(TARGET_SHARED_LIBRARY_SUFFIX ".dylib")
    set(TARGET_STATIC_LIBRARY_PREFIX "lib")
    set(TARGET_SHARED_LIBRARY_PREFIX "lib")
    set(FIND_LIBRARY_SUFFIXES ".tbd" ".dylib" ".so" ".a")
    set(FIND_LIBRARY_PREFIXES "lib" "")
else()
    set(TARGET_STATIC_LIBRARY_SUFFIX ".a")
    set(TARGET_IMPORT_LIBRARY_SUFFIX "")
    set(TARGET_SHARED_LIBRARY_SUFFIX ".so")
    set(TARGET_STATIC_LIBRARY_PREFIX "lib")
    set(TARGET_SHARED_LIBRARY_PREFIX "lib")
    set(FIND_LIBRARY_SUFFIXES ".so" ".a")
    set(FIND_LIBRARY_PREFIXES "lib" "")
endif()

set(TARGET_STATIC_LIBRARY_SUFFIX "${TARGET_STATIC_LIBRARY_SUFFIX}" CACHE STRING "The suffix for static libraries that you link to.")
set(TARGET_SHARED_LIBRARY_SUFFIX "${TARGET_SHARED_LIBRARY_SUFFIX}" CACHE STRING "The suffix for shared libraries that you link to.")
set(TARGET_IMPORT_LIBRARY_SUFFIX "${TARGET_IMPORT_LIBRARY_SUFFIX}" CACHE STRING "The suffix for import libraries that you link to.")
set(TARGET_STATIC_LIBRARY_PREFIX "${TARGET_STATIC_LIBRARY_PREFIX}" CACHE STRING "The prefix for static libraries that you link to.")
set(TARGET_SHARED_LIBRARY_PREFIX "${TARGET_SHARED_LIBRARY_PREFIX}" CACHE STRING "The prefix for shared libraries that you link to.")
set(TARGET_IMPORT_LIBRARY_PREFIX "${TARGET_IMPORT_LIBRARY_PREFIX}" CACHE STRING "The prefix for import libraries that you link to.")

set(FIND_LIBRARY_SUFFIXES "${FIND_LIBRARY_SUFFIXES}" CACHE STRING "Suffixes to append when looking for libraries.") # Required by find_library
set(FIND_LIBRARY_PREFIXES "${FIND_LIBRARY_PREFIXES}" CACHE STRING "Prefixes to prepend when looking for libraries.") # Required by find_library


#Setting these variables allows find_library to work in script mode and thus in portfiles!
#This allows us scale down on hardcoded target dependent paths in portfiles
set(CMAKE_STATIC_LIBRARY_SUFFIX "${TARGET_STATIC_LIBRARY_SUFFIX}")
set(CMAKE_SHARED_LIBRARY_SUFFIX "${TARGET_SHARED_LIBRARY_SUFFIX}")
set(CMAKE_IMPORT_LIBRARY_SUFFIX "${TARGET_IMPORT_LIBRARY_SUFFIX}")
set(CMAKE_STATIC_LIBRARY_PREFIX "${TARGET_STATIC_LIBRARY_PREFIX}")
set(CMAKE_SHARED_LIBRARY_PREFIX "${TARGET_SHARED_LIBRARY_PREFIX}")
set(CMAKE_IMPORT_LIBRARY_PREFIX "${TARGET_IMPORT_LIBRARY_PREFIX}")

set(CMAKE_FIND_LIBRARY_SUFFIXES "${FIND_LIBRARY_SUFFIXES}" CACHE INTERNAL "Suffixes to append when looking for libraries.") # Required by find_library
set(CMAKE_FIND_LIBRARY_PREFIXES "${FIND_LIBRARY_PREFIXES}" CACHE INTERNAL "Prefixes to prepend when looking for libraries.") # Required by find_library

# Append platform libraries to SYSTEM_LIBRARIES
# The variables are just appended to permit to custom triplets define the variable

# Platforms with libdl
if(TARGET_IS_LINUX OR TARGET_IS_ANDROID OR TARGET_IS_OSX)
    list(APPEND SYSTEM_LIBRARIES dl)
endif()

# Platforms with libm
if(TARGET_IS_LINUX OR TARGET_IS_ANDROID OR TARGET_IS_FREEBSD OR TARGET_IS_OPENBSD OR TARGET_IS_OSX OR TARGET_IS_MINGW)
    list(APPEND SYSTEM_LIBRARIES m)
endif()

# Platforms with pthread
if(TARGET_IS_LINUX OR TARGET_IS_ANDROID OR TARGET_IS_OSX OR TARGET_IS_FREEBSD OR TARGET_IS_OPENBSD OR TARGET_IS_MINGW)
    list(APPEND SYSTEM_LIBRARIES pthread)
endif()

# Platforms with libstdc++
if(TARGET_IS_LINUX OR TARGET_IS_ANDROID OR TARGET_IS_FREEBSD OR TARGET_IS_OPENBSD OR TARGET_IS_MINGW)
    list(APPEND SYSTEM_LIBRARIES [[stdc\+\+]])
endif()

# Platforms with libc++
if(TARGET_IS_OSX)
    list(APPEND SYSTEM_LIBRARIES [[c\+\+]])
endif()

# Platforms with librt
if(TARGET_IS_LINUX OR TARGET_IS_ANDROID OR TARGET_IS_OSX OR TARGET_IS_FREEBSD OR TARGET_IS_MINGW)
    list(APPEND SYSTEM_LIBRARIES rt)
endif()

# Platforms with GCC libs
if(TARGET_IS_LINUX OR TARGET_IS_ANDROID OR TARGET_IS_OSX OR TARGET_IS_FREEBSD OR TARGET_IS_OPENBSD OR TARGET_IS_MINGW)
    list(APPEND SYSTEM_LIBRARIES gcc)
    list(APPEND SYSTEM_LIBRARIES gcc_s)
endif()

# Platforms with system iconv
if(TARGET_IS_OSX)
    list(APPEND SYSTEM_LIBRARIES iconv)
endif()

# Windows system libs
if(TARGET_IS_WINDOWS)
    list(APPEND SYSTEM_LIBRARIES advapi32)
    list(APPEND SYSTEM_LIBRARIES bcrypt)
    list(APPEND SYSTEM_LIBRARIES dinput8)
    list(APPEND SYSTEM_LIBRARIES gdi32)
    list(APPEND SYSTEM_LIBRARIES imm32)
    list(APPEND SYSTEM_LIBRARIES oleaut32)
    list(APPEND SYSTEM_LIBRARIES ole32)
    list(APPEND SYSTEM_LIBRARIES psapi)
    list(APPEND SYSTEM_LIBRARIES secur32)
    list(APPEND SYSTEM_LIBRARIES setupapi)
    list(APPEND SYSTEM_LIBRARIES shell32)
    list(APPEND SYSTEM_LIBRARIES shlwapi)
    list(APPEND SYSTEM_LIBRARIES strmiids)
    list(APPEND SYSTEM_LIBRARIES user32)
    list(APPEND SYSTEM_LIBRARIES uuid)
    list(APPEND SYSTEM_LIBRARIES version)
    list(APPEND SYSTEM_LIBRARIES vfw32)
    list(APPEND SYSTEM_LIBRARIES winmm)
    list(APPEND SYSTEM_LIBRARIES wsock32)
    list(APPEND SYSTEM_LIBRARIES Ws2_32)
    list(APPEND SYSTEM_LIBRARIES wldap32)
    list(APPEND SYSTEM_LIBRARIES crypt32)
endif()


if(USE_TOOLCHAIN)
    cmake_policy(POP)
    message(WARNING "Toolchain returning unsually at line ${CMAKE_CURRENT_LIST_LINE}")
    return()
endif()



#############

string(COMPARE NOTEQUAL "${TARGET_TRIPLET}" "${HOST_TRIPLET}" CROSSCOMPILING)
set(CMAKE_CROSSCOMPILING "${CROSSCOMPILING}" CACHE STRING "")

cmake_policy(POP)

# Any policies applied to the below macros and functions appear to leak into consumers

function(add_executable)
    function_arguments(ARGS)
    _add_executable(${ARGS})
    set(target_name "${ARGV0}")

    list(FIND ARGV "IMPORTED" IMPORTED_IDX)
    list(FIND ARGV "ALIAS" ALIAS_IDX)
    list(FIND ARGV "MACOSX_BUNDLE" MACOSX_BUNDLE_IDX)
    if(IMPORTED_IDX EQUAL "-1" AND ALIAS_IDX EQUAL "-1")
        if(APPLOCAL_DEPS)
            if(TARGET_TRIPLET_PLATFORM MATCHES "windows|uwp|xbox")
                set_powershell_path()
                set(EXTRA_OPTIONS "")
                if(APPLOCAL_DEPS_SERIALIZED)
                    set(EXTRA_OPTIONS USES_TERMINAL)
                endif()
                add_custom_command(TARGET "${target_name}" POST_BUILD
                    COMMAND "${POWERSHELL_PATH}" -noprofile -executionpolicy Bypass -file "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/msbuild/applocal.ps1"
                        -targetBinary "$<TARGET_FILE:${target_name}>"
                        -installedDir "${CMAKE_INSTALL_PREFIX}/${TARGET_TRIPLET}$<$<CONFIG:Debug>:/debug>/bin"
                        -OutVariable out
                    VERBATIM
                    ${EXTRA_OPTIONS}
                )
            elseif(TARGET_TRIPLET_PLATFORM MATCHES "osx")
                if(NOT MACOSX_BUNDLE_IDX EQUAL "-1")
                    find_package(Python COMPONENTS Interpreter)
                    add_custom_command(TARGET "${target_name}" POST_BUILD
                        COMMAND "${Python_EXECUTABLE}" "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/osx/applocal.py"
                            "$<TARGET_FILE:${target_name}>"
                            "${CMAKE_INSTALL_PREFIX}/${TARGET_TRIPLET}$<$<CONFIG:Debug>:/debug>"
                        VERBATIM
                    )
                endif()
            endif()
        endif()
        set_target_properties("${target_name}" PROPERTIES VS_USER_PROPS do_not_import_user.props)
        set_target_properties("${target_name}" PROPERTIES VS_GLOBAL_VcpkgEnabled false)
    endif()
endfunction()

function(add_library)
    function_arguments(ARGS)
    _add_library(${ARGS})
    set(target_name "${ARGV0}")

    list(FIND ARGS "IMPORTED" IMPORTED_IDX)
    list(FIND ARGS "INTERFACE" INTERFACE_IDX)
    list(FIND ARGS "ALIAS" ALIAS_IDX)
    if(IMPORTED_IDX EQUAL "-1" AND INTERFACE_IDX EQUAL "-1" AND ALIAS_IDX EQUAL "-1")
        get_target_property(IS_LIBRARY_SHARED "${target_name}" TYPE)
        if(APPLOCAL_DEPS AND TARGET_TRIPLET_PLATFORM MATCHES "windows|uwp|xbox" AND (IS_LIBRARY_SHARED STREQUAL "SHARED_LIBRARY" OR IS_LIBRARY_SHARED STREQUAL "MODULE_LIBRARY"))
            set_powershell_path()
            add_custom_command(TARGET "${target_name}" POST_BUILD
                COMMAND "${POWERSHELL_PATH}" -noprofile -executionpolicy Bypass -file "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/msbuild/applocal.ps1"
                    -targetBinary "$<TARGET_FILE:${target_name}>"
                    -installedDir "${CMAKE_INSTALL_PREFIX}/${TARGET_TRIPLET}$<$<CONFIG:Debug>:/debug>/bin"
                    -OutVariable out
                    VERBATIM
            )
        endif()
        set_target_properties("${target_name}" PROPERTIES VS_USER_PROPS do_not_import_user.props)
        set_target_properties("${target_name}" PROPERTIES VS_GLOBAL_VcpkgEnabled false)
    endif()
endfunction()

cmake_policy(PUSH)
cmake_policy(VERSION 3.7.2)

# Don't change this var, it prevents cyclical includes :)
set(USE_TOOLCHAIN ON)

# Propogate these values to try-compile configurations so the triplet and toolchain load
if(NOT TOOLCHAIN_IN_TRY_COMPILE)
    list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
        TARGET_TRIPLET
        TARGET_TRIPLET_ARCH
        TARGET_TRIPLET_PLATFORM
        #APPLOCAL_DEPS - we can test for these individually below instead...
        #VCPKG_CHAINLOAD_TOOLCHAIN_FILE
        #Z_VCPKG_ROOT_DIR
    )
    if(DEFINED APPLOCAL_DEPS)
        list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES
            APPLOCAL_DEPS
        )
    endif()
endif()

if(CONFIG_HAS_FATAL_ERROR)
    message(FATAL_ERROR "${CONFIG_FATAL_ERROR}")
endif()

cmake_policy(POP)

message(STATUS "Toolchain file loaded.")

set(BUILD_INFO_FILE_PATH ${CMAKE_CURRENT_BINARY_DIR}/BUILD_INFO)
file(WRITE  ${BUILD_INFO_FILE_PATH} "CRTLinkage: ${CRT_LINKAGE}\n")
file(APPEND ${BUILD_INFO_FILE_PATH} "LibraryLinkage: ${LIBRARY_LINKAGE}\n")

if (DEFINED POLICY_DLLS_WITHOUT_LIBS)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyDLLsWithoutLIBs: ${POLICY_DLLS_WITHOUT_LIBS}\n")
endif()
if (DEFINED POLICY_DLLS_WITHOUT_EXPORTS)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyDLLsWithoutExports: ${POLICY_DLLS_WITHOUT_EXPORTS}\n")
endif()
if (DEFINED POLICY_DLLS_IN_STATIC_LIBRARY)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyDLLsInStaticLibrary: ${POLICY_DLLS_IN_STATIC_LIBRARY}\n")
endif()
if (DEFINED POLICY_MISMATCHED_NUMBER_OF_BINARIES)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyMismatchedNumberOfBinaries: ${POLICY_MISMATCHED_NUMBER_OF_BINARIES}\n")
endif()
if (DEFINED POLICY_EMPTY_PACKAGE)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyEmptyPackage: ${POLICY_EMPTY_PACKAGE}\n")
endif()
if (DEFINED POLICY_ONLY_RELEASE_CRT)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyOnlyReleaseCRT: ${POLICY_ONLY_RELEASE_CRT}\n")
endif()
if (DEFINED POLICY_ALLOW_OBSOLETE_MSVCRT)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyAllowObsoleteMsvcrt: ${POLICY_ALLOW_OBSOLETE_MSVCRT}\n")
endif()
if (DEFINED POLICY_EMPTY_INCLUDE_FOLDER)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyEmptyIncludeFolder: ${POLICY_EMPTY_INCLUDE_FOLDER}\n")
endif()
if (DEFINED POLICY_ALLOW_RESTRICTED_HEADERS)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyAllowRestrictedHeaders: ${POLICY_ALLOW_RESTRICTED_HEADERS}\n")
endif()
if (DEFINED POLICY_SKIP_DUMPBIN_CHECKS)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicySkipDumpbinChecks: ${POLICY_SKIP_DUMPBIN_CHECKS}\n")
endif()
if (DEFINED POLICY_SKIP_ARCHITECTURE_CHECK)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicySkipArchitectureCheck: ${POLICY_SKIP_ARCHITECTURE_CHECK}\n")
endif()
if (DEFINED POLICY_CMAKE_HELPER_PORT)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicyCmakeHelperPort: ${POLICY_CMAKE_HELPER_PORT}\n")
endif()
if (DEFINED POLICY_SKIP_ABSOLUTE_PATHS_CHECK)
    file(APPEND ${BUILD_INFO_FILE_PATH} "PolicySkipAbsolutePathsCheck: ${POLICY_SKIP_ABSOLUTE_PATHS_CHECK}\n")
endif()
if (DEFINED HEAD_VERSION)
    file(APPEND ${BUILD_INFO_FILE_PATH} "Version: ${HEAD_VERSION}\n")
endif()


###################

