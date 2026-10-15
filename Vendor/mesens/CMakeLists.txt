#
# Vendor/mesens/CMakeLists.txt
#
# 把 Mesen-S（SNES 模拟器，GPL-3.0）编成一份 arm64 静态库，供 Gameshell 链接。
#
# 为什么不用它自带的 makefile：
#   Libretro/Makefile 是给 RetroArch 的构建系统用的，直接产 .dylib / .so。
#   我们这边（见 Scripts/build_cores.sh）统一走 CMake 交叉编译成静态库 —— 因为
#   iOS 15 + A12 起系统封禁了 dynamic-codesigning，运行时 dlopen 未签名动态库会被拒，
#   核心只能静态链接进主二进制。
#
# 源清单严格照抄上游 Libretro/Makefile.common（SOURCES_C / SOURCES_CXX），
# 一个不多一个不少 —— 多编会拉进只给 Windows/UI 用的东西，少编会缺符号。
#
# 关键宏：LIBRETRO
#   上游整套代码用 #ifdef LIBRETRO / #ifndef LIBRETRO 切掉「桌面版才有」的部分：
#     · Core/ScriptHost.cpp 不再引用 Lua（我们不带 Lua，也不需要）
#     · Core/VideoDecoder.cpp / VideoRenderer.cpp 不再起独立解码/渲染线程
#       （改成 UpdateFrameSync 在被调用的线程里同步解码 —— 宿主 retro_run 逐帧驱动的前提）
#     · Utilities/Socket.cpp 的联网代码被切掉（iOS 上没意义）
#   不定义它的话，要么编不过，要么会起线程、行为和「同步逐帧」的宿主架构冲突。
#
# 只编 C++11/14 标准：上游 Makefile 用的是 -std=c++14。
#
# 不需要的东西（已从源清单里排除，也没有入库）：
#   · Lua/（脚本调试器，被 LIBRETRO 切掉）
#   · Dependencies/（只有 Windows 用的 DirectXTK .lib）
#   · UI/ Windows/ Linux/ InteropDLL/ Docs/ 等桌面前端
#
cmake_minimum_required(VERSION 3.15)
project(mesens CXX C)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# 上游用的是 -std=c++14（非 gnu 变体），但 gnu++14 对老代码更宽容，保持默认开启扩展。
set(CMAKE_CXX_EXTENSIONS ON)
set(CMAKE_C_STANDARD 11)

set(MESENS_DIR ${CMAKE_CURRENT_SOURCE_DIR})

# ------------------------------------------------------------------ 源清单
# 与 Libretro/Makefile.common 的 SOURCES_C 一致
set(MESENS_C_SOURCES
    ${MESENS_DIR}/SevenZip/7zAlloc.c
    ${MESENS_DIR}/SevenZip/7zArcIn.c
    ${MESENS_DIR}/SevenZip/7zBuf.c
    ${MESENS_DIR}/SevenZip/7zCrc.c
    ${MESENS_DIR}/SevenZip/7zCrcOpt.c
    ${MESENS_DIR}/SevenZip/7zDec.c
    ${MESENS_DIR}/SevenZip/7zFile.c
    ${MESENS_DIR}/SevenZip/7zMemBuffer.c
    ${MESENS_DIR}/SevenZip/7zStream.c
    ${MESENS_DIR}/SevenZip/Bcj2.c
    ${MESENS_DIR}/SevenZip/Bra.c
    ${MESENS_DIR}/SevenZip/Bra86.c
    ${MESENS_DIR}/SevenZip/BraIA64.c
    ${MESENS_DIR}/SevenZip/CpuArch.c
    ${MESENS_DIR}/SevenZip/Delta.c
    ${MESENS_DIR}/SevenZip/Lzma2Dec.c
    ${MESENS_DIR}/SevenZip/LzmaDec.c
    ${MESENS_DIR}/SevenZip/Ppmd7.c
    ${MESENS_DIR}/SevenZip/Ppmd7Dec.c
    ${MESENS_DIR}/SevenZip/Precomp.c
)

