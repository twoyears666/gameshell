//
//  Gameshell-Bridging-Header.h
//  Swift 与 Objective-C 核心（GSGameManifest / GSGameLauncher / GSInputManager /
//  模拟器宿主层 GSSystem / GSROMLibrary / GSEmulator）之间的桥接。
//

#import "GSGameManifest.h"
#import "GSGameLauncher.h"
#import "GSInputManager.h"

// 模拟器 / ROM 相关（GSMGBACore.m 由主 target 直接编译，不给 Swift 暴露任何东西）
#import "GSSystem.h"
#import "GSROMLibrary.h"
#import "GSEmulator.h"
