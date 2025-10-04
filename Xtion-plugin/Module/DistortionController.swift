//
//  DistortionController.swift
//

import MetalKit
import ScreenCaptureKit

/// 可用的屏幕扭曲特效类型
enum DistortionEffect: String, CaseIterable, Identifiable {
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
class DistortionController {
    private(set) var isActive = false
    private(set) var currentEffect: DistortionEffect?
    
    private var distortionSession: DistortionSession?
    private var autoStopTask: Task<Void, Never>?
    
    /// 启动指定的扭曲特效
    /// - Parameters:
    ///   - effect: 要启动的特效类型
    ///   - duration: 特效持续时间(秒),nil 表示不自动停止
    func startDistortion(effect: DistortionEffect, duration: TimeInterval? = 3) async {
        guard !isActive else { return }
        
        guard let session = try? await DistortionSession(effect: effect) else { return }
        distortionSession = session
        currentEffect = effect
        isActive = true
        
        if let duration = duration {
            autoStopTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                if !Task.isCancelled {
                    stopDistortion()
                }
            }
        }
    }
    
    func stopDistortion() {
        guard isActive else { return }
        
        autoStopTask?.cancel()
        autoStopTask = nil
        distortionSession = nil
        currentEffect = nil
        isActive = false
    }
}

@MainActor
class DistortionSession {
    // MARK: - Constants
    private enum Constants {
        static let pixelFormat: MTLPixelFormat = .bgra8Unorm
        
        /// 根据屏幕能力返回最佳帧率
        static func preferredFPS(for screen: NSScreen) -> Int {
            // 检测是否支持 ProMotion (120Hz+)
            if screen.maximumFramesPerSecond >= 120 {
                return 120
            }
            return 60
        }
    }
    
    // MARK: - Properties
    private let overlayWindow: NSWindow
    private let metalView: MTKView
    private let renderer: Renderer
    private let captureTask: Task<Void, Never>
    
    // MARK: - Initialization
    init(effect: DistortionEffect) async throws {
        // 请求屏幕捕获权限 (即使不直接使用结果,也能触发权限请求)
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let screen = NSScreen.main else {
            throw DistortionError.noScreenAvailable
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw DistortionError.metalNotAvailable
        }
        
        // 初始化组件
        overlayWindow = Self.createOverlayWindow(for: screen)
        metalView = Self.createMetalView(for: screen, device: device)
        overlayWindow.contentView = metalView
        
        let windowNumber = overlayWindow.windowNumber
        renderer = try Renderer(device: device, effect: effect, excludeWindowNumber: windowNumber)
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
        metalView.colorPixelFormat = Constants.pixelFormat
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = Constants.preferredFPS(for: screen)
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        
        return metalView
    }
}

enum DistortionError: Error, LocalizedError {
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
