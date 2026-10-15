#!/usr/bin/env bash
#
# build_cores.sh —— 把模拟器核心交叉编译成静态库，供 Xcode 链接。
#
# 为什么是静态库而不是动态库：
#   iOS 15 + A12 起系统封禁了 dynamic-codesigning / com.apple.private.cs.debugger，
#   运行时 dlopen 一个未签名的 core dylib 会被直接拒（RetroArch 那种「外挂 core」的做法
#   在 TrollStore 上也不成立）。所以核心一律静态链接进主二进制。
#
# 当前接入的核心：
#   mGBA     —— GBA / GB / GBC（Vendor/mgba，MPL-2.0）
#   Nestopia —— NES / Famicom（Vendor/nestopia，GPL-3.0）
# 尚无源码 / 尚未接入的核心（Snes9x、melonDS、Azahar、Dolphin、Cemu 等）只留空壳库，
# 由 GSBuiltCores.h 里的开关如实标成 0。
#
# 产物（每个平台一份，互不污染）：
#   build/cores/<PLATFORM>/lib<核心名>.a   —— 静态库（编译失败时是空壳，保证链接不报错）
#   build/cores/<PLATFORM>/GSBuiltCores.h  —— 编译期开关，告诉源码哪个核心真的进来了
#
# 编译失败不会让 Xcode 构建失败：会给对应核心写一个空壳库 + GS_HAVE_* 0，
# 于是 App 照常构建，只是如实显示「核心尚未接入」。
#
# 用法：
#   Scripts/build_cores.sh              # 用 $PLATFORM_NAME（Xcode 预构建脚本里就是这样调的）
#   Scripts/build_cores.sh iphoneos     # 手动指定平台
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${1:-${PLATFORM_NAME:-iphoneos}}"

OUT_DIR="$ROOT/build/cores/$PLATFORM"
HEADER="$OUT_DIR/GSBuiltCores.h"

MGBA_DIR="$ROOT/Vendor/mgba"
NESTOPIA_DIR="$ROOT/Vendor/nestopia"

mkdir -p "$OUT_DIR"

# 各核心「这次是否真的编出来了」，最后写进 GSBuiltCores.h
have_mgba=0
have_nestopia=0
have_snes9x=0
summary=""

log() { printf '[build_cores] %s\n' "$*"; }

# 造一个空壳静态库，让 -l<核心名> 一定能找到文件（没核心时不会有符号被引用）。
# 注意两点：
#  1) 空壳里必须真的放一个「目标架构」的 .o，否则链接器会报
#     "built for ... which is not the architecture being linked"；
#  2) 每个核心的空壳用**不同的**符号名。多个空壳库一起链接时，符号重名会直接
#     "duplicate symbol"，而不同名的空壳永远不会被引用，链接器会整档忽略。
make_stub_library() {
	local name="$1"
	local lib="$OUT_DIR/lib${name}.a"
	local tmpdir stub_obj
	tmpdir="$(mktemp -d)"
	cat > "$tmpdir/gs_stub.c" <<STUB
/* 空壳：本平台没有接入 ${name} 核心（见 GSBuiltCores.h） */
int gs_cores_stub_${name}(void) { return 0; }
STUB

	if [ "$PLATFORM" = "iphoneos" ]; then
		xcrun --sdk iphoneos clang -arch arm64 -target arm64-apple-ios16.0 \
			-c "$tmpdir/gs_stub.c" -o "$tmpdir/gs_stub.o" > "$tmpdir/cc.log" 2>&1
	else
		# 桌面 / 模拟器：编成 arm64 + x86_64 的通用库。
		# 只编主机架构的话，在另一种架构的构建机上会被 ld 直接整档忽略
		# （ld: warning: ignoring file ... required architecture 'x86_64'）。
		clang -arch arm64 -c "$tmpdir/gs_stub.c" -o "$tmpdir/gs_stub_arm64.o" > "$tmpdir/cc.log" 2>&1 \
			&& clang -arch x86_64 -c "$tmpdir/gs_stub.c" -o "$tmpdir/gs_stub_x86_64.o" >> "$tmpdir/cc.log" 2>&1 \
			&& lipo -create "$tmpdir/gs_stub_arm64.o" "$tmpdir/gs_stub_x86_64.o" \
				-output "$tmpdir/gs_stub.o" >> "$tmpdir/cc.log" 2>&1
	fi
	stub_obj="$tmpdir/gs_stub.o"

	if [ -f "$stub_obj" ]; then
		rm -f "$lib"
		if xcrun ar rcs "$lib" "$stub_obj" 2>/dev/null || ar rcs "$lib" "$stub_obj" 2>/dev/null; then
			log "生成空壳静态库 ${lib}"
		else
			log "警告：无法生成空壳静态库 ${lib}（-l${name} 可能找不到文件）"
		fi
	else
		log "警告：空壳目标文件编译失败，见 ${tmpdir}/cc.log"
	fi
	rm -rf "$tmpdir"
}

