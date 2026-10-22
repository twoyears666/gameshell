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
#   Azahar   —— Nintendo 3DS（上游 azahar-emu/azahar，GPL-2.0；源码不入库，构建时现克隆现编，
#               iOS 上走软件渲染 + 解释器，不需要 JIT）
#   Dolphin  —— Wii / GameCube（上游 libretro/dolphin 的 libretro 形态，GPL-2.0+；
#               源码不入库，构建时现克隆现编，iOS 上走「无 GL 上下文」的软件光栅器，
#               JIT 可用时走 JITARM64，不可用时核心自行退回 CachedInterpreter）
# 尚无源码 / 尚未接入的核心只留空壳库，由 GSBuiltCores.h 里的开关如实标成 0：
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
have_azahar=0
have_dolphin=0
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
#define GS_HAVE_AZAHAR $have_azahar
#define GS_HAVE_DOLPHIN $have_dolphin

#define GS_CORES_PLATFORM "$PLATFORM"
#define GS_CORES_NOTE "$summary"

#endif
EOF
	log "写出 ${HEADER}（mGBA=${have_mgba} Nestopia=${have_nestopia} Mesen-S=${have_mesens} melonDS=${have_melonds} Azahar=${have_azahar} Dolphin=${have_dolphin}）"
}

# 收尾：没编出来的核心补空壳库，然后写编译期开关头。成功编出来的核心不动（不覆盖真库）。
finalize() {
	[ "$have_mgba" -eq 1 ] || make_stub_library mgba
	[ "$have_nestopia" -eq 1 ] || make_stub_library nestopia
	[ "$have_mesens" -eq 1 ] || make_stub_library mesens
	[ "$have_melonds" -eq 1 ] || make_stub_library melonds
	[ "$have_azahar" -eq 1 ] || make_stub_library azahar
	[ "$have_dolphin" -eq 1 ] || make_stub_library dolphin
	write_header
}

