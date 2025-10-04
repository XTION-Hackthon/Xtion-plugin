//
//  ScreenCapturer.swift
//  Xtion-plugin
//
//  Created by GH on 10/4/25.
//

import MetalKit
import ScreenCaptureKit

actor ScreenCapturer {
    private let device: MTLDevice
    private let excludeWindowNumber: Int
    private let textureLoader: MTKTextureLoader
    
    init(device: MTLDevice, excludeWindowNumber: Int) {
        self.device = device
        self.excludeWindowNumber = excludeWindowNumber
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
    
    private func captureScreenTexture() async -> MTLTexture? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first else { return nil }
        
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width)
        configuration.height = Int(display.height)
        configuration.scalesToFit = false
        
        let excludeWindows = content.windows.filter { window in
            Int(window.windowID) == excludeWindowNumber
        }
        
        let contentFilter = SCContentFilter(display: display, excludingWindows: excludeWindows)
        
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        ) else { return nil }
        
        return try? await textureLoader.newTexture(cgImage: image, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
    }
}
