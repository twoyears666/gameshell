//
//  CoverImage.swift
//  Gameshell
//
//  封面的「本地路径」加载：
//    · 清单里的 icon 与模拟器封面都可能写成「相对 Documents 的路径」
//      （"Icons/<id>.png" / "Covers/<系统>/<文件名>.png"），这里负责读成图片；
//    · 远程 http(s) 图片交给 GameCover 里的 AsyncImage；
//    · SF Symbol 名同样由 GameCover 兜底。
//
//  本地图片走一层进程内缓存，同一张图不会每次重读磁盘。
//

import SwiftUI
import Foundation

#if canImport(UIKit)
import UIKit
/// 平台图片类型：iOS = UIImage
typealias GSPlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
/// 平台图片类型：macOS = NSImage
typealias GSPlatformImage = NSImage
#endif

extension Image {
    /// 由平台图片（UIImage / NSImage）构建 SwiftUI Image
    static func gs(_ image: GSPlatformImage) -> Image {
        #if canImport(UIKit)
        return Image(uiImage: image)
        #else
        return Image(nsImage: image)
        #endif
    }
}

/// 「相对 Documents 的路径」→ 图片，带进程内缓存。
enum GSLocalImageStore {

    private static let cache = NSCache<NSString, GSPlatformImage>()

    /// 读取本地封面 / 图标；路径为空或文件缺失返回 nil
    static func image(forRelativePath path: String) -> GSPlatformImage? {
        guard !path.isEmpty else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let url = GSIconStore.absoluteURL(forRelativePath: path),
              let image = GSPlatformImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }

    /// 图标 / 封面被替换或删除后清掉缓存（下次读取重新从磁盘加载）
    static func invalidate() {
        cache.removeAllObjects()
    }
}

/// 显示一张本地图片；加载不出来时显示占位内容。
/// `relativePath` 变化（例如封面抓取完成后写入新路径）会自动重新加载。
struct LocalCoverImage<Placeholder: View>: View {

    let relativePath: String
    var contentMode: ContentMode = .fill
    private let placeholder: () -> Placeholder

    @State private var image: GSPlatformImage?

    init(relativePath: String,
         contentMode: ContentMode = .fill,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.relativePath = relativePath
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image.gs(image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .onAppear { reload() }
        .onChange(of: relativePath) { _ in reload() }
    }

    private func reload() {
        image = GSLocalImageStore.image(forRelativePath: relativePath)
    }
}
