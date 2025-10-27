//
//  RotatingTriggerManager.swift
//  Xtion-plugin
//
//  Created by Assistant on 10/22/25.
//

import Foundation

struct RotatingTrigger {
    let word: String
    let gifName: String
    let soundName: String // 不带扩展名，例如 "2"
}

struct RotatingScheduleItem {
    let startDate: Date
    let trigger: RotatingTrigger
}

/// 管理按时间轮换的触发词（例如：23:00 切换到 bloodymary，0:00 切换到 bonjout，1:00 切换到 deadman）
final class RotatingTriggerManager {
    private(set) var schedule: [RotatingScheduleItem] = [] // 按开始时间升序
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
    
    /// 从 UserDefaults 加载日程（key: XtionRotatingTriggerSchedule）
    /// JSON 结构示例：
    /// [
    ///   {"start":"2025-10-22 23:00","word":"bloodymary","gif":"bloodymary","sound":"2"},
    ///   {"start":"2025-10-23 00:00","word":"bonjout","gif":"bonjour","sound":"2"},
    ///   {"start":"2025-10-23 01:00","word":"deadman","gif":"deadman","sound":"2"}
    /// ]
    func loadFromDefaults() {
        guard let jsonString = UserDefaults.standard.string(forKey: "XtionRotatingTriggerSchedule"),
              let data = jsonString.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return
        }
        var items: [RotatingScheduleItem] = []
        for obj in arr {
            guard let startStr = obj["start"],
                  let word = obj["word"],
                  let gif = obj["gif"],
                  let date = df.date(from: startStr) else { continue }
            let sound = obj["sound"] ?? "2"
            items.append(RotatingScheduleItem(startDate: date, trigger: RotatingTrigger(word: word, gifName: gif, soundName: sound)))
        }
        schedule = items.sorted { $0.startDate < $1.startDate }
    }
    
    /// 构建默认测试日程（按当前时区）：
    /// 2025-10-22 23:00 -> bloodymary
    /// 2025-10-23 00:00 -> bonjout
    /// 2025-10-23 01:00 -> deadman
    func buildDefaultTestSchedule() {
        guard let d1 = df.date(from: "2025-10-22 23:00"),
              let d2 = df.date(from: "2025-10-23 00:00"),
              let d3 = df.date(from: "2025-10-23 01:00") else { return }
        schedule = [
            RotatingScheduleItem(startDate: d1, trigger: RotatingTrigger(word: "bloodymary", gifName: "bloodymary", soundName: "2")),
            RotatingScheduleItem(startDate: d2, trigger: RotatingTrigger(word: "bonjout", gifName: "bonjour", soundName: "2")),
            RotatingScheduleItem(startDate: d3, trigger: RotatingTrigger(word: "deadman", gifName: "deadman", soundName: "2")),
        ]
    }
    
    /// 当前时间下的生效触发词；如果有多个，取最近一个开始时间不晚于当前的项
    func activeTrigger(at date: Date = Date()) -> RotatingTrigger? {
        guard !schedule.isEmpty else { return nil }
        var current: RotatingTrigger?
        for item in schedule where item.startDate <= date {
            current = item.trigger
        }
        return current
    }
}