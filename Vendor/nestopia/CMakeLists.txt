#
# Vendored Nestopia（NES / Famicom）—— 只编「核心本体 + C++ API 层」，给出一个静态库。
#
# 刻意不编上游的 libretro 前端（libretro/libretro.cpp 与 libretro/libretro-common）：
# 那是给 RetroArch 用的动态核心，而我们按 iOS 的限制一律静态链接、由宿主自己当「前端」
# （见 Sources/Core/GSNestopiaCore.mm 与 Sources/Core/GSEmulator.h 的说明）。
#
# 上游构建参考：libretro/Makefile.common 列出了核心源文件；本文件用 GLOB 等价地取
# source/core/ 下全部 .cpp（含 api/、board/、input/、vssystem/ 四个子目录）。
#
cmake_minimum_required(VERSION 3.15)

project(nestopia CXX)

set(NESTOPIA_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/source/core")

file(GLOB_RECURSE NESTOPIA_SOURCES CONFIGURE_DEPENDS "${NESTOPIA_CORE_DIR}/*.cpp")

add_library(nestopia STATIC ${NESTOPIA_SOURCES})

target_include_directories(nestopia PUBLIC
	"${NESTOPIA_CORE_DIR}"
	"${NESTOPIA_CORE_DIR}/api")

# NST_NO_ZLIB：上游 libretro 构建同样带这个宏（libretro/Makefile 的 DEFINES）。
# 定义它之后 NstZlib.cpp 不再 #include "zlib.h"（iOS 不保证提供 zlib 头文件），
# 压缩相关的 API 换成内置的「不压缩」实现。
target_compile_definitions(nestopia PRIVATE NST_NO_ZLIB)

# 上游代码是 2003-2008 年写的 C++98 风格：用 gnu++14 而不是 Xcode 工程里默认的
# gnu++17（C++17 移除了 register 等写法，老代码不一定还能编）。
set_target_properties(nestopia PROPERTIES
	CXX_STANDARD 14
	CXX_STANDARD_REQUIRED ON
	CXX_EXTENSIONS ON)

# 核心自己会抛 Result 异常，必须保留异常支持。
target_compile_options(nestopia PRIVATE -fexceptions)
