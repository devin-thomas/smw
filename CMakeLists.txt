cmake_minimum_required(VERSION 3.25)

project(SMWIOS LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(FATAL_ERROR "This CMake project is the iOS/iPadOS shell. Configure with -DCMAKE_SYSTEM_NAME=iOS.")
endif()

include(FetchContent)

set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)

FetchContent_Declare(
  SDL2
  GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
  GIT_TAG release-2.32.10
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(SDL2)

file(GLOB SMW_CORE_SOURCES CONFIGURE_DEPENDS
  "${CMAKE_CURRENT_SOURCE_DIR}/src/*.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/snes/*.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/smb1/*.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/smbll/*.c"
)

list(REMOVE_ITEM SMW_CORE_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/src/opengl.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/glsl_shader.c"
)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/smw_assets.dat")
  message(FATAL_ERROR
    "smw_assets.dat is required for a runnable local build. Generate it from your legally owned ROM with 'python3 assets/restool.py'.")
endif()

set(SMW_RESOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/smw.ini"
  "${CMAKE_CURRENT_SOURCE_DIR}/smw_assets.dat"
  "${CMAKE_CURRENT_SOURCE_DIR}/ios/LaunchScreen.storyboard"
)

add_executable(SuperMarioWorld MACOSX_BUNDLE
  ${SMW_CORE_SOURCES}
  "${CMAKE_CURRENT_SOURCE_DIR}/src/platform/ios/ios_impl.mm"
  ${SMW_RESOURCES}
)

set_source_files_properties(${SMW_RESOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

target_compile_features(SuperMarioWorld PRIVATE c_std_11 cxx_std_17)
target_compile_definitions(SuperMarioWorld PRIVATE
  __IOS__=1
  SYSTEM_VOLUME_MIXER_AVAILABLE=0
)
target_include_directories(SuperMarioWorld PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
)
target_compile_options(SuperMarioWorld PRIVATE
  $<$<COMPILE_LANGUAGE:C>:-Wno-tautological-constant-out-of-range-compare>
)

target_link_libraries(SuperMarioWorld PRIVATE
  SDL2::SDL2-static
  SDL2::SDL2main
  "-framework AVFAudio"
  "-framework UIKit"
)

set_target_properties(SuperMarioWorld PROPERTIES
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist.in"
  XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
  XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
  XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION 1
  XCODE_ATTRIBUTE_DEVELOPMENT_TEAM ""
  XCODE_ATTRIBUTE_ENABLE_BITCODE NO
  XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO
  XCODE_ATTRIBUTE_MARKETING_VERSION 0.1
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.local.smw.ios"
  XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)
