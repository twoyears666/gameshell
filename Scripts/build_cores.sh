#!/usr/bin/env bash
#
# build_cores.sh —— 把模拟器核心交叉编译成静态库，供 Xcode 链接。
#
# 为什么是静态库而不是动态库：
#   iOS 15 + A12 起系统封禁了 dynamic-codesigning / com.apple.private.cs.debugger，
#   运行时 dlopen 一个未签名的 core dylib 会被直接拒（RetroArch 那种「外挂 core」的做法
#   在 TrollStore 上也不成立）。所以核心一律静态链接进主二进制。
#
# 产物（每个平台一份，互不污染）：
#   build/cores/<PLATFORM>/libmgba.a      —— 静态库（编译失败时是空壳，保证链接不报错）
#   build/cores/<PLATFORM>/GSBuiltCores.h —— 编译期开关，告诉源码哪个核心真的进来了
#
# 编译失败不会让 Xcode 构建失败：会写出 GS_HAVE_MGBA 0 的头文件 + 空壳库，
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
LIB="$OUT_DIR/libmgba.a"

MGBA_DIR="$ROOT/Vendor/mgba"
MGBA_BUILD_DIR="$OUT_DIR/mgba-build"

mkdir -p "$OUT_DIR"

have_mgba=0
summary=""

log() { printf '[build_cores] %s\n' "$*"; }

write_header() {
	local have="$1"
	local note="$2"
	cat > "$HEADER" <<EOF
// 由 Scripts/build_cores.sh 自动生成，请勿手改。
#ifndef GS_BUILT_CORES_H
#define GS_BUILT_CORES_H

// 1 = mGBA（GBA / GB / GBC）已真正编进主二进制
#define GS_HAVE_MGBA $have

#define GS_CORES_PLATFORM "$PLATFORM"
#define GS_CORES_NOTE "$note"

#endif
EOF
	log "写出 ${HEADER}（GS_HAVE_MGBA=${have}）"
}

# 造一个空壳静态库，让 -lmgba 一定能找到文件（没核心时不会有符号被引用）。
# 注意：空壳里必须真的放一个「目标架构」的 .o，否则链接器会报
# "built for ... which is not the architecture being linked"。
make_stub_library() {
	local tmpdir stub_obj
	tmpdir="$(mktemp -d)"
	# 必须有一个全局符号，否则归档的符号表为空，链接时会有噪音警告
	cat > "$tmpdir/gs_stub.c" <<'STUB'
/* 空壳：本平台没有接入任何模拟器核心（见 GSBuiltCores.h） */
int gs_cores_stub(void) { return 0; }
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
		rm -f "$LIB"
		if xcrun ar rcs "$LIB" "$stub_obj" 2>/dev/null || ar rcs "$LIB" "$stub_obj" 2>/dev/null; then
			log "生成空壳静态库 $LIB"
		else
			log "警告：无法生成空壳静态库 ${LIB}（-lmgba 可能找不到文件）"
		fi
	else
		log "警告：空壳目标文件编译失败，见 $tmpdir/cc.log"
	fi
	rm -rf "$tmpdir"
}

# ---------------------------------------------------------------- macOS：不接核心
# 桌面端保持纯 URL 模式：模拟器相关 UI 在 Swift 侧是 #if os(iOS) 门禁的，
# macOS 不编译也不链接任何核心，省掉一整条交叉编译风险。
if [ "$PLATFORM" = "macosx" ]; then
	log "平台 ${PLATFORM}：按设计不接入模拟器核心（保持 URL-only）"
	make_stub_library
	write_header 0 "macOS 不接入模拟器核心（仅 URL 模式）"
	exit 0
fi

# ---------------------------------------------------------------- 依赖检查
if ! command -v cmake >/dev/null 2>&1; then
	log "找不到 cmake，跳过核心编译（CI 上应通过 brew 安装 cmake）"
	make_stub_library
	write_header 0 "构建环境缺少 cmake，核心未编译"
	exit 0
fi

if [ ! -f "$MGBA_DIR/CMakeLists.txt" ]; then
	log "找不到 $MGBA_DIR/CMakeLists.txt，跳过核心编译"
	make_stub_library
	write_header 0 "缺少 Vendor/mgba 源码，核心未编译"
	exit 0
fi

# ---------------------------------------------------------------- 目标 SDK
case "$PLATFORM" in
	iphoneos)
		SDK_NAME="iphoneos"
		;;
	iphonesimulator)
		# 模拟器构建产物按约定不交付（见 README），这里也顺手跳过省时间
		log "平台 ${PLATFORM}：按约定不交付模拟器产物，跳过核心编译"
		make_stub_library
		write_header 0 "模拟器构建不交付核心"
		exit 0
		;;
	*)
		log "未知平台 ${PLATFORM}，按不接入核心处理"
		make_stub_library
		write_header 0 "未知平台 ${PLATFORM}"
		exit 0
		;;
esac

if ! xcrun --sdk "$SDK_NAME" --show-sdk-path >/dev/null 2>&1; then
	log "找不到 $SDK_NAME SDK（需要完整 Xcode），跳过核心编译"
	make_stub_library
	write_header 0 "缺少 $SDK_NAME SDK，核心未编译"
	exit 0
fi

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
CC="$(xcrun --sdk "$SDK_NAME" --find clang)"

log "平台=$PLATFORM SDK=$SDK_PATH"

# ---------------------------------------------------------------- 配置
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
cmake -S "$MGBA_DIR" -B "$MGBA_BUILD_DIR" \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$SDK_NAME" \
	-DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
	-DCMAKE_C_COMPILER="$CC" \
	-DCMAKE_C_COMPILER_WORKS=1 \
	-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
	-DHAVE_POPCOUNT32=0 \
	-DHAVE_CRC32=0 \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DBINARY_NAME=mgba \
	-DLIBMGBA_ONLY=ON \
	-DENABLE_DEBUGGERS=OFF \
	-DUNIX=1 \
	> "$OUT_DIR/cmake-configure.log" 2>&1

if [ $? -ne 0 ]; then
	log "cmake 配置失败，详情见 $OUT_DIR/cmake-configure.log"
	make_stub_library
	write_header 0 "mGBA 配置失败（见 cmake-configure.log）"
	exit 0
fi

# ---------------------------------------------------------------- 编译
log "开始编译 libmgba.a（日志：$OUT_DIR/cmake-build.log）"
cmake --build "$MGBA_BUILD_DIR" --target mgba --parallel 4 \
	> "$OUT_DIR/cmake-build.log" 2>&1

if [ $? -ne 0 ]; then
	log "mGBA 编译失败，详情见 $OUT_DIR/cmake-build.log"
	make_stub_library
	write_header 0 "mGBA 编译失败（见 cmake-build.log）"
	exit 0
fi

# ---------------------------------------------------------------- 收集产物
BUILT_LIB="$(find "$MGBA_BUILD_DIR" -name 'libmgba.a' -type f 2>/dev/null | head -n 1)"

if [ -z "$BUILT_LIB" ]; then
	log "编译成功但没找到 libmgba.a，详情见 $OUT_DIR/cmake-build.log"
	make_stub_library
	write_header 0 "mGBA 产物缺失"
	exit 0
fi

cp "$BUILT_LIB" "$LIB"
have_mgba=1
summary="mGBA 已接入（GBA / GB / GBC）"
log "完成：${LIB}（$(du -h "$LIB" | cut -f1)）"

write_header "$have_mgba" "$summary"
exit 0
