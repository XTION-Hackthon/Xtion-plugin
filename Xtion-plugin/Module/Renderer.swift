//
//  ScreenEffectRenderer.swift
//  Xtion-plugin
//
//  Created by GH on 10/4/25.
//

import MetalKit

final class ScreenEffectRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let captureManager: ScreenCapturer
    private let effect: ScreenEffect
    private let vertexBuffer: MTLBuffer
    
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var screenTexture: MTLTexture?
    
    private static let vertices: [Float] = [
        -1.0, -1.0, 0.0, 1.0,
         1.0, -1.0, 1.0, 1.0,
        -1.0,  1.0, 0.0, 0.0,
         1.0,  1.0, 1.0, 0.0
    ]
    
    init(device: MTLDevice, effect: ScreenEffect, excludeWindowNumber: Int) throws {
        self.device = device
        self.effect = effect
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw ScreenEffectError.metalSetupFailed
        }
        self.commandQueue = commandQueue
        
        let verticesSize = Self.vertices.count * MemoryLayout<Float>.stride
        guard let buffer = device.makeBuffer(bytes: Self.vertices, length: verticesSize, options: []) else {
            throw ScreenEffectError.metalSetupFailed
        }
        self.vertexBuffer = buffer
        
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
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        
        if let texture = screenTexture {
            renderEncoder.setFragmentTexture(texture, index: 0)
        }
        
        var timeValue = Float(CACurrentMediaTime() - startTime)
        renderEncoder.setFragmentBytes(&timeValue, length: MemoryLayout<Float>.size, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private static func createPipelineState(device: MTLDevice, effect: ScreenEffect) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: effect.fragmentFunctionName) else {
            throw ScreenEffectError.shaderNotFound
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
