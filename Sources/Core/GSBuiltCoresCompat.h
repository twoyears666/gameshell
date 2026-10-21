//
//  GSBuiltCoresCompat.h
//  Gameshell
//
//  编译期得知「哪些核心这次真的编进了主二进制」。
//
//  核心由 Scripts/build_cores.sh 在 Xcode 的 pre-build 阶段交叉编译成静态库，
//  同时把构建结果写成 GSBuiltCores.h 放到 build/cores/runtime（该目录在
//  HEADER_SEARCH_PATHS 里）。没跑过脚本时（例如刚 clone 下来直接用 Xcode 打开），
//  GSBuiltCores.h 不存在，下面所有 *_HAVE_* 一律回退成 0 —— 工程照常能编，
//  只是 UI 会如实显示「核心尚未接入」。
//

#ifndef GS_BUILT_CORES_COMPAT_H
#define GS_BUILT_CORES_COMPAT_H

#if __has_include("GSBuiltCores.h")
#import "GSBuiltCores.h"
#endif

#ifndef GS_HAVE_MGBA
#define GS_HAVE_MGBA 0
#endif

#ifndef GS_HAVE_NESTOPIA
#define GS_HAVE_NESTOPIA 0
#endif

#ifndef GS_HAVE_MESENS
#define GS_HAVE_MESENS 0
#endif

#ifndef GS_HAVE_MELONDS
#define GS_HAVE_MELONDS 0
#endif

#ifndef GS_HAVE_AZAHAR
#define GS_HAVE_AZAHAR 0
#endif

#ifndef GS_HAVE_DOLPHIN
#define GS_HAVE_DOLPHIN 0
#endif

#endif /* GS_BUILT_CORES_COMPAT_H */
