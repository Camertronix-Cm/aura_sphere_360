cmake_minimum_required(VERSION 3.10)

project(webrtc_pixel_stream)

# Set C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add source files
add_library(
    webrtc_pixel_stream
    SHARED
    webrtc_pixel_stream.cpp
)

# Link against Android log library
find_library(log-lib log)
target_link_libraries(webrtc_pixel_stream ${log-lib})

# Optional: Enable NEON optimizations on ARMv7 (arm64 has it by default)
if(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(webrtc_pixel_stream PRIVATE -mfpu=neon)
endif()
