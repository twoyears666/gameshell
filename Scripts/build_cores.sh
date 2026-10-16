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
#   Mesen-S  —— SNES / Super Famicom（Vendor/mesens，GPL-3.0）
#   melonDS  —— NDS / DSi（Vendor/melonds，GPL-3.0；编入 ARM64 JIT，无 JIT 时自动走解释器）
# 尚无源码 / 尚未接入的核心只留空壳库，由 GSBuiltCores.h 里的开关如实标成 0：
#   · Azahar(3DS) / Dolphin(Wii) 需要 GL 硬件渲染宿主层，待立项（本轮不接，不假装接入）；
#   · Wii U 核心本轮不做。
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
MESENS_DIR="$ROOT/Vendor/mesens"
MELONDS_DIR="$ROOT/Vendor/melonds"

mkdir -p "$OUT_DIR"

# 各核心「这次是否真的编出来了」，最后写进 GSBuiltCores.h
have_mgba=0
have_nestopia=0
have_mesens=0
have_melonds=0
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
#define GS_HAVE_MESENS $have_mesens
#define GS_HAVE_MELONDS $have_melonds

#define GS_CORES_PLATFORM "$PLATFORM"
#define GS_CORES_NOTE "$summary"

#endif
EOF
	log "写出 ${HEADER}（mGBA=${have_mgba} Nestopia=${have_nestopia} Mesen-S=${have_mesens} melonDS=${have_melonds}）"
}

# 收尾：没编出来的核心补空壳库，然后写编译期开关头。成功编出来的核心不动（不覆盖真库）。
finalize() {
	[ "$have_mgba" -eq 1 ] || make_stub_library mgba
	[ "$have_nestopia" -eq 1 ] || make_stub_library nestopia
	[ "$have_mesens" -eq 1 ] || make_stub_library mesens
	[ "$have_melonds" -eq 1 ] || make_stub_library melonds
	write_header
}

