//
//  EffectSession.swift
//  Xtion-plugin
//
//  Created by GH on 10/4/25.
//

import MetalKit
import ScreenCaptureKit

@MainActor
final class EffectSession {
    // MARK: - Properties
    private let overlayWindow: NSWindow
    private let metalView: MTKView
    private let renderer: EffectRenderer
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
        renderer = try EffectRenderer(device: device, effect: effect, excludeWindowNumber: windowNumber)
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
