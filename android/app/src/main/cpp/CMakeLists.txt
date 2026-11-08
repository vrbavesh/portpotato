cmake_minimum_required(VERSION 3.22.1)
project(portpotato_llama LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)

set(LLAMA_SRC "${CMAKE_CURRENT_LIST_DIR}/../../../../../third_party/llama.cpp")
add_subdirectory("${LLAMA_SRC}" "${CMAKE_CURRENT_BINARY_DIR}/llama")

add_library(ai-chat SHARED
    "${LLAMA_SRC}/examples/llama.android/lib/src/main/cpp/ai_chat.cpp")
target_include_directories(ai-chat PRIVATE
    "${LLAMA_SRC}/examples/llama.android/lib/src/main/cpp"
    "${LLAMA_SRC}/common"
    "${LLAMA_SRC}/include"
    "${LLAMA_SRC}/ggml/include")
target_link_libraries(ai-chat PRIVATE llama llama-common android log)
