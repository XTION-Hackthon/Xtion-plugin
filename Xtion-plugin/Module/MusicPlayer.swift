//
//  MusicPlayer.swift
//  Xtion-plugin
//
//  Created by Assistant on 10/11/25.
//

import Foundation
import AVFoundation

@MainActor
final class MusicPlayer {
    static let shared = MusicPlayer()
    private var player: AVAudioPlayer?
    private init() {}
    // 新增：系统音量控制器（在所有播放前解除静音）
    private let audioController = AudioController()
    
    /// 播放指定名称的 mp3 资源
    /// - Parameters:
    ///   - name: 文件名（不带扩展名）。例如 "1" 或 "1.买票"
    ///   - subdirectory: 资源所在的 bundle 子目录，默认 "Music"
    ///   - fileExtension: 扩展名，默认 "mp3"
    ///   - volume: 初始音量 0.0~1.0，默认 1.0
    ///   - loops: 循环次数，0 为不循环，-1 为无限循环
    func play(
        named name: String,
        subdirectory: String? = "Music",
        fileExtension: String = "mp3",
        volume: Float = 1.0,
        loops: Int = 0
    ) {
        // 播放前确保系统未静音
        audioController.unmuteIfMuted()
        
        // 优先在指定子目录查找，其次在根 bundle 查找
        let url = Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
        ?? Bundle.main.url(forResource: name, withExtension: fileExtension)
        guard let url else {
            print("[MusicPlayer] Resource not found: \(name).\(fileExtension) in \(subdirectory ?? ":root")")
            return
        }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.volume = volume
            newPlayer.numberOfLoops = loops
            newPlayer.prepareToPlay()
            newPlayer.play()
            self.player = newPlayer
        } catch {
            print("[MusicPlayer] Failed to play: \(error)")
        }
    }
    
    /// 停止播放
    func stop() {
        player?.stop()
        player = nil
    }
    
    /// 设置当前播放音量
    func setVolume(_ volume: Float) {
        player?.volume = max(0.0, min(1.0, volume))
    }
    
    /// 是否正在播放
    var isPlaying: Bool { player?.isPlaying ?? false }
}
