cmake_minimum_required(VERSION 3.21)

project(AnimindQtHost LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Qt 6
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick OpenGL QuickControls2 QuickDialogs2 Network)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# MPV: normalize to absolute path so the linker always finds the .lib
get_filename_component(MPV_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv" ABSOLUTE)
get_filename_component(MPV_INCLUDE "${CMAKE_CURRENT_SOURCE_DIR}/include" ABSOLUTE)

add_executable(AnimindQtHost
    src/main.cpp
    src/auth_manager.cpp
    src/auth_manager.h
    src/mpv_item.cpp
    src/mpv_item.h
)

# Bake the Qt QML path into the binary so the engine can always find modules
get_filename_component(QT_QML_DIR "${Qt6_DIR}/../../../qml" ABSOLUTE)
target_compile_definitions(AnimindQtHost PRIVATE
    QT_QML_IMPORT_PATH="${QT_QML_DIR}"
)

target_include_directories(AnimindQtHost PRIVATE "${MPV_INCLUDE}")

target_link_directories(AnimindQtHost PRIVATE "${MPV_ROOT}/win-x64")

target_link_libraries(AnimindQtHost PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::OpenGL
    Qt6::QuickControls2
    Qt6::QuickDialogs2
    Qt6::Network
    "${MPV_ROOT}/win-x64/libmpv-2-proper.lib"
)

if(WIN32)
    set_target_properties(AnimindQtHost PROPERTIES WIN32_EXECUTABLE TRUE)
endif()

# --------------------------------------------------------------------------
# Post-build: copy assets next to the exe
# --------------------------------------------------------------------------

# Copy libmpv DLL
add_custom_command(TARGET AnimindQtHost POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${MPV_ROOT}/win-x64/libmpv-2.dll"
        "$<TARGET_FILE_DIR:AnimindQtHost>"
    COMMENT "Copying libmpv-2.dll..."
)

# Copy the qml/ folder so the exe can find main.qml at runtime
add_custom_command(TARGET AnimindQtHost POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/qml"
        "$<TARGET_FILE_DIR:AnimindQtHost>/qml"
    COMMENT "Copying qml/ assets..."
)

# Use windeployqt to copy required Qt DLLs / plugins
find_program(WINDEPLOYQT_EXE windeployqt
    PATHS "${Qt6_DIR}/../../../bin"
)
if(WINDEPLOYQT_EXE)
    add_custom_command(TARGET AnimindQtHost POST_BUILD
        COMMAND "${WINDEPLOYQT_EXE}"
            --no-translations
            --no-compiler-runtime
            --qmldir "${CMAKE_CURRENT_SOURCE_DIR}/qml"
            "$<TARGET_FILE_DIR:AnimindQtHost>/AnimindQtHost.exe"
        COMMENT "Running windeployqt..."
    )
endif()