write_header() {
	cat > "$HEADER" <<EOF
// 由 Scripts/build_cores.sh 自动生成，请勿手改。
#ifndef GS_BUILT_CORES_H
#define GS_BUILT_CORES_H

// 1 = 对应核心已真正编进主二进制（0 = 空壳，宿主会如实提示「核心尚未接入」）
#define GS_HAVE_MGBA $have_mgba
#define GS_HAVE_NESTOPIA $have_nestopia
#define GS_HAVE_SNES9X $have_snes9x

#define GS_CORES_PLATFORM "$PLATFORM"
#define GS_CORES_NOTE "$summary"

#endif
EOF
	log "写出 ${HEADER}（mGBA=${have_mgba} Nestopia=${have_nestopia} Snes9x=${have_snes9x}）"
}

# 收尾：没编出来的核心补空壳库，然后写编译期开关头。成功编出来的核心不动（不覆盖真库）。
finalize() {
	[ "$have_mgba" -eq 1 ] || make_stub_library mgba
	[ "$have_nestopia" -eq 1 ] || make_stub_library nestopia
	[ "$have_snes9x" -eq 1 ] || make_stub_library snes9x
	write_header
}

# 一个核心都没编（平台/工具链不满足）时的统一收尾
finish_without_cores() {
	have_mgba=0
	have_nestopia=0
	have_snes9x=0
	summary="$1"
	finalize
	exit 0
}

# 交叉编译一个 cmake 工程形态的核心。
# 用法：build_cmake_core <核心名> <源码目录> <cmake 目标名> [额外的 -D 参数...]
# 成功返回 0 并把产物放到 $OUT_DIR/lib<核心名>.a；失败返回 1，日志留在
# $OUT_DIR/<核心名>-configure.log 与 <核心名>-build.log。
#
# 与 mGBA 相同的两个交叉编译要点（用 cmake 的 iOS 交叉编译规则，不依赖 Xcode 工程）：
#   CMAKE_SYSTEM_NAME=iOS + CMAKE_OSX_SYSROOT/ARCHITECTURES/DEPLOYMENT_TARGET
#   CMAKE_C_COMPILER / CMAKE_CXX_COMPILER 显式指向 SDK 里的 clang（不指的话 cmake
#   会挑到宿主 /usr/bin/c++，编出来的库是 macOS 架构，链接期直接被忽略）
#   CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY —— 只编译不链接地试探编译器，
#   交叉编译时不会有「链接不到 SDK 里的库」这类噪音失败。
build_cmake_core() {
	local name="$1"
	local src_dir="$2"
	local target="$3"
	shift 3

	local build_dir="$OUT_DIR/${name}-build"
	local configure_log="$OUT_DIR/${name}-configure.log"
	local build_log="$OUT_DIR/${name}-build.log"
	local built

	cmake -S "$src_dir" -B "$build_dir" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT="$SDK_NAME" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
		-DCMAKE_C_COMPILER="$CC" \
		-DCMAKE_CXX_COMPILER="$CXX" \
		-DCMAKE_C_COMPILER_WORKS=1 \
		-DCMAKE_CXX_COMPILER_WORKS=1 \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		"$@" > "$configure_log" 2>&1
	if [ $? -ne 0 ]; then
		log "${name} 的 cmake 配置失败，详情见 ${configure_log}"
		return 1
	fi

	log "开始编译 lib${name}.a（日志：${build_log}）"
	cmake --build "$build_dir" --target "$target" --parallel 4 > "$build_log" 2>&1
	if [ $? -ne 0 ]; then
		log "${name} 编译失败，详情见 ${build_log}"
		return 1
	fi

	built="$(find "$build_dir" -name "lib${name}.a" -type f 2>/dev/null | head -n 1)"
	if [ -z "$built" ]; then
		log "编译成功但没找到 lib${name}.a，详情见 ${build_log}"
		return 1
	fi

	cp "$built" "$OUT_DIR/lib${name}.a"
	log "完成：${OUT_DIR}/lib${name}.a（$(du -h "$OUT_DIR/lib${name}.a" | cut -f1)）"
	return 0
}

