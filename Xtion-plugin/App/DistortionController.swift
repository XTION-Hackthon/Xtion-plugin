//
//  DistortionController.swift
//

import SwiftUI
import Metal
import MetalKit
import QuartzCore
import ScreenCaptureKit

@Observable @MainActor
class DistortionController {
    var isActive = false
    
    private var overlayWindow: NSWindow?
    private var metalView: MTKView?
    private var renderer: DistortionRenderer?
    private var displayLink: CVDisplayLink?
    private var stopTimer: Timer?
    
    func startDistortion() async {
        guard !isActive else { 
            print("扭曲效果已经在运行中")
            return 
        }
        
        print("开始启动扭曲效果...")
        
        await setupScreenCapture()
        setupOverlayWindow()
        setupMetal()
        startDisplayLink()
        
        // 3秒后自动停止
        stopTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            Task { @MainActor in
                self.stopDistortion()
            }
        }
        
        isActive = true
        print("扭曲效果已启动")
    }
    
    func stopDistortion() {
        guard isActive else { return }
        
        print("停止扭曲效果...")
        
        stopTimer?.invalidate()
        stopTimer = nil
        
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        
        // 停止屏幕捕获
        renderer?.stopCapture()
        
        // 确保窗口被正确移除
        overlayWindow?.orderOut(nil)
        overlayWindow?.contentView = nil
        overlayWindow = nil
        
        metalView = nil
        renderer = nil
        
        isActive = false
        print("扭曲效果已停止")
    }
    
    private func setupScreenCapture() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("屏幕捕获权限已获得")
        } catch {
            print("无法获取屏幕捕获权限: \(error)")
        }
    }
    
    private func setupOverlayWindow() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame
        
        print("创建覆盖窗口，尺寸: \(screenRect)")
        
        overlayWindow = NSWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        overlayWindow?.level = .screenSaver
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = .clear
        overlayWindow?.ignoresMouseEvents = true
        overlayWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        metalView = MTKView(frame: screenRect)
        metalView?.wantsLayer = true
        metalView?.layer?.isOpaque = false
        
        overlayWindow?.contentView = metalView
        overlayWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func setupMetal() {
        guard let metalView = metalView,
              let device = MTLCreateSystemDefaultDevice() else { return }
        
        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = false
        metalView.preferredFramesPerSecond = 60
        
        renderer = DistortionRenderer(device: device)
        metalView.delegate = renderer
    }
    
    private func startDisplayLink() {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        if let displayLink = displayLink {
            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo in
                let controller = Unmanaged<DistortionController>.fromOpaque(userInfo!).takeUnretainedValue()
                DispatchQueue.main.async {
                    controller.updateFrame()
                }
                return kCVReturnSuccess
            }
            
            CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(displayLink)
            self.displayLink = displayLink
        }
    }
    
    private func updateFrame() {
        renderer?.updateTime()
        metalView?.needsDisplay = true
    }
}

class DistortionRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var screenTexture: MTLTexture?
    private var time: Float = 0
    private var captureTask: Task<Void, Never>?
    private var initialScreenshot: MTLTexture?
    
    // 修复顶点坐标 - 确保正确的纹理映射
    private let vertices: [Float] = [
        -1.0, -1.0, 0.0, 1.0,  // 左下
         1.0, -1.0, 1.0, 1.0,  // 右下
        -1.0,  1.0, 0.0, 0.0,  // 左上
         1.0,  1.0, 1.0, 0.0   // 右上
    ]
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        setupPipeline()
        startScreenCapture()
    }
    
    private func setupPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            print("无法创建默认库")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertex_main") else {
            print("无法找到顶点着色器函数 vertex_main")
            return
        }
        
        guard let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            print("无法找到片段着色器函数 fragment_main")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("无法创建渲染管线: \(error)")
        }
    }
    
    private func startScreenCapture() {
        captureTask = Task {
            // 只捕获一次初始屏幕截图，避免递归
            await captureInitialScreen()
        }
    }
    
    func stopCapture() {
        captureTask?.cancel()
    }
    
    func updateTime() {
        time += 1.0 / 60.0
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pipelineState = pipelineState,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // 传递顶点数据
        renderEncoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        
        // 使用初始截图而不是实时捕获
        if let texture = initialScreenshot {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }
        var timeValue = time
        renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.size, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func captureInitialScreen() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }
            
            let configuration = SCStreamConfiguration()
            let contentFilter = SCContentFilter(display: display, excludingWindows: [])
            
            // 确保捕获完整的屏幕区域
            configuration.width = Int(display.width)
            configuration.height = Int(display.height)
            configuration.scalesToFit = false
            
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            )
            
            let textureLoader = MTKTextureLoader(device: device)
            initialScreenshot = try await textureLoader.newTexture(cgImage: image, options: [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ])
            
            print("初始屏幕截图已捕获")
            
        } catch {
            print("无法捕获屏幕: \(error)")
        }
    }
    
    deinit {
        captureTask?.cancel()
    }
}
