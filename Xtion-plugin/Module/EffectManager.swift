//
//  EffectManager.swift
//  Xtion-plugin
//
//  Created by GH on 10/4/25.
//

import Foundation

@MainActor
final class EffectManager {
    private(set) var isActive = false
    private(set) var currentEffect: ScreenEffect?
    
    private var effectSession: EffectSession?
    private var autoStopTask: Task<Void, Never>?
    
    /// 启动指定的屏幕特效
    /// - Parameters:
    ///   - effect: 要启动的特效类型
    ///   - duration: 特效持续时间(秒),nil 表示不自动停止
    func start(_ effect: ScreenEffect, duration: TimeInterval? = 3) async {
        guard !isActive else { return }
        
        guard let session = try? await EffectSession(effect: effect) else { return }
        effectSession = session
        currentEffect = effect
        isActive = true
        
        if let duration = duration {
            autoStopTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled {
                    stop()
                }
            }
        }
    }
    
    func stop() {
        guard isActive else { return }
        
        autoStopTask?.cancel()
        autoStopTask = nil
        effectSession = nil
        currentEffect = nil
        isActive = false
    }
}
