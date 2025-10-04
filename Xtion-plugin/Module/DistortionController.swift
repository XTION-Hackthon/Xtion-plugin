//
//  ScreenEffectController.swift
//

import MetalKit
import ScreenCaptureKit

/// 可用的屏幕特效类型
enum ScreenEffect: String, CaseIterable, Identifiable {
    case glitchWave = "故障波浪"
    var id: String { rawValue }
    
    /// 对应的 Metal fragment 函数名
    var fragmentFunctionName: String {
        switch self {
        case .glitchWave: return "fragment_glitch_wave"
        }
    }
}

@MainActor
final class ScreenEffectController {
    private(set) var isActive = false
    private(set) var currentEffect: ScreenEffect?
    
    private var effectSession: ScreenEffectSession?
    private var autoStopTask: Task<Void, Never>?
    
    /// 启动指定的屏幕特效
    /// - Parameters:
    ///   - effect: 要启动的特效类型
    ///   - duration: 特效持续时间(秒),nil 表示不自动停止
    func startEffect(_ effect: ScreenEffect, duration: TimeInterval? = 3) async {
        guard !isActive else { return }
        
        guard let session = try? await ScreenEffectSession(effect: effect) else { return }
        effectSession = session
        currentEffect = effect
        isActive = true
        
        if let duration = duration {
            autoStopTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled {
                    stopEffect()
                }
            }
        }
    }
    
    func stopEffect() {
        guard isActive else { return }
        
        autoStopTask?.cancel()
        autoStopTask = nil
        effectSession = nil
        currentEffect = nil
        isActive = false
    }
}

@MainActor
final class ScreenEffectSession {
    // MARK: - Properties
    private let overlayWindow: NSWindow
    private let metalView: MTKView
    private let renderer: ScreenEffectRenderer
    private let captureTask: Task<Void, Never>
    
    // MARK: - Initialization
    init(effect: ScreenEffect) async throws {
        // 请求屏幕捕获权限
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let screen = NSScreen.main else {
            throw ScreenEffectError.noScreenAvailable
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ScreenEffectError.metalNotAvailable
        }
        
        // 初始化组件
        overlayWindow = Self.createOverlayWindow(for: screen)
        metalView = Self.createMetalView(for: screen, device: device)
        overlayWindow.contentView = metalView
        
        let windowNumber = overlayWindow.windowNumber
        renderer = try ScreenEffectRenderer(device: device, effect: effect, excludeWindowNumber: windowNumber)
        metalView.delegate = renderer
        
        overlayWindow.makeKeyAndOrderFront(nil)
        
        // 启动屏幕捕获
        captureTask = Task { [renderer] in
            await renderer.startCapturing()
        }
    }
    
    deinit {
        captureTask.cancel()
        metalView.delegate = nil
        overlayWindow.orderOut(nil)
    }
    
    // MARK: - Factory Methods
    private static func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        
        return window
    }
    
    private static func createMetalView(for screen: NSScreen, device: MTLDevice) -> MTKView {
        let metalView = MTKView(frame: screen.frame)
        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        
        // 根据屏幕能力设置帧率
        metalView.preferredFramesPerSecond = screen.maximumFramesPerSecond >= 120 ? 120 : 60
        
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        
        return metalView
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
