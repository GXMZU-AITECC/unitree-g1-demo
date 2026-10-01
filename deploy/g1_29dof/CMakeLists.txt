cmake_minimum_required(VERSION 3.12)
project(g1_29dof_controller)

set(CMAKE_CXX_STANDARD 17)

find_package(Boost REQUIRED COMPONENTS program_options)
find_package(yaml-cpp REQUIRED)

# ONNX Runtime path — use env var if set, otherwise fall back to bundled thirdparty
if(DEFINED ENV{ONNXRUNTIME_ROOT})
    set(ONNXRUNTIME_ROOT "$ENV{ONNXRUNTIME_ROOT}")
else()
    set(ONNXRUNTIME_ROOT "${PROJECT_SOURCE_DIR}/../../thirdparty/onnxruntime-linux-x64-1.22.0")
    message(STATUS "ONNXRUNTIME_ROOT not set, using default: ${ONNXRUNTIME_ROOT}")
endif()

# 先确认 ONNX Runtime 真的在那儿。以前不在也照样 configure 成功，直到编译才报
# "onnxruntime_cxx_api.h: No such file or directory" —— 新手怎么也联不上是这一步的问题。
if(NOT EXISTS "${ONNXRUNTIME_ROOT}/include/onnxruntime_cxx_api.h")
    message(FATAL_ERROR
        "\n找不到 ONNX Runtime 头文件: ${ONNXRUNTIME_ROOT}/include/onnxruntime_cxx_api.h"
        "\n  当前 ONNXRUNTIME_ROOT = '$ENV{ONNXRUNTIME_ROOT}'（空 = 用上面的默认路径）"
        "\n  1) 还没装过:  cd ~/g1-rl-deploy && bash install_onnxruntime.sh"
        "\n  2) 装过但环境变量丢了（重开一个 SSH 会话就会丢）:"
        "\n       export ONNXRUNTIME_ROOT=~/g1-rl-deploy/thirdparty/onnxruntime-linux-x64-1.22.0"
        "\n       rm -f CMakeCache.txt && cmake .. -DCMAKE_BUILD_TYPE=Release"
        "\n  机器人不能联网时怎么手动装：见 5_deployment/5.8_troubleshooting.md")
endif()
if(NOT EXISTS "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so.1.22.0")
    message(FATAL_ERROR
        "\n找不到 ONNX Runtime 运行库: ${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so.1.22.0"
        "\n  头文件在、库不在 = 解压不完整或架构不对（本脚本装的是 linux-x64）。"
        "\n  重新跑 deploy/install_onnxruntime.sh，或用 ONNXRUNTIME_ROOT 指到一个完整的解压目录。")
endif()

include_directories(
  /usr/include/eigen3
  /usr/local/include/ddscxx # dds
  /usr/local/include/iceoryx/v2.0.2 # dds
  include
  ${ONNXRUNTIME_ROOT}/include
  ${PROJECT_SOURCE_DIR}/../../include/
)

link_libraries(
  unitree_sdk2 ddsc ddscxx rt pthread # dds
  libboost_program_options.a libyaml-cpp.a fmt
  ${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so.1.22.0
)

file(GLOB_RECURSE ADD_SRC_LIST
  ${PROJECT_SOURCE_DIR}/src/*.cpp
)

add_library(${PROJECT_NAME}_lib ${ADD_SRC_LIST})
link_libraries(${PROJECT_NAME}_lib)

add_executable(g1_ctrl main.cpp)
