//
//  Enumerate.swift
//  Xtion-plugin
//
//  Created by GH on 10/4/25.
//

import Foundation

enum ScreenEffect: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    
    case glitchWave = "故障波浪"
    
    /// 对应的 Metal fragment 函数名
    var fragmentFunctionName: String {
        switch self {
        case .glitchWave: return "fragment_glitch_wave"
        }
    }
}

enum ScreenEffectError: Error, LocalizedError {
    case noScreenAvailable
    case metalNotAvailable
    case metalSetupFailed
    case shaderNotFound
    
    var errorDescription: String? {
        switch self {
        case .noScreenAvailable:
            return "没有可用的屏幕"
        case .metalNotAvailable:
            return "Metal 不可用"
        case .metalSetupFailed:
            return "Metal 设置失败"
        case .shaderNotFound:
            return "着色器未找到"
        }
    }
}
