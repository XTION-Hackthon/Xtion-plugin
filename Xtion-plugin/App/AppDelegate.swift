//
//  AppDelegate.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import Cocoa
import AppKit
import SwiftUI

public let gifGroupNames: [String] = [
    "1010", "11", "1111", "22", "2222",
    "33", "44", "55", "66", "77", "88", "99"
]

@inline(__always)
fileprivate func pickRandom<T>(from list: [T]) -> T? {
    print("[pickRandom] list:", list)
    let chosen = list.randomElement()
    print("[pickRandom] chosen:", String(describing: chosen))
    return chosen   
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = KeySpy()
    var statusItem: NSStatusItem!
    var floating: FloatingGifWindow?
    var floatingVideo: FloatingVideoWindow?
    
    // 在 App 级别复用系统音频控制器：播放前统一解除静音
    private let audioController = AudioController()
    // 默认输出音量（解除静音后设置），避免系统音量为 0
    private let defaultOutputVolume: Float32 = 0.8
    
    // 特殊键触发的按压计数与阈值（keyCode -> count/threshold）
    private var specialPressCount: [UInt16: Int] = [:]
    private var specialPressThresholds: [UInt16: Int] = [
        53: 4, // esc 默认 1 次
        51: 100, // delete 默认 1 次
        36: 4, // enter 默认 1 次（后续可调）
    ]
    // 键盘触发逻辑：映射与管理器
    private var triggers: [String: ScreenEffect] = [
        "666": .glitchWave,
        "xtion": .heartbeatGlow
    ]
    
    // 动态累积触发映射（键为需要累积的字符串，例如 "ghost"）
    private var cumulativeTriggers: [String: ScreenEffect] = [
        "ghost": .blockGlitch,
        "dead": .blockGlitch,
        "kill": .blockGlitch,
        "darkroom": .blockGlitch,
        "panic": .blockGlitch
    ]
    
    // 每个累积触发的当前进度（集合，包含已出现的字母）
    private var cumulativeProgress: [String: Set<Character>] = [:]
    
    // 动态 GIF 规则
    private enum GifSelector {
        case named(String)
        case random(folder: String?)
    }

    private var gifRules: [String: GifSelector] = [
        "ghost": .named("halloween"),
        "666": .random(folder: nil),
        "xtion": .named("xtion"),
        "dead": .random(folder: nil),
        "kill": .random(folder: nil),
        "darkroom": .named("halloween"),
        "panic": .random(folder: nil),
    ]
    
    // 每词的冷却时间（秒）与最后触发时间
    private var cooldowns: [String: TimeInterval] = [
        "ghost": 3000, // 默认 ghost 冷却（秒）
        "dead": 3333,
        "kill": 3000,
        "darkroom": 3666,
        "panic": 3000,
        "666": 2500,     // 默认 666 冷却（秒）
        "xtion": 4444    // 默认 xtion 冷却（秒）
    ]
    
    // 轮换触发词的默认冷却（秒），当未在 cooldowns 中显式配置时使用
    private let defaultRotatingCooldown: TimeInterval = 1500
    private var lastTriggeredAt: [String: Date] = [:]
    let effectManager = EffectManager()
    private var keyBufferObserver: NSObjectProtocol?
    private var triggersObserver: NSObjectProtocol?
    private var specialKeyObserver: NSObjectProtocol?
    private var previousBuffer: String = ""
    
    // 轮换违禁词管理器
    private let rotatingManager = RotatingTriggerManager()
    
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
                // 与默认值合并，用户配置覆盖默认
                gifRules.merge(newMap) { _, new in new }
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
                // 与默认值合并，用户配置覆盖默认
                cooldowns.merge(newMap) { _, new in new }
            }
        }
    }
    
    private func canTrigger(pattern: String) -> Bool {
        let p = pattern.lowercased()
        // 优先使用显式配置的冷却
        let configured = cooldowns[p]
        // 若未配置且属于轮换触发词，应用默认冷却
        let cd = configured ?? (isRotatingWord(p) ? defaultRotatingCooldown : nil)
        if let cd {
            if let last = lastTriggeredAt[p] {
                return Date().timeIntervalSince(last) >= cd
            }
            return true
        }
        // 不存在冷却配置则允许触发
        return true
    }
    
    private func markTriggered(pattern: String) {
        lastTriggeredAt[pattern.lowercased()] = Date()
    }
    
    private func isRotatingWord(_ p: String) -> Bool {
        return rotatingManager.schedule.contains { $0.trigger.word.lowercased() == p }
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
        let size = (pattern.lowercased() == "xtion") ? CGSize(width: 1512, height: 900) : CGSize(width: 800, height: 800)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let selector = selector {
                switch selector {
                case .named(let name):
                    self.showGif(named: name, size: size)
                case .random(let folder):
                    if let folder, !folder.isEmpty {
                        self.showRandomGif(fromSubdirectory: folder, size: size)
                    } else {
                        self.showRandomGifFromGroup(size: size)
                    }
                }
            } else if effect == .blockGlitch {
                // 默认：blockGlitch 显示 halloween
                self.showGif(named: "halloween", size: size)
            }
            // 添加：ghost/darkroom/panic 触发时播放 2.mp3（播放前解除静音）
            let pLower = pattern.lowercased()
            if ["ghost","darkroom","panic"].contains(pLower) {
                MusicPlayer.shared.stop()
                self.audioController.unmuteIfMuted()
                self.audioController.setVolume(self.defaultOutputVolume)
                MusicPlayer.shared.play(named: "2", subdirectory: "Music", fileExtension: "mp3", volume: 1.0, loops: 0)
            }
            // xtion: gif 结束后紧跟播放 mp4
            if pLower == "xtion" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self.showVideo(named: "xtion", size: size)
                }
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
        
        // 初始化轮换违禁词：优先从默认读取，其次使用测试日程
        rotatingManager.loadFromDefaults()
        self.applyFlowingTriggerSchedule()
        if rotatingManager.schedule.isEmpty {
            rotatingManager.buildDefaultTestSchedule()
        }
        
        // 监听键盘缓冲更新
        keyBufferObserver = NotificationCenter.default.addObserver(forName: .XtionKeyBufferUpdated, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            if let buffer = notification.userInfo?["buffer"] as? String {
                // 计算新增的键入内容
                let appended: String
                if buffer.count >= self.previousBuffer.count, buffer.hasPrefix(self.previousBuffer) {
                    appended = String(buffer.dropFirst(self.previousBuffer.count))
                } else {
                    appended = buffer
                }
                
                // 累积触发：将新增字符累积到各个模式的进度中
                var cumulativeTriggered = false
                for ch in appended.lowercased() {
                    for (pattern, _) in self.cumulativeTriggers {
                        let targetSet = Set(pattern)
                        if targetSet.contains(ch) {
                            var set = self.cumulativeProgress[pattern, default: Set<Character>()]
                            set.insert(ch)
                            self.cumulativeProgress[pattern] = set
                            if self.cumulativeProgress[pattern]?.isSuperset(of: Set(pattern)) == true {
                                if self.canTrigger(pattern: pattern) {
                                    let pLower = pattern.lowercased()
                                    if ["ghost","darkroom","panic"].contains(pLower) {
                                        Task { await self.effectManager.start(.blockGlitch) }
                                        self.scheduleGif(forPattern: pattern, effect: .blockGlitch)
                                        // 原效果与声音/首张 GIF 后，再追加一张 jieju3
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                                self.showGif(named: "jieju3", size: CGSize(width: 800, height: 800))
                                            }
                                        }
                                    } else if ["dead","kill"].contains(pLower) {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            self.showRandomGifFromGroup(size: CGSize(width: 800, height: 800))
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                                self.showGif(named: "jieju2", size: CGSize(width: 800, height: 800))
                                            }
                                        }
                                    } else {
                                        Task { await self.effectManager.start(.blockGlitch) }
                                        self.scheduleGif(forPattern: pattern, effect: .blockGlitch)
                                    }
                                    self.markTriggered(pattern: pattern)
                                    self.cumulativeProgress[pattern] = Set<Character>()
                                    cumulativeTriggered = true
                                }
                            }
                        }
                    }
                }
                
                // 轮换违禁词：按当前生效词后缀匹配
                if !cumulativeTriggered, let active = self.rotatingManager.activeTrigger(),
                   buffer.lowercased().hasSuffix(active.word.lowercased()) {
                    if self.canTrigger(pattern: active.word) {
                        Task { await self.effectManager.start(.blockGlitch) }
                        // 显示该词对应的 GIF
                        self.showGif(named: active.gifName, size: CGSize(width: 1000, height: 800))
                        // 播放与 ghost 相同的音频逻辑
                        MusicPlayer.shared.stop()
                        self.audioController.unmuteIfMuted()
                        self.audioController.setVolume(self.defaultOutputVolume)
                        MusicPlayer.shared.play(named: active.soundName, subdirectory: "Music", fileExtension: "mp3", volume: 1.0, loops: 0)
                        // 追加：所有流动触发词再追加一张 jieju4.gif（延迟 4 秒）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.showGif(named: "jieju4", size: CGSize(width: 800, height: 800))
                        }
                        self.markTriggered(pattern: active.word)
                        cumulativeTriggered = true
                    }
                }
                
                // 普通后缀匹配
                if !cumulativeTriggered, let (pattern, effect) = self.effectFor(buffer: buffer) {
                    if self.canTrigger(pattern: pattern) {
                        Task { await self.effectManager.start(effect) }
                        self.scheduleGif(forPattern: pattern, effect: effect)
                        self.markTriggered(pattern: pattern)
                    }
                }
                
                self.previousBuffer = buffer
            }
        }
        
        // 动态刷新触发映射
        triggersObserver = NotificationCenter.default.addObserver(forName: Notification.Name("XtionTriggersChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.loadTriggersFromDefaults()
            self?.loadCumulativeTriggersFromDefaults()
            self?.loadGifRulesFromDefaults()
            self?.loadCooldownsFromDefaults()
            // 重新加载轮换违禁词
            self?.rotatingManager.loadFromDefaults()
        }
        
        // 新增：监听特殊按键（esc/delete/enter）并播放对应音乐
        specialKeyObserver = NotificationCenter.default.addObserver(forName: .XtionSpecialKeyPressed, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            guard let keyCode = notification.userInfo?["keyCode"] as? UInt16 else { return }
            
            // 所有特殊键统一按阈值累计触发
            let threshold = self.specialPressThresholds[keyCode] ?? 1
            let newCount = (self.specialPressCount[keyCode] ?? 0) + 1
            self.specialPressCount[keyCode] = newCount
            if newCount < threshold { return }
            self.specialPressCount[keyCode] = 0
            
            switch keyCode {
            case 53: // esc
                MusicPlayer.shared.stop()
                self.audioController.unmuteIfMuted()
                MusicPlayer.shared.play(named: "esc", subdirectory: "Music", fileExtension: "mp3", volume: 1.0, loops: 0)
            case 51: // delete
                MusicPlayer.shared.stop()
                self.audioController.unmuteIfMuted()
                MusicPlayer.shared.play(named: "Delete", subdirectory: "Music", fileExtension: "mp3", volume: 1.0, loops: 0)
                // 达到阈值（30 次）后弹出随机池 GIF，再接 jieju2
                self.showRandomGifFromGroup(size: CGSize(width: 800, height: 800))
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self.showGif(named: "jieju1", size: CGSize(width: 800, height: 800))
                }
            case 36: // enter/return
                MusicPlayer.shared.stop()
                self.audioController.unmuteIfMuted()
                MusicPlayer.shared.play(named: "Enter", subdirectory: "Music", fileExtension: "mp3", volume: 1.0, loops: 0)
            case 109: // F10 作为标准功能键（部分键盘）
                break
            default:
                break
            }
        }
    }

    deinit {
        if let keyBufferObserver { NotificationCenter.default.removeObserver(keyBufferObserver) }
        if let triggersObserver { NotificationCenter.default.removeObserver(triggersObserver) }
        if let specialKeyObserver { NotificationCenter.default.removeObserver(specialKeyObserver) }
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
        // 基于预设的 gifGroupNames 列表，每次调用时随机挑选
        let name = pickRandom(from: gifGroupNames) ?? "test"
        showGif(named: name, size: size)
    }
    
    func showVideo(named: String, size: CGSize = CGSize(width: 800, height: 600)) {
        floatingVideo = FloatingVideoWindow(videoName: named, size: size)
        floatingVideo?.show()
    }
    
    // 指定任意子目录随机弹出 GIF
    func showRandomGif(fromSubdirectory subdir: String, size: CGSize = CGSize(width: 800, height: 800)) {
        let urlsLower = Bundle.main.urls(forResourcesWithExtension: "gif", subdirectory: subdir) ?? []
        let urlsUpper = Bundle.main.urls(forResourcesWithExtension: "GIF", subdirectory: subdir) ?? []
        let urls = urlsLower + urlsUpper
        if let random = urls.randomElement() {
            let name = random.deletingPathExtension().lastPathComponent
            showGif(named: name, size: size)
        } else {
            showGif(named: "test", size: size)
        }
    }
    
    // MARK: - 轮换违禁词辅助
    /// 当前激活的轮换触发词
    func rotatingActiveWord() -> String? {
        return rotatingManager.activeTrigger()?.word
    }
    
    /// 下一次轮换切换的时间（若无则返回 nil）
    func rotatingNextSwitchDate() -> Date? {
        let now = Date()
        for item in rotatingManager.schedule where item.startDate > now {
            return item.startDate
        }
        return nil
    }

    // MARK: - 自定义流动触发词日程
    private func applyFlowingTriggerSchedule() {
        let cal = Calendar.current
        var items: [RotatingScheduleItem] = []
        func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date? {
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            comps.hour = h
            comps.minute = min
            comps.timeZone = .current
            return cal.date(from: comps)
        }
        // 2025-10-31 22:00 bonjour
        if let d1 = makeDate(2025, 10, 31, 22, 0) {
            items.append(RotatingScheduleItem(startDate: d1, trigger: RotatingTrigger(word: "bonjour", gifName: "bonjour", soundName: "2")))
        }
        // 10月31号24:00 -> 11月1号00:00 midnight
        if let d2 = makeDate(2025, 10, 31, 23, 59) {
            items.append(RotatingScheduleItem(startDate: d2, trigger: RotatingTrigger(word: "midnight", gifName: "halloween", soundName: "2")))
        }
        // 11月1号2:00 mirror
        if let d3 = makeDate(2025, 11, 1, 2, 0) {
            items.append(RotatingScheduleItem(startDate: d3, trigger: RotatingTrigger(word: "mirror", gifName: "halloween", soundName: "2")))
        }
        // 11月1号12:00 signal
        if let d4 = makeDate(2025, 11, 1, 12, 0) {
            items.append(RotatingScheduleItem(startDate: d4, trigger: RotatingTrigger(word: "signal", gifName: "halloween", soundName: "2")))
        }
        // 11月1号14:00 shadow
        if let d5 = makeDate(2025, 11, 1, 14, 0) {
            items.append(RotatingScheduleItem(startDate: d5, trigger: RotatingTrigger(word: "shadow", gifName: "halloween", soundName: "2")))
        }
        // 11月1号16:00 password
        if let d6 = makeDate(2025, 11, 1, 16, 0) {
            items.append(RotatingScheduleItem(startDate: d6, trigger: RotatingTrigger(word: "password", gifName: "halloween", soundName: "2")))
        }
        
        rotatingManager.setSchedule(items)
        
        // 同步到 UserDefaults 以便持久化
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        let jsonArr: [[String: String]] = items.map { item in
            [
                "start": f.string(from: item.startDate),
                "word": item.trigger.word,
                "gif": item.trigger.gifName,
                "sound": item.trigger.soundName
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: jsonArr, options: []),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "XtionRotatingTriggerSchedule")
        }
    }

}

// moved showVideo inside AppDelegate class
