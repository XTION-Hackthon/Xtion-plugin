//
//  DistortionController.swift
//

import SwiftUI
import Metal
import MetalKit
import QuartzCore

@MainActor
class DistortionController: ObservableObject {
    @Published var isActive = false
    
    private var overlayWindow: NSWindow?
    private var metalView: MTKView?
    private var renderer: DistortionRenderer?
    private var displayLink: CADisplayLink?
    
    func startDistortion() {
        guard !isActive else { return }
        
        setupOverlayWindow()
        setupMetal()
        startDisplayLink()
        
        isActive = true
    }
    
    func stopDistortion() {
        guard isActive else { return }
        
        displayLink?.invalidate()
        displayLink = nil
        
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        metalView = nil
        renderer = nil
        
        isActive = false
    }
    
    private func setupOverlayWindow() {
        // 获取主屏幕尺寸
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame
        
        // 创建全屏覆盖窗口
        overlayWindow = NSWindow(
            contentRect: screenRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        overlayWindow?.level = .screenSaver
        overlayWindow?.isOpaque = false
        overlayWindow?.backgroundColor = .clear
        overlayWindow?.ignoresMouseEvents = false
        overlayWindow?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // 创建 Metal 视图
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
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func updateFrame() {
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
    }
    
    private func setupPipeline() {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")
        
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
    
    func updateTime() {
        time += 1.0 / 60.0
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pipelineState = pipelineState,
              let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        
        // 捕获屏幕
        captureScreen()
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // 传递顶点数据
        renderEncoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        
        // 传递纹理和时间参数
        if let texture = screenTexture {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func captureScreen() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.frame
        
        let imageRef = CGWindowListCreateImage(screenRect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
        guard let cgImage = imageRef else { return }
        
        // 将 CGImage 转换为 Metal 纹理
        let textureLoader = MTKTextureLoader(device: device)
        do {
            screenTexture = try textureLoader.newTexture(cgImage: cgImage, options: nil)
        } catch {
            print("无法创建屏幕纹理: \(error)")
        }
    }
}
