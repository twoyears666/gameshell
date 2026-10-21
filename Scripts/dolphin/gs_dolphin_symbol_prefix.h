//
//  gs_dolphin_symbol_prefix.h
//  Gameshell 给 Dolphin（Wii / GameCube，libretro 形态）打的「入口点符号前缀」补丁。
//
//  为什么需要它：
//  主二进制里已经静态链接了 Mesen-S、melonDS 与 Azahar 三个 libretro 核心，现在再加
//  Dolphin。四者的「核心侧入口点」（retro_init / retro_run / retro_load_game …）
//  都是 extern "C" 符号，名字一模一样。静态库按「谁先解析掉未定义符号」选成员，重名时
//  要么静默跑错核心，要么 duplicate symbol —— 两种结局都不能接受。
//
//  做法：在编译 Dolphin 时用 `-include gs_dolphin_symbol_prefix.h` 把本头文件预包含进
//  每一个翻译单元（见 Scripts/build_cores.sh 的 build_dolphin_core），于是核心内的
//  「声明 ↔ 定义」一起改名，对外的符号名统一变成 gsdol_ 前缀。
//  之所以不用「逐文件插入 include」：Dolphin 的入口点分散在 Main.cpp / Boot.cpp /
//  Video.cpp / Audio.cpp / Input.cpp 五个翻译单元，而且还有别处调用它们，逐文件插
//  很容易漏；预包含能保证全树一致。
//
//  与 melonDS / Azahar 那两份前缀头的区别：
//  Dolphin 额外导出了两个分机种版本的选择器
//  （retro_set_controller_port_device_gc / _wii），这两个也必须一起改名。
//
//  用法（两处必须一致）：
//    1) Dolphin 编译期 —— 由构建脚本用 -include 预包含，核心自身的定义改名；
//    2) Sources/Core/GSWiiCore.mm —— 让宿主胶水的调用改名（手动 include）。
//
//  注意：这里只重命名「核心侧入口点」。前端回调（retro_environment_t /
//  retro_video_refresh_t 等）是 typedef，不是同名标识符，不受影响；
//  RETRO_ENVIRONMENT_* / RETRO_DEVICE_* 这类枚举也一样不受影响。
//

#ifndef GS_DOLPHIN_SYMBOL_PREFIX_H
#define GS_DOLPHIN_SYMBOL_PREFIX_H

#define retro_init                          gsdol_retro_init
#define retro_deinit                        gsdol_retro_deinit
#define retro_api_version                   gsdol_retro_api_version
#define retro_get_system_info               gsdol_retro_get_system_info
#define retro_get_system_av_info            gsdol_retro_get_system_av_info
#define retro_set_environment               gsdol_retro_set_environment
#define retro_set_audio_sample              gsdol_retro_set_audio_sample
#define retro_set_audio_sample_batch        gsdol_retro_set_audio_sample_batch
#define retro_set_input_poll                gsdol_retro_set_input_poll
#define retro_set_input_state               gsdol_retro_set_input_state
#define retro_set_video_refresh             gsdol_retro_set_video_refresh
#define retro_set_controller_port_device    gsdol_retro_set_controller_port_device
#define retro_reset                         gsdol_retro_reset
#define retro_run                           gsdol_retro_run
#define retro_load_game                     gsdol_retro_load_game
#define retro_unload_game                   gsdol_retro_unload_game
#define retro_get_region                    gsdol_retro_get_region
#define retro_load_game_special             gsdol_retro_load_game_special
#define retro_serialize_size                gsdol_retro_serialize_size
#define retro_serialize                     gsdol_retro_serialize
#define retro_unserialize                   gsdol_retro_unserialize
#define retro_get_memory_data               gsdol_retro_get_memory_data
#define retro_get_memory_size               gsdol_retro_get_memory_size
#define retro_cheat_reset                   gsdol_retro_cheat_reset
#define retro_cheat_set                     gsdol_retro_cheat_set

// Dolphin 独有：按机种分开的控制器选择器（Input.cpp 里同时导出了这两个）
#define retro_set_controller_port_device_gc   gsdol_retro_set_controller_port_device_gc
#define retro_set_controller_port_device_wii  gsdol_retro_set_controller_port_device_wii

#endif /* GS_DOLPHIN_SYMBOL_PREFIX_H */
