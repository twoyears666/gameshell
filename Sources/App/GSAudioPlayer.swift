//
//  GSAudioPlayer.swift
//  Gameshell
//
//  把模拟器核心输出的音频喂给 AVAudioEngine。
//
//  核心给的是交错立体声 int16（GSEmulatorCoreDelegate 的 count = int16 元素总数），
//  AVAudioSourceNode 也能直接吃 int16 交错格式，所以这里不存在任何格式转换 ——
//  音频线程里只是把环形缓冲里的样本读出来，读不够时 readAudio(into:count:) 会补 0。
//
//  音频起不来不影响画面：start() 失败就整体停掉，游戏照常能玩。
//

import Foundation

#if os(iOS)

import AVFoundation

final class GSAudioPlayer {

    private let session: GSEmulatorSession
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    init(session: GSEmulatorSession) {
        self.session = session
    }

    /// 按核心当前采样率起音频。采样率拿不到（核心没载入 ROM）时直接不动。
    func start() {
        guard sourceNode == nil else { return }

        let sampleRate = session.audioSampleRate
        guard sampleRate > 0 else { return }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: sampleRate,
                                         channels: 2,
                                         interleaved: true) else { return }

        let node = AVAudioSourceNode(format: format) { [session] _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            // 交错立体声：每帧 2 个 int16
            let needed = Int(frameCount) * 2
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let capacity = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = data.assumingMemoryBound(to: Int16.self)
                _ = session.readAudio(into: samples, count: min(needed, capacity))
            }
            return noErr
        }

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
            try engine.start()
            sourceNode = node
        } catch {
            // 起不来就整体回退，别留下半启动的引擎
            engine.stop()
            engine.detach(node)
            sourceNode = nil
        }
    }

    func stop() {
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    deinit {
        stop()
    }
}

#endif
