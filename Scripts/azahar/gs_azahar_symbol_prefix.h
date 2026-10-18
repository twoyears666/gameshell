//
//  gs_azahar_symbol_prefix.h
//  Gameshell 给 Azahar（libretro 形态）打的「入口点符号前缀」补丁。
//
//  为什么需要它：
//  本 App 的主二进制里已经静态链接了两个 libretro 核心 —— Mesen-S（SNES）与
//  melonDS（NDS），现在再加 Azahar（3DS）。三者的「核心侧入口点」
//  （retro_init / retro_run / retro_load_game …）都是 extern "C" 符号，名字一模一样。
//  静态库按「谁先解析掉未定义符号」选成员：名字重复时，链接器要么让胶水拿到别的核心
//  的实现（静默跑错核心），要么报 duplicate symbol。两种结局都不能接受。
//
//  做法：在编译 Azahar 的 citra_libretro.cpp / environment.cpp 之前，先把这 25 个入口点
//  重命名成 gsazh_ 前缀。同一个翻译单元里 libretro.h 对这些入口点的「声明」也会被宏
//  一并改掉，所以「声明 ↔ 定义」依旧一致，只是对外的符号名变了。
//
//  与 melonDS 那份（Vendor/melonds/src/libretro/gs_symbol_prefix.h）的区别：
//  Azahar 把入口点分散在两个 .cpp 里 —— citra_libretro.cpp（init/run/load…）与
//  environment.cpp（get_system_info / set_environment / set_* / get_system_av_info…），
//  所以两处都必须 include 本文件，且都必须在各自的 libretro.h 之前。
//
//  用法（三处必须同时 include 本文件，且都必须在 libretro.h 之前）：
//    1) <azahar>/src/citra_libretro/citra_libretro.cpp —— 让核心自身的定义改名；
//    2) <azahar>/src/citra_libretro/environment.cpp   —— 另一批入口点的定义改名；
//    3) Sources/Core/GSAzaharCore.mm                  —— 让胶水的调用改名。
//  构建时由 Scripts/build_cores.sh 把本文件复制进 Azahar 源码树并插入 include。
//  新增入口点时只维护下面这一份列表。
//
//  注意：这里只重命名「核心侧入口点」。前端回调（retro_environment_t /
//  retro_video_refresh_t 等）是 typedef，不是同名标识符，不受影响；
//  RETRO_ENVIRONMENT_* / RETRO_DEVICE_* 这类枚举也一样不受影响。
//

#ifndef GS_AZAHAR_SYMBOL_PREFIX_H
#define GS_AZAHAR_SYMBOL_PREFIX_H

#define retro_init                         gsazh_retro_init
#define retro_deinit                       gsazh_retro_deinit
#define retro_api_version                  gsazh_retro_api_version
#define retro_get_system_info              gsazh_retro_get_system_info
#define retro_get_system_av_info           gsazh_retro_get_system_av_info
#define retro_set_environment              gsazh_retro_set_environment
#define retro_set_audio_sample             gsazh_retro_set_audio_sample
#define retro_set_audio_sample_batch       gsazh_retro_set_audio_sample_batch
#define retro_set_input_poll               gsazh_retro_set_input_poll
#define retro_set_input_state              gsazh_retro_set_input_state
#define retro_set_video_refresh            gsazh_retro_set_video_refresh
#define retro_set_controller_port_device   gsazh_retro_set_controller_port_device
#define retro_reset                        gsazh_retro_reset
#define retro_run                          gsazh_retro_run
#define retro_load_game                    gsazh_retro_load_game
#define retro_unload_game                  gsazh_retro_unload_game
#define retro_get_region                   gsazh_retro_get_region
#define retro_load_game_special            gsazh_retro_load_game_special
#define retro_serialize_size               gsazh_retro_serialize_size
#define retro_serialize                    gsazh_retro_serialize
#define retro_unserialize                  gsazh_retro_unserialize
#define retro_get_memory_data              gsazh_retro_get_memory_data
#define retro_get_memory_size              gsazh_retro_get_memory_size
#define retro_cheat_reset                  gsazh_retro_cheat_reset
#define retro_cheat_set                    gsazh_retro_cheat_set

#endif /* GS_AZAHAR_SYMBOL_PREFIX_H */
