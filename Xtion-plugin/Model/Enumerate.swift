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
    case heartbeatGlow = "心跳红光"
    case snowStatic = "恐怖雪花"
    case blockGlitch = "块状故障"
    
    /// 对应的 Metal fragment 函数名
    var fragmentFunctionName: String {
        switch self {
        case .glitchWave: return "fragment_glitch_wave"
        case .heartbeatGlow: return "fragment_heartbeat_glow"
        case .snowStatic: return "fragment_snow_static"
        case .blockGlitch: return "fragment_block_glitch"
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
