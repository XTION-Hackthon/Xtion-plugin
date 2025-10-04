//
//  ScreenCapturer.swift
//  Xtion-plugin
//
//  Created by GH on 10/4/25.
//

import MetalKit
import CoreGraphics
import ScreenCaptureKit

actor ScreenCapturer {
    private let device: MTLDevice
    private let excludeWindowNumber: Int
    private let textureCache: CVMetalTextureCache?
    
    private var cachedContentFilter: SCContentFilter?
    private var cachedConfiguration: SCStreamConfiguration?
    
    init(device: MTLDevice, excludeWindowNumber: Int) {
        self.device = device
        self.excludeWindowNumber = excludeWindowNumber
        
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache
        
        Task { await prepareCapture() }
    }
    
    /// 准备并缓存屏幕捕获配置
    private func prepareCapture() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first else { return }
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.scalesToFit = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        
        let excludeWindows = content.windows.filter { window in
            Int(window.windowID) == excludeWindowNumber
        }
        
        let contentFilter = SCContentFilter(display: display, excludingWindows: excludeWindows)
        
        self.cachedContentFilter = contentFilter
        self.cachedConfiguration = configuration
    }
    
    /// 纹理流 - 尽可能快地捕获屏幕内容
    var textureStream: AsyncStream<MTLTexture> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    if let texture = await captureScreenTexture() {
                        continuation.yield(texture)
                    }
                }
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    /// 捕获屏幕并转换为 Metal 纹理
    private func captureScreenTexture() async -> MTLTexture? {
        guard let contentFilter = cachedContentFilter,
              let configuration = cachedConfiguration else {
            await prepareCapture()
            return nil
        }
        
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        ) else { return nil }
        
        return createTexture(from: image)
    }
    
    /// 使用 CVMetalTextureCache 从 CGImage 直接创建 Metal 纹理
    private func createTexture(from cgImage: CGImage) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary, &pixelBuffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var textureRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .bgra8Unorm, width, height, 0, &textureRef)
        
        guard let textureRef = textureRef else { return nil }
        return CVMetalTextureGetTexture(textureRef)
    }
}