# 一个核心都没编（平台/工具链不满足）时的统一收尾
finish_without_cores() {
	have_mgba=0
	have_nestopia=0
	have_mesens=0
	have_melonds=0
	have_azahar=0
	have_dolphin=0
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

# 交叉编译 Azahar（3DS）libretro 核心，产出一个合并好的 $OUT_DIR/libazahar.a。
#
# 与其它核心有两处本质不同：
#  1) Azahar 没有 vendoring 进 Vendor/（它递归子模块近 20 个 —— boost / dynarmic /
#     libressl / … 全量入库太重），所以这里直接在 $OUT_DIR 里
#     git clone --recurse-submodules，构建产物不污染 Vendor/。因此这个函数需要网络。
#  2) 绝不复用 build_cmake_core()：后者硬传 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY，
#     会让 libressl 的 check_function_exists 全部假阳性、不启用自带 compat 垫片，
#     进而触发 vsyslog_r / explicit_bzero 符号未定义 —— 这是探路阶段挖出来的真根因。
#     这里保持默认（EXECUTABLE，检测真去链接），并另加两条兜底 -DHAVE_SYSLOG_R=0 /
#     -DHAVE_EXPLICIT_BZERO=0。
#
# 参数口径与探路工作流（.github/workflows/probe-azahar-ios.yml，azahar-probe 分支）
# 完全一致，那一版已在 iOS 16.0 上真实编通（CI run 全绿）。
#
# 产物名：Azahar 的 CMake 把 target citra_libretro 的 PREFIX 设为 ""、
# OUTPUT_NAME 设为 azahar_libretro；把 SHARED 改成 STATIC 后产物就是 azahar_libretro.a。
# 但它是「只含自身目标文件」的静态库，依赖的 20 多个 .a 不会自动并进去，
# 所以最后用 libtool -static 把 build 目录下所有 .a 合并成单一 libazahar.a，
# 让 App 只需要一条 -lazahar。
build_azahar_core() {
	local src_dir="$OUT_DIR/azahar-src"
	local build_dir="$OUT_DIR/azahar-build"
	local configure_log="$OUT_DIR/azahar-configure.log"
	local build_log="$OUT_DIR/azahar-build.log"

	rm -rf "$src_dir" "$build_dir"
	: > "$configure_log"
	: > "$build_log"

	# 打补丁与插入符号前缀都要用 python3；缺了它整条 Azahar 段就跑不起来，
	# 这里显式拦下（缺 python3 时 CI 应通过 brew install python 补上）。
	if ! command -v python3 >/dev/null 2>&1; then
		log "找不到 python3，无法给 Azahar 打补丁（CI 上应通过 brew install python 补上）"
		return 1
	fi

	log "克隆 Azahar 及其全部子模块（日志：${configure_log}）"
	if ! git clone --recurse-submodules --jobs 8 \
			https://github.com/azahar-emu/azahar.git "$src_dir" >> "$configure_log" 2>&1; then
		log "Azahar 克隆失败，详情见 ${configure_log}"
		return 1
	fi

	# 消除 Vulkan-Hpp 的 std::format 依赖：vulkan_to_string.hpp 的 toHexString 里
	# std::format("{:x}", value) 会拉起 libc++ 的浮点 to_chars，而它被标成
	# 「introduced in iOS 16.3」——部署目标 16.0 时直接编译报错。该文件里 std::format
	# 只此一处，改成等价的 sstream 实现即可从源头不实例化它。
	# 注意：不能用 _LIBCPP_DISABLE_AVAILABILITY 压注解绕过 —— 那只是把编译错误变成
	# iOS 16.0 上的运行期隐患（系统 libc++ 没这个外置符号）。
	python3 - "$src_dir/externals/vulkan-headers/include/vulkan/vulkan_to_string.hpp" <<'PY' >> "$configure_log" 2>&1
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

old = '#if __cpp_lib_format\n    return std::format( "{:x}", value );\n'
new = '#if 0  // Gameshell 补丁：不走 std::format（libc++ 会拉起浮点 to_chars，要求 iOS 16.3+）\n    return std::format( "{:x}", value );\n'
assert old in text, "toHexString 的 std::format 段没找到（Vulkan-Headers 版本可能变了）"
text = text.replace(old, new, 1)

anchor = '#    include <format>  // std::format\n'
assert anchor in text, "找不到 <format> 的 include 行"
text = text.replace(
    anchor,
    anchor + '#    include <sstream>  // Gameshell 补丁：给 toHexString 的 sstream 分支用\n',
    1,
)

path.write_text(text)
print("已给 Vulkan-Hpp 打补丁：", path)
PY

	log "给 Azahar 打符号前缀补丁 + 静态化补丁"
	# 入口点符号前缀：同一 App 里还静态链接了 Mesen-S 与 melonDS，retro_* 入口点会撞车。
	# Azahar 的入口点分散在 citra_libretro.cpp 与 environment.cpp 两个翻译单元，
	# 两处都必须在各自的 libretro.h 之前 include 前缀头。
	# 同时放一份到 $OUT_DIR：宿主胶水 GSAzaharCore.mm 也 include 这份头，
	# 而 $OUT_DIR 在 HEADER_SEARCH_PATHS 里（$(SRCROOT)/build/cores/$(PLATFORM_NAME)）。
	cp "$ROOT/Scripts/azahar/gs_azahar_symbol_prefix.h" "$OUT_DIR/gs_azahar_symbol_prefix.h" >> "$configure_log" 2>&1
	cp "$ROOT/Scripts/azahar/gs_azahar_symbol_prefix.h" \
		"$src_dir/src/citra_libretro/gs_azahar_symbol_prefix.h" >> "$configure_log" 2>&1
	for f in "$src_dir/src/citra_libretro/citra_libretro.cpp" \
			"$src_dir/src/citra_libretro/environment.cpp"; do
		python3 - "$f" <<'PY' >> "$configure_log" 2>&1
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
header = '#include "gs_azahar_symbol_prefix.h"  // Gameshell 补丁：把 retro_* 入口点改名，避免与其它核心撞车\n'
if 'gs_azahar_symbol_prefix.h' not in text:
    path.write_text(header + text)
print("已插入符号前缀 include：", path)
PY
	done

	# 静态化：SHARED → STATIC；去掉 Darwin 的 -Wl,-exported_symbols_list
	# （那是给 dylib 用的，静态归档用不到，且会带上一个不存在的 .def 依赖）。
	python3 - "$src_dir/src/citra_libretro/CMakeLists.txt" <<'PY' >> "$configure_log" 2>&1
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

shared = 'add_library(citra_libretro SHARED'
static = 'add_library(citra_libretro STATIC  # Gameshell 补丁：静态链接进主二进制'
assert shared in text, "找不到 add_library(citra_libretro SHARED)"
text = text.replace(shared, static, 1)

exported = '''if (CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR
    CMAKE_SYSTEM_NAME STREQUAL "iOS" OR
    CMAKE_SYSTEM_NAME STREQUAL "tvOS")
  target_link_libraries(citra_libretro PRIVATE "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/libretro.osx.def")
else()
  target_link_libraries(citra_libretro PRIVATE "-Wl,-Bsymbolic")
endif()'''
assert exported in text, "找不到 Darwin 的 exported_symbols_list 段"
text = text.replace(
    exported,
    '# Gameshell 补丁：静态归档不链接，去掉 -Wl,-exported_symbols_list / -Bsymbolic 等纯链接期开关',
    1,
)

path.write_text(text)
print("已把 citra_libretro 静态化：", path)
PY

	# 放开 CPU JIT —— 「有 JIT 就一定用 JIT」。
	# 上游在 iOS 上把 use_cpu_jit 硬写成 false（选项定义也被 #ifndef IOS 挡住），
	# 但 Azahar 的 dynarmic 后端其实照样编了（arm/dynarmic/arm_dynarmic.cpp 在 citra_core 里），
	# 只要设备拿得到可执行内存就该走 JIT。所以这里只改两处、不碰别的东西：
	#   ① ParseCpuOptions 去掉 #ifdef IOS false; 分支，改成一律问前端；
	#   ② 把 use_cpu_jit 的选项定义从 #ifndef IOS 里放出来，否则前端答了核心也不认。
	# 无 JIT 的设备由宿主答 disabled（见 GSAzaharCore.mm 的 gs_retro_lookup_variable），
	# 核心于是按 use_fastinterp 退回 FastInterp 解释器 —— 双模式，不拒绝启动。
	# 注意 use_shader_jit 不动：那是给硬件着色器用的，我们走软件渲染，没有它的事。
	# 上游是未钉版本的 master，core_settings.cpp 随时可能改样；
	# 补丁靠三段 assert 定位，对不上就说明「有 JIT 一定用 JIT」这条断了，
	# 必须让整段 Azahar 构建失败（GS_HAVE_AZAHAR 变 0），而不是静默编出一个只走解释器的核心。
	if ! python3 - "$src_dir/src/citra_libretro/core_settings.cpp" <<'PY' >> "$configure_log" 2>&1
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

# ① 选项定义不再对 iOS 隐藏（把 use_cpu_jit 那一项从 #ifndef IOS 里挪出来）
old_opt = '''#ifndef IOS
    {
        config::cpu::use_cpu_jit,'''
new_opt = '''    {
        config::cpu::use_cpu_jit,'''
assert old_opt in text, "找不到 use_cpu_jit 选项定义前的 #ifndef IOS"
text = text.replace(old_opt, new_opt, 1)

# 该选项定义以 "config::enabled\\n    },\\n#endif" 收尾，紧跟着就是 use_fastinterp 那一项，
# 用后半段一起匹配保证只动这一处。
old_end = '''        config::enabled
    },
#endif
    {
        config::cpu::use_fastinterp,'''
new_end = '''        config::enabled
    },
    {
        config::cpu::use_fastinterp,'''
assert old_end in text, "找不到 use_cpu_jit 选项定义结尾的 #endif"
text = text.replace(old_end, new_end, 1)

# ② ParseCpuOptions 不再硬写 false，改成问前端
old_parse = '''    Settings::values.use_cpu_jit =
#ifdef IOS
        false;
#else
        LibRetro::FetchVariable(config::cpu::use_cpu_jit, config::enabled) == config::enabled;
#endif'''
new_parse = '''    Settings::values.use_cpu_jit =
        LibRetro::FetchVariable(config::cpu::use_cpu_jit, config::enabled) == config::enabled;'''
assert old_parse in text, "找不到 ParseCpuOptions 里 #ifdef IOS 硬写 false 的段"
text = text.replace(old_parse, new_parse, 1)

path.write_text(text)
print("已放开 Azahar 的 CPU JIT：", path)
PY
	then
		log "放开 CPU JIT 失败：core_settings.cpp 的补丁段没对上（上游可能改过），详情见 ${configure_log}"
		return 1
	fi
	log "已放开 Azahar 的 CPU JIT：citra_use_cpu_jit 在 iOS 上不再被硬写成 false"

	log "配置 Azahar（交叉编译到 iOS arm64，日志：${configure_log}）"
	cmake -S "$src_dir" -B "$build_dir" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT=iphoneos \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
		-DCMAKE_C_COMPILER="$CC" \
		-DCMAKE_CXX_COMPILER="$CXX" \
		-DCMAKE_OBJC_COMPILER="$CC" \
		-DCMAKE_OBJCXX_COMPILER="$CXX" \
		-DCMAKE_ASM_COMPILER="$CC" \
		-DCMAKE_C_COMPILER_WORKS=1 \
		-DCMAKE_CXX_COMPILER_WORKS=1 \
		-DCMAKE_BUILD_TYPE=Release \
		-DENABLE_LIBRETRO=ON \
		-DENABLE_TESTS=OFF \
		-DENABLE_LTO=OFF \
		-DHAVE_SYSLOG_R=0 \
		-DHAVE_EXPLICIT_BZERO=0 \
		-DCITRA_WARNINGS_AS_ERRORS=OFF \
		>> "$configure_log" 2>&1
	if [ $? -ne 0 ]; then
		log "Azahar 的 cmake 配置失败，详情见 ${configure_log}"
		return 1
	fi

	log "开始编译 Azahar libretro 核心（日志：${build_log}，这一步最重，会很久）"
	cmake --build "$build_dir" --target citra_libretro --parallel 4 >> "$build_log" 2>&1
	if [ $? -ne 0 ]; then
		log "Azahar 编译失败，详情见 ${build_log}"
		return 1
	fi

	# 合并所有静态库：citra_libretro.a 只含自身目标文件，依赖的 20 多个 .a 不会自动并进去。
	local -a libs
	libs=()
	while IFS= read -r line; do
		libs+=("$line")
	done < <(find "$build_dir" -name '*.a' -type f)
	if [ "${#libs[@]}" -eq 0 ]; then
		log "编译成功但没找到任何 .a，详情见 ${build_log}"
		return 1
	fi

	local libtool
	libtool="$(xcrun --find libtool 2>/dev/null || command -v libtool || true)"
	if [ -z "$libtool" ]; then
		log "找不到 libtool，无法合并 Azahar 静态库"
		return 1
	fi

	log "合并 ${#libs[@]} 个静态库为 libazahar.a（日志：${configure_log}）"
	rm -f "$OUT_DIR/libazahar.a"
	if ! "$libtool" -static -o "$OUT_DIR/libazahar.a" "${libs[@]}" >> "$configure_log" 2>&1; then
		log "libtool 合并失败，详情见 ${configure_log}"
		return 1
	fi
	if [ ! -s "$OUT_DIR/libazahar.a" ]; then
		log "libtool 没有产出 libazahar.a，详情见 ${configure_log}"
		return 1
	fi

	log "完成：${OUT_DIR}/libazahar.a（$(du -h "$OUT_DIR/libazahar.a" | cut -f1)）"

	# 合并完成、产物已留下，就把克隆下来的源码树与中间产物删掉：
	# Azahar 递归子模块体量很大，不删会给后续的 Xcode 构建留下磁盘压力。
	# 日志在 $OUT_DIR 下的 azahar-*.log，不在这里面，删掉不影响排查。
	rm -rf "$src_dir" "$build_dir"
	return 0
}

# 交叉编译 Dolphin（Wii / GameCube）libretro 核心，产出一个合并好的 $OUT_DIR/libdolphin.a。
#
# 与 Azahar 同一套思路（源码不入库、构建时现克隆现编、最后合并所有 .a），但有三处必须
# 自己拍板的地方：
#
#  1) 上游选 libretro/dolphin，而不是 dolphin-emu/dolphin —— 官方仓库里没有
#     Source/Core/DolphinLibretro 这层 libretro 前端；只有 libretro 的 fork 有，
#     且它的顶层 CMake 明确带 IOS 分支（if(IOS) add_definitions(-DIPHONEOS) 等）。
#
#  2) Dolphin 的「软件渲染」在 libretro 里仍然会造一个 SWOGLWindow ——
#     也就是即便只想拿 CPU 帧缓冲，它也要求宿主提供一个 GL 上下文
#     （GLContextLR → 前端 SET_HW_RENDER）。我们没有、也不想为它引一条 GLES 渲染通路，
#     所以给上游打「headless 补丁」：GL 上下文创建失败时保留 m_gl_context 为空的窗口，
#     把 GL 相关调用全部跳过，帧由 Libretro::Video::SWGfx::ShowImage 的 video_cb 直接交付。
#     这个补丁是 Wii 能进本 App 的前提，绝不能丢。
#     另外，上游在 __LIBRETRO__ 下把 Core::GetInitializedVideoGuard 的 init_video 改成直接
#     return true，视频后端真正的初始化只挂在「SET_HW_RENDER → 前端回调 ContextReset」上；
#     软件渲染根本不走 SET_HW_RENDER，于是 Presenter / 顶点管理器 / 纹理缓存全是空指针，
#     首个视频帧就崩。所以补丁还要在 Main.cpp 里显式补一次后端初始化。
#
#  3) 渲染器选项 dolphin_renderer 的 "Software" 项在上游被
#     #if defined(_DEBUG) || defined(DEBUGFAST) 包着 —— Release 构建里根本不存在。
#     宿主答 "Software" 会被选项校验打回默认值 "Hardware"，接着走 SET_HW_RENDER 失败 → Null。
#     因此补丁里必须把 Software/Null 两项从调试宏里放出来。
#
# JIT：Dolphin 在 iOS 上自己检测可执行内存（Boot.cpp），拿不到时退回 CachedInterpreter。
# 宿主侧（Sources/Core/GSWiiCore.mm）按 GSJIT 探测结果答 dolphin_cpu_core，
# 「有 JIT 就一定用 JIT」，没有也不拒绝启动。
#
# 产物：target dolphin_libretro 默认是 SHARED，补丁改成 STATIC；
# 它只含自身目标文件，依赖库（core / video / audio / Externals/*）都是独立 .a，
# 所以最后用 libtool -static 合并成单一 libdolphin.a，App 只需要一条 -ldolphin。
build_dolphin_core() {
	local src_dir="$OUT_DIR/dolphin-src"
	local build_dir="$OUT_DIR/dolphin-build"
	local configure_log="$OUT_DIR/dolphin-configure.log"
	local build_log="$OUT_DIR/dolphin-build.log"
	local prefix_header="$ROOT/Scripts/dolphin/gs_dolphin_symbol_prefix.h"

	rm -rf "$src_dir" "$build_dir"
	: > "$configure_log"
	: > "$build_log"

	if ! command -v python3 >/dev/null 2>&1; then
		log "找不到 python3，无法给 Dolphin 打补丁（CI 上应通过 brew install python 补上）"
		return 1
	fi

	cp "$prefix_header" "$OUT_DIR/gs_dolphin_symbol_prefix.h" >> "$configure_log" 2>&1

	# 只取一层历史：Dolphin 仓库不大，但 --depth 1 仍能省掉大半克隆时间。
	log "克隆 libretro/dolphin（日志：${configure_log}）"
	if ! git clone --depth 1 https://github.com/libretro/dolphin.git "$src_dir" >> "$configure_log" 2>&1; then
		log "Dolphin 克隆失败，详情见 ${configure_log}"
		return 1
	fi

	# 必须初始化一部分子模块：Dolphin 把 fmt / zstd / zlib-ng / lz4 / curl / spng 等
	# 直接以子模块形式放在 Externals/ 下，顶层 CMake 对这些库是「找不到系统库就用自带」，
	# 而 iOS 交叉编译根本不可能命中系统库 —— 于是 configure 阶段会去 add_subdirectory
	# 那些空目录，直接报 "does not contain a CMakeLists.txt file"。
	#
	# 这里只拉 iOS + LIBRETRO 真正会用到的那批，Windows/Qt/FFmpeg/libusb/SDL/cubeb/
	# mGBA/rcheevos/watcher/gtest 等都被我们的 cmake 开关关掉或按平台跳过，不拉。
	# 少拉一个就要多跑一轮 CI，所以下面的清单必须和顶层 CMakeLists 的引入条件对得上。
	local dolphin_submodules=(
		Externals/cpp-optparse/cpp-optparse
		Externals/fmt/fmt
		Externals/imgui/imgui
		Externals/implot/implot
		Externals/glslang/glslang
		Externals/spirv_cross/SPIRV-Cross
		Externals/tinygltf/tinygltf
		Externals/pugixml/pugixml
		Externals/enet/enet
		Externals/xxhash/xxHash
		Externals/bzip2/bzip2
		Externals/zstd/zstd
		Externals/zlib-ng/zlib-ng
		Externals/minizip-ng/minizip-ng
		Externals/lz4/lz4
		Externals/libspng/libspng
		Externals/curl/curl
		Externals/SFML/SFML
	)
	log "拉取 Dolphin 依赖子模块（${#dolphin_submodules[@]} 个，日志：${configure_log}）"
	if ! git -C "$src_dir" submodule update --init --depth 1 "${dolphin_submodules[@]}" >> "$configure_log" 2>&1; then
		log "Dolphin 子模块拉取失败，详情见 ${configure_log}"
		return 1
	fi

	log "给 Dolphin 打补丁（静态化 / 放开软件渲染 / headless 呈现 / 软件路径后端初始化 / 符号前缀 / GBA 配置守卫）"
	if ! python3 - "$src_dir" <<'PY' >> "$configure_log" 2>&1
import pathlib
import sys

root = pathlib.Path(sys.argv[1])

# ---------------------------------------------------------------- 静态化
path = root / "Source/Core/DolphinLibretro/CMakeLists.txt"
text = path.read_text()
old = "add_library(dolphin_libretro SHARED"
new = "add_library(dolphin_libretro STATIC  # Gameshell 补丁：静态链接进主二进制"
assert old in text, "找不到 add_library(dolphin_libretro SHARED)"
path.write_text(text.replace(old, new, 1))
print("已静态化 dolphin_libretro：", path)

# ---------------------------------------------------------------- 放开软件渲染
path = root / "Source/Core/DolphinLibretro/Common/Options.cpp"
text = path.read_text()
old = """      { "Hardware", "Hardware" },
  #if defined(_DEBUG) || defined(DEBUGFAST)
      { "Software", "Software Renderer" },
      { "Null",     "Null Renderer" },
  #endif
"""
new = """      { "Hardware", "Hardware" },
      // Gameshell 补丁：Release 也保留软件渲染 —— iOS 上没有可用的硬件渲染通路，
      // 宿主只会答 "Software"（见 Sources/Core/GSWiiCore.mm 的 gs_retro_lookup_variable）。
      { "Software", "Software Renderer" },
      { "Null",     "Null Renderer" },
"""
assert old in text, "找不到 dolphin_renderer 的 Hardware/Software 选项表"
path.write_text(text.replace(old, new, 1))
print("已放开 Release 下的软件渲染选项：", path)

# ---------------------------------------------------------------- headless 呈现（窗口）
path = root / "Source/Core/VideoBackends/Software/SWOGLWindow.cpp"
text = path.read_text()

old = """  if (!window->Initialize(wsi))
  {
    PanicAlertFmt("Failed to create OpenGL window");
    return nullptr;
  }
"""
new = """  if (!window->Initialize(wsi))
  {
#ifdef __LIBRETRO__
    // Gameshell 补丁：libretro 前端直接收 CPU 帧缓冲，不需要 GL 窗口。
    // 保留一个 m_gl_context 为空的「headless 窗口」，后续 GL 调用一律跳过。
    WARN_LOG_FMT(VIDEO, "Libretro: no GL context, using CPU-only present path");
#else
    PanicAlertFmt("Failed to create OpenGL window");
    return nullptr;
#endif
  }
"""
assert old in text, "找不到 SWOGLWindow::Create 的失败分支"
text = text.replace(old, new, 1)

old = """bool SWOGLWindow::IsHeadless() const
{
  return m_gl_context->IsHeadless();
}
"""
new = """bool SWOGLWindow::IsHeadless() const
{
  // Gameshell 补丁：CPU-only 路径没有 GL 上下文，一律按 headless 处理
  return !m_gl_context || m_gl_context->IsHeadless();
}
"""
assert old in text, "找不到 SWOGLWindow::IsHeadless"
text = text.replace(old, new, 1)

old = """  const SW::SWTexture* sw_image = static_cast<const SW::SWTexture*>(image);
  m_gl_context->Update();"""
new = """  const SW::SWTexture* sw_image = static_cast<const SW::SWTexture*>(image);
  // Gameshell 补丁：没有 GL 上下文时不做任何 GL blit（帧已由 video_cb 交出去）
  if (!m_gl_context)
    return;
  m_gl_context->Update();"""
assert old in text, "找不到 SWOGLWindow::ShowImage 的开头"
text = text.replace(old, new, 1)

path.write_text(text)
print("已给 SWOGLWindow 加 headless 分支：", path)

# ---------------------------------------------------------------- headless 呈现（SWGfx）
path = root / "Source/Core/VideoBackends/Software/SWGfx.cpp"
text = path.read_text()

old = """bool SWGfx::IsHeadless() const
{
  return m_window->IsHeadless();
}
"""
new = """bool SWGfx::IsHeadless() const
{
  // Gameshell 补丁：没有窗口（或窗口没有 GL 上下文）时按 headless 处理
  return !m_window || m_window->IsHeadless();
}
"""
assert old in text, "找不到 SWGfx::IsHeadless"
text = text.replace(old, new, 1)

old = """  // Look for framebuffer resizes
  if (!g_presenter->SurfaceResizedTestAndClear())
    return true;

  GLContext* context = m_window->GetContext();
  context->Update();
  g_presenter->SetBackbuffer(context->GetBackBufferWidth(), context->GetBackBufferHeight());
  return true;
"""
new = """  // Gameshell 补丁：软件渲染路径上游从来没有真正初始化过后端，
  // g_presenter 可能是空的；这里绝不直接解引用（初始化见 Main.cpp 的补丁）。
  if (!g_presenter)
    return true;

  // Look for framebuffer resizes
  if (!g_presenter->SurfaceResizedTestAndClear())
    return true;

  GLContext* context = m_window ? m_window->GetContext() : nullptr;
  if (!context)
    return true;

  context->Update();
  g_presenter->SetBackbuffer(context->GetBackBufferWidth(), context->GetBackBufferHeight());
  return true;
"""
assert old in text, "找不到 SWGfx::BindBackbuffer 的上下文使用段"
text = text.replace(old, new, 1)

old = """  GLContext* context = m_window->GetContext();
  return {std::max(context->GetBackBufferWidth(), 1u), std::max(context->GetBackBufferHeight(), 1u),
          1.0f, AbstractTextureFormat::RGBA8};
"""
new = """  GLContext* context = m_window ? m_window->GetContext() : nullptr;
  if (!context)
  {
    // Gameshell 补丁：CPU-only 路径按 EFB 原生尺寸报告表面（Wii / GameCube 都是 640x480 起）
    return {640, 480, 1.0f, AbstractTextureFormat::RGBA8};
  }
  return {std::max(context->GetBackBufferWidth(), 1u), std::max(context->GetBackBufferHeight(), 1u),
          1.0f, AbstractTextureFormat::RGBA8};
"""
assert old in text, "找不到 SWGfx::GetSurfaceInfo"
text = text.replace(old, new, 1)

path.write_text(text)
print("已给 SWGfx 加 headless 分支：", path)

# ---------------------------------------------------------------- headless 下仍要出帧
# Presenter::Present 一开头就 `if (g_gfx->IsHeadless()) return;`。我们的软件渲染窗口
# 是 headless 的（没有 GL 上下文），于是 ShowImage → video_cb 永远走不到 —— 表现为黑屏。
# libretro 下把这条早退去掉，帧继续交给 SWGfx::ShowImage（GL blit 那步已被上面的补丁跳过）。
path = root / "Source/Core/VideoCommon/Present.cpp"
text = path.read_text()

old = """  if (g_gfx->IsHeadless() || (!m_onscreen_ui && !m_xfb_entry))
    return;
"""
new = """#ifdef __LIBRETRO__
  // Gameshell 补丁：软件渲染在 libretro 下没有 GL 上下文（IsHeadless 为真），
  // 但帧必须经由 SWGfx::ShowImage → video_cb 交出去，这里不能直接 return。
  if (!m_onscreen_ui && !m_xfb_entry)
    return;
#else
  if (g_gfx->IsHeadless() || (!m_onscreen_ui && !m_xfb_entry))
    return;
#endif
"""
assert old in text, "找不到 Presenter::Present 的 headless 早退"
text = text.replace(old, new, 1)

path.write_text(text)
print("已让 libretro 软件渲染在 headless 下继续出帧：", path)

# ---------------------------------------------------------------- 软件渲染路径补后端初始化
# 上游在 __LIBRETRO__ 下把 Core::GetInitializedVideoGuard 的 init_video 改成直接 return true，
# 于是 g_video_backend->Initialize() 永远不执行 → VideoBackendBase::InitializeShared 不执行 →
# g_presenter / g_vertex_manager / g_texture_cache / g_shader_cache 全是 nullptr。
# 硬件渲染靠「SET_HW_RENDER → 前端回调 ContextReset」补上这一步，而软件渲染根本不走
# SET_HW_RENDER（见 DolphinLibretro/Video.cpp 的 Init），所以首帧 SWGfx 一碰 presenter 就崩。
# 修法：在起模拟线程之前自己跑一遍 Video_InitializeBackend()；headless 窗口补丁保证
# 没有 GL 上下文也能初始化成功。
path = root / "Source/Core/DolphinLibretro/Main.cpp"
text = path.read_text()

old = """    WindowSystemInfo wsi(WindowSystemType::Libretro, nullptr, nullptr, nullptr);
    if (system.IsDualCoreMode())
"""
new = """    WindowSystemInfo wsi(WindowSystemType::Libretro, nullptr, nullptr, nullptr);

    // Gameshell 补丁：软件渲染路径补一次后端初始化（上游在 __LIBRETRO__ 下从不做）。
    // 顺序很关键：必须在本线程里、起模拟线程之前完成初始化，并当场换成带 video_cb 的
    // Libretro::Video::SWGfx —— 上游原本是「等模拟线程跑起来后再 g_gfx.reset()」，
    // 那时 GPU 线程已经在用这个对象了，换成真对象之后会变成 use-after-free。
    if (!g_gfx && Config::Get(Config::MAIN_GFX_BACKEND) == "Software Renderer")
    {
      if (!Libretro::Video::Video_InitializeBackend())
      {
        ERROR_LOG_FMT(VIDEO, "Libretro: software video backend init failed");
      }
      else
      {
        g_gfx.reset();
        g_gfx = std::make_unique<Libretro::Video::SWGfx>();
      }
    }

    if (system.IsDualCoreMode())
"""
assert old in text, "找不到 retro_run 里起模拟线程的位置"
text = text.replace(old, new, 1)

old = """    if(Config::Get(Config::MAIN_GFX_BACKEND) == "Software Renderer")
    {
      g_gfx.reset();
      g_gfx = std::make_unique<Libretro::Video::SWGfx>();
    }
    else if (Config::Get(Config::MAIN_GFX_BACKEND) == "Null")
"""
new = """    // Gameshell 补丁：Software 分支已挪到起模拟线程之前（见上方），这里只剩 Null。
    if(Config::Get(Config::MAIN_GFX_BACKEND) == "Null")
"""
assert old in text, "找不到软件渲染 / Null 的 g_gfx 替换段"
text = text.replace(old, new, 1)

path.write_text(text)
print("已在软件渲染路径补后端初始化：", path)

# ---------------------------------------------------------------- GBA 配置项编译守卫
path = root / "Source/Core/DolphinLibretro/Boot.cpp"
text = path.read_text()

old = """  if (Libretro::GBPlayer_active)
  {
    Config::SetBase(Config::MAIN_GBA_ROM_PATHS[Config::GBPLAYER_GBA_INDEX], Libretro::GBPlayer_rom_path);
"""
new = """#ifdef HAS_LIBMGBA
  // Gameshell 补丁：上面这些 Config:: 项在 MainSettings.h 里被 #ifdef HAS_LIBMGBA 包着，
  // 我们按 USE_MGBA=OFF 编译（GBA 由宿主的 mGBA 核心负责，不需要 Dolphin 内置一份），
  // 上游这里没加同样的守卫，会直接编译失败。
  if (Libretro::GBPlayer_active)
  {
    Config::SetBase(Config::MAIN_GBA_ROM_PATHS[Config::GBPLAYER_GBA_INDEX], Libretro::GBPlayer_rom_path);
"""
assert old in text, "找不到 Boot.cpp 的 GBPlayer 配置写入段"
text = text.replace(old, new, 1)

old = """  else
  {
    Config::SetBase(Config::MAIN_GBA_ROM_PATHS[Config::GBPLAYER_GBA_INDEX], std::string{});
  }
"""
new = old + """#endif
"""
assert old in text, "找不到 Boot.cpp 的 GBPlayer 配置清空段"
text = text.replace(old, new, 1)

path.write_text(text)
print("已给 Boot.cpp 的 GBA 配置项补上 HAS_LIBMGBA 守卫：", path)
PY
	then
		log "Dolphin 补丁段没对上（上游可能改过），详情见 ${configure_log}"
		return 1
	fi

	# CMAKE_SYSTEM_PROCESSOR 必须显式给 arm64：Dolphin 顶层 CMake 用它判断「这是不是
	# 它认识的 64 位架构」，iOS 交叉编译时该变量默认是空的，会直接 fatal
	# （"You're building on an unsupported platform: '' with 8-byte pointers"）。
	log "配置 Dolphin（交叉编译到 iOS arm64，日志：${configure_log}）"
	cmake -S "$src_dir" -B "$build_dir" \
		-DCMAKE_SYSTEM_NAME=iOS \
		-DCMAKE_OSX_SYSROOT="$SDK_NAME" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_SYSTEM_PROCESSOR=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
		-DCMAKE_C_COMPILER="$CC" \
		-DCMAKE_CXX_COMPILER="$CXX" \
		-DCMAKE_OBJC_COMPILER="$CC" \
		-DCMAKE_OBJCXX_COMPILER="$CXX" \
		-DCMAKE_ASM_COMPILER="$CC" \
		-DCMAKE_C_COMPILER_WORKS=1 \
		-DCMAKE_CXX_COMPILER_WORKS=1 \
		-DCMAKE_BUILD_TYPE=Release \
		-DLIBRETRO=ON \
		-DENABLE_QT=OFF \
		-DENABLE_TESTS=OFF \
		-DENABLE_LTO=OFF \
		-DENABLE_VULKAN=OFF \
		-DENABLE_SDL=OFF \
		-DENABLE_CUBEB=OFF \
		-DENABLE_LLVM=OFF \
		-DENABLE_ANALYTICS=OFF \
		-DENABLE_CLI_TOOL=OFF \
		-DENABLE_AUTOUPDATE=OFF \
		-DENCODE_FRAMEDUMPS=OFF \
		-DUSE_MGBA=OFF \
		-DUSE_UPNP=OFF \
		-DUSE_DISCORD_PRESENCE=OFF \
		-DUSE_RETRO_ACHIEVEMENTS=OFF \
		-DMACOS_CODE_SIGNING=OFF \
		-DCMAKE_C_FLAGS="-include $prefix_header" \
		-DCMAKE_CXX_FLAGS="-include $prefix_header" \
		>> "$configure_log" 2>&1
	if [ $? -ne 0 ]; then
		log "Dolphin 的 cmake 配置失败，详情见 ${configure_log}"
		return 1
	fi

	log "开始编译 Dolphin libretro 核心（日志：${build_log}，这一步很重，会很久）"
	cmake --build "$build_dir" --target dolphin_libretro --parallel 4 >> "$build_log" 2>&1
	if [ $? -ne 0 ]; then
		log "Dolphin 编译失败，详情见 ${build_log}"
		return 1
	fi

	# 合并所有静态库：dolphin_libretro.a 只含自身目标文件，
	# core / video / audio / Externals 下的依赖 .a 不会自动并进去。
	local -a libs
	libs=()
	while IFS= read -r line; do
		libs+=("$line")
	done < <(find "$build_dir" -name '*.a' -type f)
	if [ "${#libs[@]}" -eq 0 ]; then
		log "编译成功但没找到任何 .a，详情见 ${build_log}"
		return 1
	fi

	local libtool
	libtool="$(xcrun --find libtool 2>/dev/null || command -v libtool || true)"
	if [ -z "$libtool" ]; then
		log "找不到 libtool，无法合并 Dolphin 静态库"
		return 1
	fi

	log "合并 ${#libs[@]} 个静态库为 libdolphin.a（日志：${configure_log}）"
	rm -f "$OUT_DIR/libdolphin.a"
	if ! "$libtool" -static -o "$OUT_DIR/libdolphin.a" "${libs[@]}" >> "$configure_log" 2>&1; then
		log "libtool 合并失败，详情见 ${configure_log}"
		return 1
	fi
	if [ ! -s "$OUT_DIR/libdolphin.a" ]; then
		log "libtool 没有产出 libdolphin.a，详情见 ${configure_log}"
		return 1
	fi

	log "完成：${OUT_DIR}/libdolphin.a（$(du -h "$OUT_DIR/libdolphin.a" | cut -f1)）"

	# 产物留下，源码树与中间产物删掉（体量大，别给后续 Xcode 构建留磁盘压力）
	rm -rf "$src_dir" "$build_dir"
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

# ---------------------------------------------------------------- Azahar（Nintendo 3DS）
# 上游 Azahar（Citra 后继，GPL-2.0），按给 RetroArch 用的 src/citra_libretro/ 前端形态编，
# 宿主侧走 libretro 接口（见 Sources/Core/GSAzaharCore.mm）。
#   · 与其它核心不同：源码不在 Vendor/，由本脚本 git clone --recurse-submodules 现取现编
#     （它递归子模块近 20 个，全量入库太重），构建完即删。因此这一步需要网络。
#   · 渲染走软件渲染（软件光栅器 + CPU 帧缓冲），与宿主「只要一帧 RGBA8888」的架构匹配。
#   · iOS 上核心把 use_cpu_jit 硬写成 false 走解释器，所以 3DS 不需要 JIT（宿主 requiresJIT=NO）。
#   · 默认布局（上屏叠下屏）合成后 400x480，宿主缓冲上限 1024x512 足够。
#   · 细节与已验参数全部写在 build_azahar_core() 的注释里（与探路工作流一致）。
if build_azahar_core; then
	have_azahar=1
fi

# ---------------------------------------------------------------- Dolphin（Wii / GameCube）
# 上游 libretro/dolphin 的 libretro 形态（GPL-2.0+），宿主侧走 libretro 接口
# （见 Sources/Core/GSWiiCore.mm）。
#   · 源码不入库，构建时 git clone --depth 1 现取现编，构建完即删。因此这一步需要网络。
#   · 渲染：软件光栅器 + CPU 帧缓冲；上游仍会尝试建 GL 窗口，构建脚本会打「headless」补丁
#     让它在没有 GL 上下文时照样交付 video_cb 帧（见 build_dolphin_core() 注释）。
#   · CPU：JITARM64 与 CachedInterpreter 都编进库里，运行时由核心按可执行内存探测结果选择；
#     宿主再按 GSJIT 探测结果答 dolphin_cpu_core，「有 JIT 就一定用 JIT」。
if build_dolphin_core; then
	have_dolphin=1
fi

# ---------------------------------------------------------------- 汇总
built=""
[ "$have_mgba" -eq 1 ] && built="${built}mGBA（GBA/GB/GBC）、"
[ "$have_nestopia" -eq 1 ] && built="${built}Nestopia（NES）、"
[ "$have_mesens" -eq 1 ] && built="${built}Mesen-S（SNES）、"
[ "$have_melonds" -eq 1 ] && built="${built}melonDS（NDS/DSi）、"
[ "$have_azahar" -eq 1 ] && built="${built}Azahar（3DS）、"
[ "$have_dolphin" -eq 1 ] && built="${built}Dolphin（Wii/GameCube）、"
if [ -z "$built" ]; then
	summary="本次没有核心编译成功（见各 *-configure.log / *-build.log）"
else
	summary="${built}已接入"
fi

finalize
exit 0
