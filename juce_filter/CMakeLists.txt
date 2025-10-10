cmake_minimum_required(VERSION 3.15)
project(AudioFilter VERSION 1.0.0)

set(CMAKE_CXX_STANDARD 17)

# Add JUCE and disable GUI modules
set(JUCE_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
set(JUCE_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory(/home/home/JUCE ${CMAKE_CURRENT_BINARY_DIR}/JUCE)

# Create the CLI application
juce_add_console_app(AudioFilter
    PRODUCT_NAME "AudioFilter"
    NEEDS_WEB_BROWSER FALSE
    NEEDS_CURL FALSE)

target_sources(AudioFilter PRIVATE main.cpp)

target_compile_definitions(AudioFilter PRIVATE
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_DISABLE_JUCE_VERSION_PRINTING=1
    JUCE_APPLICATION_NAME_STRING="AudioFilter"
    JUCE_APPLICATION_VERSION_STRING="1.0.0")

target_link_libraries(AudioFilter PRIVATE
    juce::juce_audio_basics
    juce::juce_audio_formats
    juce::juce_dsp
    juce::juce_events
    juce::juce_core)
