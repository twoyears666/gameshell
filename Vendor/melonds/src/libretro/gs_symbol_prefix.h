//
//  gs_symbol_prefix.h
//  Gameshell 给 melonDS（libretro 形态）打的「入口点符号前缀」补丁。
//
//  为什么需要它：
//  本 App 的主二进制里同时静态链接了两个 libretro 核心 —— Mesen-S（SNES）与
//  melonDS（NDS）。两者的「核心侧入口点」（retro_init / retro_run / retro_load_game …）
//  都是 extern "C" 符号，名字一模一样。静态库是按「谁先解析掉未定义符号」来选成员的：
//  一旦这些名字重复，链接器要么让 melonDS 的胶水拿到 Mesen-S 的实现（静默跑错核心，
//  连报错都没有），要么两边都被拉起来报 duplicate symbol。两种结局都不能接受。
//
//  做法：在编译 melonDS 的 libretro.cpp 之前先把这 25 个入口点重命名成 gsmds_ 前缀。
//  同一个翻译单元里 libretro.h 对这些入口点的「声明」也会被宏一并改掉，
//  所以「声明 ↔ 定义」依旧一致，只是对外的符号名变了。
//
//  用法（两处必须同时 include 本文件，且都必须在 libretro.h 之前）：
//    1) Vendor/melonds/src/libretro/libretro.cpp —— 让核心自身的定义改名；
//    2) Sources/Core/GSMelonDSCore.mm      —— 让胶水的调用改名。
//  新增入口点时只维护下面这一份列表。
//
//  注意：这里只重命名「核心侧入口点」。前端回调（retro_environment_t /
//  retro_video_refresh_t 等）是 typedef，不是同名标识符，不受影响；
//  RETRO_ENVIRONMENT_* / RETRO_DEVICE_* 这类枚举也一样不受影响。
//

#ifndef GS_MELONDS_SYMBOL_PREFIX_H
#define GS_MELONDS_SYMBOL_PREFIX_H

#define retro_init                         gsmds_retro_init
#define retro_deinit                       gsmds_retro_deinit
#define retro_api_version                  gsmds_retro_api_version
#define retro_get_system_info              gsmds_retro_get_system_info
#define retro_get_system_av_info           gsmds_retro_get_system_av_info
#define retro_set_environment              gsmds_retro_set_environment
#define retro_set_audio_sample             gsmds_retro_set_audio_sample
#define retro_set_audio_sample_batch       gsmds_retro_set_audio_sample_batch
#define retro_set_input_poll               gsmds_retro_set_input_poll
#define retro_set_input_state              gsmds_retro_set_input_state
#define retro_set_video_refresh            gsmds_retro_set_video_refresh
#define retro_set_controller_port_device   gsmds_retro_set_controller_port_device
#define retro_reset                        gsmds_retro_reset
#define retro_run                          gsmds_retro_run
#define retro_load_game                    gsmds_retro_load_game
#define retro_unload_game                  gsmds_retro_unload_game
#define retro_get_region                   gsmds_retro_get_region
#define retro_load_game_special            gsmds_retro_load_game_special
#define retro_serialize_size               gsmds_retro_serialize_size
#define retro_serialize                    gsmds_retro_serialize
#define retro_unserialize                  gsmds_retro_unserialize
#define retro_get_memory_data              gsmds_retro_get_memory_data
#define retro_get_memory_size              gsmds_retro_get_memory_size
#define retro_cheat_reset                  gsmds_retro_cheat_reset
#define retro_cheat_set                    gsmds_retro_cheat_set

#endif /* GS_MELONDS_SYMBOL_PREFIX_H */
