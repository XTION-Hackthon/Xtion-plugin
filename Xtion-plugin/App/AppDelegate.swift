//
//  AppDelegate.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import Cocoa
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = KeySpy()
    var statusItem: NSStatusItem!
    var floating: FloatingGifWindow?
    
    // 键盘触发逻辑：映射与管理器
    private var triggers: [String: ScreenEffect] = [
        "666": .glitchWave,
        "xtion": .heartbeatGlow,
        "dead": .snowStatic
    ]
    // 动态累积触发映射（键为需要累积的字符串，例如 "ghost"）
    private var cumulativeTriggers: [String: ScreenEffect] = [
        "ghost": .blockGlitch
    ]
    
    // 每个累积触发的当前进度（集合，包含已出现的字母）
    private var cumulativeProgress: [String: Set<Character>] = [:]
    
    // 动态 GIF 规则
    private enum GifSelector {
        case named(String)
        case random(folder: String?)
    }

    private var gifRules: [String: GifSelector] = [
        "ghost": .named("halloween")
    ]
    
    // 每词的冷却时间（秒）与最后触发时间
    private var cooldowns: [String: TimeInterval] = [
        "ghost": 3000 // 默认 ghost 5 分钟
    ]
    private var lastTriggeredAt: [String: Date] = [:]
    let effectManager = EffectManager()
    private var keyBufferObserver: NSObjectProtocol?
    private var triggersObserver: NSObjectProtocol?
    private var previousBuffer: String = ""
    
    // 支持 caseName 或中文 rawValue
    private func effectFromKey(_ key: String) -> ScreenEffect? {
        switch key {
        case "glitchWave", ScreenEffect.glitchWave.rawValue: return .glitchWave
        case "heartbeatGlow", ScreenEffect.heartbeatGlow.rawValue: return .heartbeatGlow
        case "snowStatic", ScreenEffect.snowStatic.rawValue: return .snowStatic
        case "blockGlitch", ScreenEffect.blockGlitch.rawValue: return .blockGlitch
        default: return nil
        }
    }
    
    private func loadTriggersFromDefaults() {
        if let jsonString = UserDefaults.standard.string(forKey: "XtionTriggers"),
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            var newMap: [String: ScreenEffect] = [:]
            for (pattern, effectKey) in dict {
                // 如果该 pattern 存在于累积触发中，则跳过后缀匹配，避免重复触发
                if cumulativeTriggers.keys.contains(pattern.lowercased()) { continue }
                if let effect = effectFromKey(effectKey) {
                    newMap[pattern] = effect
                }
            }
            if !newMap.isEmpty {
                triggers = newMap
            }
        }
    }
    
    // 从 UserDefaults 载入累积触发配置（key: XtionCumulativeTriggers，JSON: { "ghost": "blockGlitch", ... }）
    private func loadCumulativeTriggersFromDefaults() {
        if let jsonString = UserDefaults.standard.string(forKey: "XtionCumulativeTriggers"),
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            var newMap: [String: ScreenEffect] = [:]
            for (pattern, effectKey) in dict {
                if let effect = effectFromKey(effectKey) {
                    newMap[pattern.lowercased()] = effect
                }
            }
            if !newMap.isEmpty {
                cumulativeTriggers = newMap
                // 重置对应的累积进度
                cumulativeProgress = Dictionary(uniqueKeysWithValues: cumulativeTriggers.keys.map { ($0, Set<Character>()) })
            }
        } else {
            // 初始化默认的进度字典（确保包含默认 ghost）
            if cumulativeProgress.isEmpty {
                cumulativeProgress = Dictionary(uniqueKeysWithValues: cumulativeTriggers.keys.map { ($0, Set<Character>()) })
            }
        }
    }
    
    // 从 UserDefaults 载入 GIF 规则配置（key: XtionGifRules, JSON: { "ghost": "halloween", "xtion": "random", "dead": "random:GIFGroup" }）
    private func loadGifRulesFromDefaults() {
        if let jsonString = UserDefaults.standard.string(forKey: "XtionGifRules"),
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            var newMap: [String: GifSelector] = [:]
            for (pattern, value) in dict {
                let p = pattern.lowercased()
                let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if v.lowercased() == "random" {
                    newMap[p] = .random(folder: nil)
                } else if v.lowercased().hasPrefix("random:") {
                    let folder = String(v.dropFirst("random:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    newMap[p] = .random(folder: folder.isEmpty ? nil : folder)
                } else {
                    newMap[p] = .named(v)
                }
            }
            if !newMap.isEmpty {
                gifRules = newMap
            }
        }
    }
    
    // 从 UserDefaults 载入冷却配置（key: XtionCooldowns，JSON: { "ghost": 300, "xtion": 60 }，单位秒）
    private func loadCooldownsFromDefaults() {
        if let jsonString = UserDefaults.standard.string(forKey: "XtionCooldowns"),
           let data = jsonString.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var newMap: [String: TimeInterval] = [:]
            for (pattern, value) in dict {
                let p = pattern.lowercased()
                if let secs = value as? Double {
                    newMap[p] = secs
                } else if let secsInt = value as? Int {
                    newMap[p] = TimeInterval(secsInt)
                } else if let str = value as? String, let secs = Double(str) {
                    newMap[p] = secs
                }
            }
            if !newMap.isEmpty {
                cooldowns = newMap
            }
        }
    }
    
    private func canTrigger(pattern: String) -> Bool {
        let p = pattern.lowercased()
        guard let cd = cooldowns[p] else { return true }
        if let last = lastTriggeredAt[p] {
            return Date().timeIntervalSince(last) >= cd
        }
        return true
    }
    
    private func markTriggered(pattern: String) {
        lastTriggeredAt[pattern.lowercased()] = Date()
    }
    
    // 后缀匹配：返回匹配的模式与效果
    private func effectFor(buffer: String) -> (String, ScreenEffect)? {
        for (pattern, effect) in triggers {
            if buffer.hasSuffix(pattern) { return (pattern, effect) }
        }
        return nil
    }
    
    // 统一的 GIF 调度逻辑：优先使用规则，否则按效果默认
    private func scheduleGif(forPattern pattern: String, effect: ScreenEffect) {
        let selector = gifRules[pattern.lowercased()]
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let selector = selector {
                switch selector {
                case .named(let name):
                    self.showGif(named: name, size: CGSize(width: 800, height: 800))
                case .random(let folder):
                    if let folder, !folder.isEmpty {
                        self.showRandomGif(fromSubdirectory: folder, size: CGSize(width: 800, height: 800))
                    } else {
                        self.showRandomGifFromGroup(size: CGSize(width: 800, height: 800))
                    }
                }
            } else if effect == .blockGlitch {
                // 默认：blockGlitch 显示 halloween
                self.showGif(named: "halloween", size: CGSize(width: 800, height: 800))
            }
            // 添加：ghost 触发时播放 1.mp3
            if pattern.lowercased() == "ghost" {
                MusicPlayer.shared.stop()
                MusicPlayer.shared.play(named: "2", subdirectory: "Music", fileExtension: "mp3", volume: 1.0, loops: 0)
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor.checkAccessibilityPermission()
        
        // 载入可配置触发映射
        loadTriggersFromDefaults()
        loadCumulativeTriggersFromDefaults()
        loadGifRulesFromDefaults()
        loadCooldownsFromDefaults()
        
        // 监听键盘缓冲更新
        keyBufferObserver = NotificationCenter.default.addObserver(forName: .XtionKeyBufferUpdated, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let buffer = notification.userInfo?["buffer"] as? String {
                // 计算新增的键入内容
                let appended: String
                if buffer.count >= self.previousBuffer.count, buffer.hasPrefix(self.previousBuffer) {
                    appended = String(buffer.dropFirst(self.previousBuffer.count))
                } else {
                    // 缓冲被清空或改变，使用当前缓冲作为追加内容
                    appended = buffer
                }
                
                // 累积触发：将新增字符累积到各个模式的进度中
                var cumulativeTriggered = false
                for ch in appended.lowercased() {
                    for (pattern, _) in self.cumulativeTriggers {
                        let targetSet = Set(pattern)
                        if targetSet.contains(ch) {
                            var progress = self.cumulativeProgress[pattern] ?? Set<Character>()
                            progress.insert(ch)
                            self.cumulativeProgress[pattern] = progress
                        }
                    }
                }
                
                // 检查是否满足任意累积模式
                for (pattern, effect) in self.cumulativeTriggers {
                    let targetSet = Set(pattern)
                    let progress = self.cumulativeProgress[pattern] ?? Set<Character>()
                    if progress.isSuperset(of: targetSet) {
                        if self.canTrigger(pattern: pattern) {
                            cumulativeTriggered = true
                            Task { await self.effectManager.start(effect) }
                            self.scheduleGif(forPattern: pattern, effect: effect)
                            // 触发后重置该模式的累积进度 & 记录冷却
                            self.cumulativeProgress[pattern] = Set<Character>()
                            self.markTriggered(pattern: pattern)
                        }
                        // 冷却期间不触发，也不重置累积进度
                    }
                }
                
                self.previousBuffer = buffer
                
                // 若没有被累积规则触发，继续进行后缀匹配触发
                if !cumulativeTriggered, let (pattern, effect) = self.effectFor(buffer: buffer) {
                    if self.canTrigger(pattern: pattern) {
                        Task { await self.effectManager.start(effect) }
                        self.scheduleGif(forPattern: pattern, effect: effect)
                        self.markTriggered(pattern: pattern)
                    }
                }
            }
        }
        
        // 动态刷新触发映射
        triggersObserver = NotificationCenter.default.addObserver(forName: Notification.Name("XtionTriggersChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.loadTriggersFromDefaults()
            self?.loadCumulativeTriggersFromDefaults()
            self?.loadGifRulesFromDefaults()
            self?.loadCooldownsFromDefaults()
        }
    }
    
    deinit {
        if let keyBufferObserver { NotificationCenter.default.removeObserver(keyBufferObserver) }
        if let triggersObserver { NotificationCenter.default.removeObserver(triggersObserver) }
    }
    
    func showGif() {
        floating = FloatingGifWindow(gifName: "halloween", size: CGSize(width: 800, height: 800))
        floating?.show()
    }
    
    func showGif(named: String, size: CGSize = CGSize(width: 800, height: 800)) {
        floating = FloatingGifWindow(gifName: named, size: size)
        floating?.show()
    }
    
    func showRandomGifFromGroup(size: CGSize = CGSize(width: 800, height: 800)) {
        let urls = Bundle.main.urls(forResourcesWithExtension: "gif", subdirectory: "GIFGroup") ?? []
        if let random = urls.randomElement() {
            let name = random.deletingPathExtension().lastPathComponent
            showGif(named: name, size: size)
        } else {
            // fallback
            showGif(named: "test", size: size)
        }
    }
    
    // 指定任意子目录随机弹出 GIF
    func showRandomGif(fromSubdirectory subdir: String, size: CGSize = CGSize(width: 800, height: 800)) {
        let urls = Bundle.main.urls(forResourcesWithExtension: "gif", subdirectory: subdir) ?? []
        if let random = urls.randomElement() {
            let name = random.deletingPathExtension().lastPathComponent
            showGif(named: name, size: size)
        } else {
            showGif(named: "test", size: size)
        }
    }
}