# 与 Libretro/Makefile.common 的 SOURCES_CXX 一致
set(MESENS_CXX_SOURCES
    ${MESENS_DIR}/Libretro/libretro.cpp

    ${MESENS_DIR}/Core/AluMulDiv.cpp
    ${MESENS_DIR}/Core/Assembler.cpp
    ${MESENS_DIR}/Core/BaseCartridge.cpp
    ${MESENS_DIR}/Core/BaseControlDevice.cpp
    ${MESENS_DIR}/Core/BaseRenderer.cpp
    ${MESENS_DIR}/Core/BaseSoundManager.cpp
    ${MESENS_DIR}/Core/BaseVideoFilter.cpp
    ${MESENS_DIR}/Core/BatteryManager.cpp
    ${MESENS_DIR}/Core/Breakpoint.cpp
    ${MESENS_DIR}/Core/BreakpointManager.cpp
    ${MESENS_DIR}/Core/BsxCart.cpp
    ${MESENS_DIR}/Core/BsxMemoryPack.cpp
    ${MESENS_DIR}/Core/BsxSatellaview.cpp
    ${MESENS_DIR}/Core/BsxStream.cpp
    ${MESENS_DIR}/Core/CallstackManager.cpp
    ${MESENS_DIR}/Core/CheatManager.cpp
    ${MESENS_DIR}/Core/CodeDataLogger.cpp
    ${MESENS_DIR}/Core/Console.cpp
    ${MESENS_DIR}/Core/ConsoleLock.cpp
    ${MESENS_DIR}/Core/ControlManager.cpp
    ${MESENS_DIR}/Core/Cpu.cpp
    ${MESENS_DIR}/Core/CpuDebugger.cpp
    ${MESENS_DIR}/Core/CpuDisUtils.cpp
    ${MESENS_DIR}/Core/Cx4.cpp
    ${MESENS_DIR}/Core/Cx4.Instructions.cpp
    ${MESENS_DIR}/Core/Cx4DisUtils.cpp
    ${MESENS_DIR}/Core/Cx4Debugger.cpp
    ${MESENS_DIR}/Core/Debugger.cpp
    ${MESENS_DIR}/Core/DebugHud.cpp
    ${MESENS_DIR}/Core/DebugStats.cpp
    ${MESENS_DIR}/Core/DefaultVideoFilter.cpp
    ${MESENS_DIR}/Core/Disassembler.cpp
    ${MESENS_DIR}/Core/DisassemblyInfo.cpp
    ${MESENS_DIR}/Core/DmaController.cpp
    ${MESENS_DIR}/Core/EmuSettings.cpp
    ${MESENS_DIR}/Core/EventManager.cpp
    ${MESENS_DIR}/Core/ExpressionEvaluator.cpp
    ${MESENS_DIR}/Core/GameClient.cpp
    ${MESENS_DIR}/Core/GameClientConnection.cpp
    ${MESENS_DIR}/Core/GameConnection.cpp
    ${MESENS_DIR}/Core/GameServer.cpp
    ${MESENS_DIR}/Core/GameServerConnection.cpp
    ${MESENS_DIR}/Core/Gameboy.cpp
    ${MESENS_DIR}/Core/GbAssembler.cpp
    ${MESENS_DIR}/Core/GbCpu.cpp
    ${MESENS_DIR}/Core/GbDmaController.cpp
    ${MESENS_DIR}/Core/GbPpu.cpp
    ${MESENS_DIR}/Core/GbApu.cpp
    ${MESENS_DIR}/Core/GbNoiseChannel.cpp
    ${MESENS_DIR}/Core/GbSquareChannel.cpp
    ${MESENS_DIR}/Core/GbWaveChannel.cpp
    ${MESENS_DIR}/Core/GbTimer.cpp
    ${MESENS_DIR}/Core/GbMemoryManager.cpp
    ${MESENS_DIR}/Core/GbDebugger.cpp
    ${MESENS_DIR}/Core/GbEventManager.cpp
    ${MESENS_DIR}/Core/GameboyDisUtils.cpp
    ${MESENS_DIR}/Core/Gsu.cpp
    ${MESENS_DIR}/Core/Gsu.Instructions.cpp
    ${MESENS_DIR}/Core/GsuDisUtils.cpp
    ${MESENS_DIR}/Core/GsuDebugger.cpp
    ${MESENS_DIR}/Core/InputHud.cpp
    ${MESENS_DIR}/Core/InternalRegisters.cpp
    ${MESENS_DIR}/Core/KeyManager.cpp
    ${MESENS_DIR}/Core/LabelManager.cpp
    ${MESENS_DIR}/Core/MemoryAccessCounter.cpp
    ${MESENS_DIR}/Core/MemoryDumper.cpp
    ${MESENS_DIR}/Core/MemoryManager.cpp
    ${MESENS_DIR}/Core/MemoryMappings.cpp
    ${MESENS_DIR}/Core/MesenMovie.cpp
    ${MESENS_DIR}/Core/MessageManager.cpp
    ${MESENS_DIR}/Core/MovieManager.cpp
    ${MESENS_DIR}/Core/MovieRecorder.cpp
    ${MESENS_DIR}/Core/Msu1.cpp
    ${MESENS_DIR}/Core/Multitap.cpp
    ${MESENS_DIR}/Core/NecDsp.cpp
    ${MESENS_DIR}/Core/NecDspDebugger.cpp
    ${MESENS_DIR}/Core/NecDspDisUtils.cpp
    ${MESENS_DIR}/Core/NotificationManager.cpp
    ${MESENS_DIR}/Core/NtscFilter.cpp
    ${MESENS_DIR}/Core/Obc1.cpp
    ${MESENS_DIR}/Core/PcmReader.cpp
    ${MESENS_DIR}/Core/Ppu.cpp
    ${MESENS_DIR}/Core/PpuTools.cpp
    ${MESENS_DIR}/Core/Profiler.cpp
    ${MESENS_DIR}/Core/RegisterHandlerB.cpp
    ${MESENS_DIR}/Core/RewindData.cpp
    ${MESENS_DIR}/Core/RewindManager.cpp
    ${MESENS_DIR}/Core/Rtc4513.cpp
    ${MESENS_DIR}/Core/SaveStateManager.cpp
    ${MESENS_DIR}/Core/Sa1.cpp
    ${MESENS_DIR}/Core/Sa1Cpu.cpp
    ${MESENS_DIR}/Core/ScaleFilter.cpp
    ${MESENS_DIR}/Core/ScriptHost.cpp
    ${MESENS_DIR}/Core/ScriptingContext.cpp
    ${MESENS_DIR}/Core/ScriptManager.cpp
    ${MESENS_DIR}/Core/Sdd1Decomp.cpp
    ${MESENS_DIR}/Core/Sdd1.cpp
    ${MESENS_DIR}/Core/Sdd1Mmc.cpp
    ${MESENS_DIR}/Core/ShortcutKeyHandler.cpp
    ${MESENS_DIR}/Core/SnesController.cpp
    ${MESENS_DIR}/Core/SoundMixer.cpp
    ${MESENS_DIR}/Core/SoundResampler.cpp
    ${MESENS_DIR}/Core/Spc.cpp
    ${MESENS_DIR}/Core/Spc.Instructions.cpp
    ${MESENS_DIR}/Core/SpcDebugger.cpp
    ${MESENS_DIR}/Core/SpcDisUtils.cpp
    ${MESENS_DIR}/Core/SpcHud.cpp
    ${MESENS_DIR}/Core/SPC_DSP.cpp
    ${MESENS_DIR}/Core/SPC_Filter.cpp
    ${MESENS_DIR}/Core/Spc7110.cpp
    ${MESENS_DIR}/Core/Spc7110Decomp.cpp
    ${MESENS_DIR}/Core/SuperGameboy.cpp
    ${MESENS_DIR}/Core/stdafx.cpp
    ${MESENS_DIR}/Core/TraceLogger.cpp
    ${MESENS_DIR}/Core/VideoDecoder.cpp
    ${MESENS_DIR}/Core/VideoRenderer.cpp
    ${MESENS_DIR}/Core/WaveRecorder.cpp

    ${MESENS_DIR}/Utilities/ArchiveReader.cpp
    ${MESENS_DIR}/Utilities/AutoResetEvent.cpp
    ${MESENS_DIR}/Utilities/AviRecorder.cpp
    ${MESENS_DIR}/Utilities/AviWriter.cpp
    ${MESENS_DIR}/Utilities/blip_buf.cpp
    ${MESENS_DIR}/Utilities/BpsPatcher.cpp
    ${MESENS_DIR}/Utilities/CamstudioCodec.cpp
    ${MESENS_DIR}/Utilities/CRC32.cpp
    ${MESENS_DIR}/Utilities/Equalizer.cpp
    ${MESENS_DIR}/Utilities/FolderUtilities.cpp
    ${MESENS_DIR}/Utilities/GifRecorder.cpp
    ${MESENS_DIR}/Utilities/HermiteResampler.cpp
    ${MESENS_DIR}/Utilities/HexUtilities.cpp
    ${MESENS_DIR}/Utilities/IpsPatcher.cpp
    ${MESENS_DIR}/Utilities/md5.cpp
    ${MESENS_DIR}/Utilities/miniz.cpp
    ${MESENS_DIR}/Utilities/PlatformUtilities.cpp
    ${MESENS_DIR}/Utilities/PNGHelper.cpp
    ${MESENS_DIR}/Utilities/Serializer.cpp
    ${MESENS_DIR}/Utilities/sha1.cpp
    ${MESENS_DIR}/Utilities/SimpleLock.cpp
    ${MESENS_DIR}/Utilities/snes_ntsc.cpp
    ${MESENS_DIR}/Utilities/Socket.cpp
    ${MESENS_DIR}/Utilities/stb_vorbis.cpp
    ${MESENS_DIR}/Utilities/stdafx.cpp
    ${MESENS_DIR}/Utilities/SZReader.cpp
    ${MESENS_DIR}/Utilities/Timer.cpp
    ${MESENS_DIR}/Utilities/UpsPatcher.cpp
    ${MESENS_DIR}/Utilities/UTF8Util.cpp
    ${MESENS_DIR}/Utilities/VirtualFile.cpp
    ${MESENS_DIR}/Utilities/ZipReader.cpp
    ${MESENS_DIR}/Utilities/ZipWriter.cpp
    ${MESENS_DIR}/Utilities/ZmbvCodec.cpp

    ${MESENS_DIR}/Utilities/HQX/hq2x.cpp
    ${MESENS_DIR}/Utilities/HQX/hq3x.cpp
    ${MESENS_DIR}/Utilities/HQX/hq4x.cpp
    ${MESENS_DIR}/Utilities/HQX/init.cpp

    ${MESENS_DIR}/Utilities/KreedSaiEagle/2xSai.cpp
    ${MESENS_DIR}/Utilities/KreedSaiEagle/Super2xSai.cpp
    ${MESENS_DIR}/Utilities/KreedSaiEagle/SuperEagle.cpp

    ${MESENS_DIR}/Utilities/Scale2x/scale2x.cpp
    ${MESENS_DIR}/Utilities/Scale2x/scale3x.cpp
    ${MESENS_DIR}/Utilities/Scale2x/scalebit.cpp

    ${MESENS_DIR}/Utilities/xBRZ/xbrz.cpp
)

add_library(mesens STATIC ${MESENS_C_SOURCES} ${MESENS_CXX_SOURCES})
set_target_properties(mesens PROPERTIES OUTPUT_NAME mesens)

# 上游整套代码用的是同目录 / ../ 相对 include，本身不需要额外 -I；
# 这里补上只是让「万一某个文件写的是 <Core/...>」也能找到。
target_include_directories(mesens PRIVATE
    ${MESENS_DIR}
    ${MESENS_DIR}/Core
    ${MESENS_DIR}/Utilities
    ${MESENS_DIR}/SevenZip
    ${MESENS_DIR}/Libretro
)

# LIBRETRO 是必须的：切掉 Lua、独立解码/渲染线程、联网代码（见文件头说明）
target_compile_definitions(mesens PRIVATE LIBRETRO)

# 上游 -Wall；关掉两类在 2019 年老代码上必然刷屏、且与本项目无关的告警
target_compile_options(mesens PRIVATE
    -Wall
    -Wno-unused-variable
    -Wno-unused-but-set-variable
    -Wno-unused-function
    -Wno-unused-private-field
    -Wno-invalid-offsetof
)