# ---------------------------------------------------------------- macOS：不接核心
# 桌面端保持纯 URL 模式：模拟器相关 UI 在 Swift 侧是 #if os(iOS) 门禁的，
# macOS 不编译也不链接任何核心，省掉一整条交叉编译风险。
if [ "$PLATFORM" = "macosx" ]; then
	log "平台 ${PLATFORM}：按设计不接入模拟器核心（保持 URL-only）"
	finish_without_cores "macOS 不接入模拟器核心（仅 URL 模式）"
fi

# ---------------------------------------------------------------- 依赖检查
if ! command -v cmake >/dev/null 2>&1; then
	log "找不到 cmake，跳过核心编译（CI 上应通过 brew 安装 cmake）"
	finish_without_cores "构建环境缺少 cmake，核心未编译"
fi

# ---------------------------------------------------------------- 目标 SDK
case "$PLATFORM" in
	iphoneos)
		SDK_NAME="iphoneos"
		;;
	iphonesimulator)
		# 模拟器构建产物按约定不交付（见 README），这里也顺手跳过省时间
		log "平台 ${PLATFORM}：按约定不交付模拟器产物，跳过核心编译"
		finish_without_cores "模拟器构建不交付核心"
		;;
	*)
		log "未知平台 ${PLATFORM}，按不接入核心处理"
		finish_without_cores "未知平台 ${PLATFORM}"
		;;
esac

if ! xcrun --sdk "$SDK_NAME" --show-sdk-path >/dev/null 2>&1; then
	log "找不到 ${SDK_NAME} SDK（需要完整 Xcode），跳过核心编译"
	finish_without_cores "缺少 ${SDK_NAME} SDK，核心未编译"
fi

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK_NAME" --find clang)"
CXX="$(xcrun --sdk "$SDK_NAME" --find clang++)"

log "平台=${PLATFORM} SDK=${SDK_PATH}"

