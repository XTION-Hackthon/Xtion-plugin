//
//  DistortionController.swift
//

import Metal
import SwiftUI
import MetalKit
import QuartzCore
import ScreenCaptureKit

@Observable @MainActor
final class DistortionController {
    private(set) var isActive = false
    
    private var distortionSession: DistortionSession?
    private var autoStopTask: Task<Void, Never>?
    
    func startDistortion() async {
        guard !isActive else { return }
        
        do {
            let session = try await DistortionSession()
            distortionSession = session
            isActive = true
            
            autoStopTask = Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled {
                    stopDistortion()
                }
            }
        } catch {
            // Handle error silently or use structured logging
        }
    }
    
    func stopDistortion() {
        guard isActive else { return }
        
        autoStopTask?.cancel()
        autoStopTask = nil
        distortionSession = nil
        isActive = false
    }
}

@MainActor
private final class DistortionSession {
    private let overlayWindow: NSWindow
    private let metalView: MTKView
    private let renderer: DistortionRenderer
    private let renderTask: Task<Void, Never>
    
    init() async throws {
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
        
        renderer = try DistortionRenderer(device: device, excludeWindow: overlayWindow)
        metalView.delegate = renderer
        
        overlayWindow.makeKeyAndOrderFront(nil)
        
        let renderer = self.renderer
        let metalView = self.metalView
        
        renderTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    while !Task.isCancelled {
                        await renderer.updateTime()
                        await MainActor.run {
                            metalView.needsDisplay = true
                        }
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
                
                group.addTask {
                    await renderer.startCapturing()
                }
            }
        }
    }
    
    deinit {
        renderTask.cancel()
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

private final class DistortionRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let captureManager: ScreenCaptureManager
    
    private var time: Float = 0
    private var screenTexture: MTLTexture?
    
    private let vertices: [Float] = [
        -1.0, -1.0, 0.0, 1.0,
         1.0, -1.0, 1.0, 1.0,
        -1.0,  1.0, 0.0, 0.0,
         1.0,  1.0, 1.0, 0.0
    ]
    
    init(device: MTLDevice, excludeWindow: NSWindow) throws {
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw DistortionError.metalSetupFailed
        }
        self.commandQueue = commandQueue
        
        self.pipelineState = try Self.createPipelineState(device: device)
        self.captureManager = ScreenCaptureManager(device: device, excludeWindow: excludeWindow)
        
        super.init()
    }
    
    func updateTime() async {
        time += 1.0 / 60.0
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
        
        var timeValue = time
        renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.size, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private static func createPipelineState(device: MTLDevice) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
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

private actor ScreenCaptureManager {
    private let device: MTLDevice
    private let excludeWindow: NSWindow
    private let textureLoader: MTKTextureLoader
    
    init(device: MTLDevice, excludeWindow: NSWindow) {
        self.device = device
        self.excludeWindow = excludeWindow
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    var textureStream: AsyncStream<MTLTexture> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let texture = await captureScreenTexture() {
                        continuation.yield(texture)
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    @MainActor
    private func captureScreenTexture() async -> MTLTexture? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            
            let configuration = SCStreamConfiguration()
            configuration.width = Int(display.width)
            configuration.height = Int(display.height)
            configuration.scalesToFit = false
            
            let excludeWindows = content.windows.filter { window in
                Int(window.windowID) == excludeWindow.windowNumber
            }
            
            let contentFilter = SCContentFilter(display: display, excludingWindows: excludeWindows)
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            )
            
            return try await textureLoader.newTexture(cgImage: image, options: [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ])
            
        } catch {
            return nil
        }
    }
}

private enum DistortionError: Error, LocalizedError {
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