# 一个核心都没编（平台/工具链不满足）时的统一收尾
finish_without_cores() {
	have_mgba=0
	have_nestopia=0
	have_mesens=0
	have_melonds=0
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

# 交叉编译一个「libretro 标准 Makefile」形态的核心。
# 用法：build_make_core <核心名> <源码目录> <产物文件名> [额外的 make 变量...]
# 成功返回 0 并把产物放到 $OUT_DIR/lib<核心名>.a；失败返回 1，日志留在
# $OUT_DIR/<核心名>-build.log。
#
# melonDS 的 make 会把 .o 直接写在源码树里（Makefile 的 `%.o: %.cpp` 没有 OBJDIR），
# 为了不污染 Vendor/（那是要入库的上游源码），先把源码 rsync 一份到
# $OUT_DIR/<核心名>-build/ 再在里面编。
#
# 交叉编译要点：
#   platform=ios-arm64 → Makefile 走 iOS 分支（TARGET 变成 *_libretro_ios.dylib）
#   STATIC_LINKING=1   → 链接规则从 $(LD) -dynamiclib 换成 $(AR) rcs（产静态归档）
#   IOSSDK=$SDK_PATH   → Makefile 用 -isysroot 找 SDK
#   CC/CXX 显式指到 SDK 里的 clang：Makefile 的 iOS 分支硬写 `cc`/`c++`（第 139-140 行），
#     命令行变量优先于 Makefile 赋值，这里覆盖掉它，编出来才是 iOS 目标架构，
#     否则 .a 是宿主架构、链接期被 ld 整档忽略。
#   产物名仍是 melonds_libretro_ios.dylib（iOS 分支把 TARGET 写死了，STATIC_LINKING=1
#   只改链接规则、不改文件名），内容其实是 ar 归档 → 复制成 lib<核心名>.a。
build_make_core() {
	local name="$1"
	local src_dir="$2"
	local artifact="$3"
	shift 3

	local build_dir="$OUT_DIR/${name}-build"
	local build_log="$OUT_DIR/${name}-build.log"

	rm -rf "$build_dir"
	mkdir -p "$build_dir"
	rsync -a --delete --exclude '.git' "$src_dir/" "$build_dir/" >> "$build_log" 2>&1

	log "开始编译 lib${name}.a（日志：${build_log}）"
	( cd "$build_dir" \
		&& make -j4 \
			platform=ios-arm64 \
			STATIC_LINKING=1 \
			IOSSDK="$SDK_PATH" \
			MINVERSION="-miphoneos-version-min=16.0" \
			CC="$CC -arch arm64 -isysroot $SDK_PATH" \
			CXX="$CXX -arch arm64 -isysroot $SDK_PATH" \
			"$@" ) >> "$build_log" 2>&1

	if [ ! -f "$build_dir/$artifact" ]; then
		log "${name} 编译失败或未产出 ${artifact}，详情见 ${build_log}"
		return 1
	fi

	cp "$build_dir/$artifact" "$OUT_DIR/lib${name}.a"
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

# ---------------------------------------------------------------- Mesen-S（SNES / Super Famicom）
# 上游是 2019 年归档的 C++14 核心（Vendor/mesens，GPL-3.0）。
# 我们按它的 Libretro/ 前端形态编（Vendor/mesens/CMakeLists.txt 的源清单逐项照抄
# Libretro/Makefile.common），宿主侧走 libretro 接口（见 Sources/Core/GSSnesCore.mm）。
# -DLIBRETRO 由 CMakeLists.txt 内部定义，不能用切换宏关掉：
#   它切掉的是「桌面版才有的独立解码/渲染线程 + Lua + 联网」——
#   带上它 retro_run 才会在调用线程里同步跑完一帧，宿主的逐帧架构才成立。
if [ -f "$MESENS_DIR/CMakeLists.txt" ]; then
	build_cmake_core mesens "$MESENS_DIR" mesens \
		&& have_mesens=1
else
	log "找不到 ${MESENS_DIR}/CMakeLists.txt，跳过 Mesen-S"
fi

# ---------------------------------------------------------------- melonDS（NDS / DSi）
# 上游 libretro fork（Vendor/melonds，GPL-3.0），构建系统是标准的 libretro Makefile。
# 关键点：
#   · 走 libretro 软件渲染 + CPU 帧缓冲链路（HAVE_OPENGL 默认 0；GPU3D_Soft.cpp 始终编入），
#     与宿主「只要一帧 RGBA8888」的架构匹配（见 Sources/Core/GSMelonDSCore.mm）。
#   · JIT_ARCH=aarch64 显式打开 ARM64 dynarec（iOS 分支默认不开）。
#     于是库里同时有 JIT 与解释器两条路径，运行时由宿主按探测结果作答核心选项
#     melonds_jit_enable：JIT 可用→enabled（走 dynarec），不可用→disabled（走解释器）。
#     JIT 用 mmap(MAP_JIT) + pthread_jit_write_protect_np，需要 JIT entitlement（tipa 已带）。
#   · Vendor/melonds/Makefile.common 有一处 Gameshell 补丁：把上游
#     `ifneq ($(STATIC_LINKING),1)` 的 libretro-common 守卫改成恒真，
#     否则静态链接时这些符号没人提供，App 链接期会一片 undefined symbol。
if [ -f "$MELONDS_DIR/Makefile" ]; then
	if build_make_core melonds "$MELONDS_DIR" melonds_libretro_ios.dylib JIT_ARCH=aarch64; then
		have_melonds=1
	fi
else
	log "找不到 ${MELONDS_DIR}/Makefile，跳过 melonDS"
fi

# ---------------------------------------------------------------- 汇总
built=""
[ "$have_mgba" -eq 1 ] && built="${built}mGBA（GBA/GB/GBC）、"
[ "$have_nestopia" -eq 1 ] && built="${built}Nestopia（NES）、"
[ "$have_mesens" -eq 1 ] && built="${built}Mesen-S（SNES）、"
[ "$have_melonds" -eq 1 ] && built="${built}melonDS（NDS/DSi）、"
if [ -z "$built" ]; then
	summary="本次没有核心编译成功（见各 *-configure.log / *-build.log）"
else
	summary="${built}已接入"
fi

finalize
exit 0
