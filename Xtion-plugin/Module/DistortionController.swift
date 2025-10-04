//
//  DistortionController.swift
//

import Metal
import SwiftUI
import MetalKit
import QuartzCore
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
    private let overlayWindow: NSWindow
    private let metalView: MTKView
    private let renderer: DistortionRenderer
    private let captureTask: Task<Void, Never>
    
    init(effect: DistortionEffect) async throws {
        _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        guard let screen = NSScreen.main else {
            throw DistortionError.noScreenAvailable
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw DistortionError.metalNotAvailable
        }
        
        overlayWindow = Self.createOverlayWindow(for: screen)
        metalView = Self.createMetalView(for: screen, device: device)
        overlayWindow.contentView = metalView
        
        let windowNumber = overlayWindow.windowNumber
        renderer = try DistortionRenderer(device: device, effect: effect, excludeWindowNumber: windowNumber)
        metalView.delegate = renderer
        
        overlayWindow.makeKeyAndOrderFront(nil)
        
        // 简化:只需要一个 Task 用于屏幕捕获
        let renderer = self.renderer
        captureTask = Task {
            await renderer.startCapturing()
        }
    }
    
    deinit {
        captureTask.cancel()
        overlayWindow.orderOut(nil)
    }
    
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
        metalView.preferredFramesPerSecond = 60
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false
        metalView.layer?.backgroundColor = NSColor.clear.cgColor
        
        return metalView
    }
}

class DistortionRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let captureManager: ScreenCapturer
    private let effect: DistortionEffect
    
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var screenTexture: MTLTexture?
    
    private let vertices: [Float] = [
        -1.0, -1.0, 0.0, 1.0,
         1.0, -1.0, 1.0, 1.0,
        -1.0,  1.0, 0.0, 0.0,
         1.0,  1.0, 1.0, 0.0
    ]
    
    init(device: MTLDevice, effect: DistortionEffect, excludeWindowNumber: Int) throws {
        self.device = device
        self.effect = effect
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw DistortionError.metalSetupFailed
        }
        self.commandQueue = commandQueue
        
        self.pipelineState = try Self.createPipelineState(device: device, effect: effect)
        self.captureManager = ScreenCapturer(device: device, excludeWindowNumber: excludeWindowNumber)
        
        super.init()
    }
    
    func startCapturing() async {
        for await texture in await captureManager.textureStream {
            screenTexture = texture
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        
        if let texture = screenTexture {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }
        
        // 简化:直接在 draw 时计算时间
        var timeValue = Float(CACurrentMediaTime() - startTime)
        renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.size, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private static func createPipelineState(device: MTLDevice, effect: DistortionEffect) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: effect.fragmentFunctionName) else {
            throw DistortionError.shaderNotFound
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
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