# ---------------------------------------------------------------- mGBA（GBA / GB / GBC）
# 关键开关（依据 mGBA 官方 CMakeLists 的 LIBMGBA_ONLY 静态库路径）：
#   LIBMGBA_ONLY=ON        —— 只编库，不编任何前端，自动 BUILD_STATIC=ON / BUILD_SHARED=OFF
#   ENABLE_DEBUGGERS=OFF   —— 不需要调试器，去掉它库能小一圈
#   UNIX=1                 —— 确保走 if(UNIX) 分支，拿到 src/platform/posix/*.c 与 vfs-dirent.c
#   CMAKE_BUILD_TYPE=MinSizeRel
#                          —— 刻意不用 Release：mGBA 在 APPLE 平台会给 Release 追加 -flto
#                             （CMakeLists 第 276-279 行），产出的 .a 里是 LLVM bitcode，
#                             Xcode 的 linker 不一定认；MinSizeRel 不会被追加 -flto。
#   不定义 COLOR_16_BIT / COLOR_5_6_5 —— 让 mColor 保持 32 位 RGBA8888，宿主免转换
#   不传 -DMINIMAL_CORE —— CMake 里的 MINIMAL_CORE 只是决定「编哪些源文件」（第 929-948 行），
#                          不会作为编译宏传给核心源码，而且它要剔的那些 SIO/EXTRA 变量
#                          在整个仓库里从没被赋值过，传了也白传。库里没有 MINIMAL_CORE 宏，
#                          宿主胶水层（Sources/Core/GSMGBACore.m 顶部）也就不能定义它。
#
# 与宿主胶水层的约定（改这里必须同步改 GSMGBACore.m 顶部的 #define）：
#   ENABLE_DEBUGGERS=OFF          ⇒ 库里没有 ENABLE_DEBUGGERS 宏；
#   ENABLE_VFS 强制 ON（第 356 行）⇒ 库里必然同时有 ENABLE_VFS 与 ENABLE_DIRECTORIES。
#   这几个宏决定 struct mCore 的成员布局，两边必须一致，否则 ABI 不一致会读错内存。
#
# HAVE_POPCOUNT32=0 / HAVE_CRC32=0：必须显式预置，否则 check_function_exists 会假阳性。
#   原因：上面为了「交叉编译时不真的链接」传了 CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY，
#   这会让 cmake 的 check_function_exists 只编译、不链接 —— 「函数是否存在于 libc」于是永远
#   返回 found。而 Apple libc 里这两个函数是真的没有：
#     · popcount32  → include/mgba-util/math.h 的 inline 回退被 #ifndef HAVE_POPCOUNT32 跳过
#                     ⇒ src/gba/gba.c:476 直接编译报 "call to undeclared function"；
#     · crc32       → src/util/crc32.c 自带实现在 #ifndef HAVE_CRC32 里，被跳过 ⇒ .a 里没有
#                     crc32 符号；USE_ZLIB 又是 OFF（DISABLE_DEPS），zlib 也不会补上它，
#                     ⇒ Xcode 链接期报 _crc32 undefined。
#   预置成 0（非空且 falsy）可同时骗过 CheckFunctionExists 的两条分支
#   （`NOT DEFINED VAR` 与 `VAR STREQUAL ""` 都不会命中），于是它不再去 try_compile，
#   且 flags.h 里的 #cmakedefine HAVE_* 也会被写成 /* #undef */。
if [ -f "$MGBA_DIR/CMakeLists.txt" ]; then
	build_cmake_core mgba "$MGBA_DIR" mgba \
		-DHAVE_POPCOUNT32=0 \
		-DHAVE_CRC32=0 \
		-DBINARY_NAME=mgba \
		-DLIBMGBA_ONLY=ON \
		-DENABLE_DEBUGGERS=OFF \
		-DUNIX=1 \
		&& have_mgba=1
else
	log "找不到 ${MGBA_DIR}/CMakeLists.txt，跳过 mGBA"
fi

# ---------------------------------------------------------------- Nestopia（NES / Famicom）
# 上游是 2003-2008 年的 C++98 代码；Vendor/nestopia/CMakeLists.txt 只编
# source/core/ 下的核心本体 + api 层（不编它给 RetroArch 用的 libretro 前端）。
# 宿主直接调 Nes::Core::Api（见 Sources/Core/GSNestopiaCore.mm）。
if [ -f "$NESTOPIA_DIR/CMakeLists.txt" ]; then
	build_cmake_core nestopia "$NESTOPIA_DIR" nestopia \
		&& have_nestopia=1
else
	log "找不到 ${NESTOPIA_DIR}/CMakeLists.txt，跳过 Nestopia"
fi

# ---------------------------------------------------------------- 汇总
# Snes9x 的源码还没入库（Vendor/snes9x 不存在），因此这里恒为 0 ——
# finalize 会给它补空壳库，UI 侧据 GS_HAVE_SNES9X == 0 如实标「未接入」。
built=""
[ "$have_mgba" -eq 1 ] && built="${built}mGBA（GBA/GB/GBC）、"
[ "$have_nestopia" -eq 1 ] && built="${built}Nestopia（NES）、"
if [ -z "$built" ]; then
	summary="本次没有核心编译成功（见各 *-configure.log / *-build.log）"
else
	summary="${built}已接入"
fi

finalize
exit 0
