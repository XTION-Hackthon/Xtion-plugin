//
//  XtionPluginApp.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import SwiftUI

@main
struct XtionPluginApp: App {
    @State private var screenEffectController = ScreenEffectController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("Xtion", systemImage: "waveform") {
            // 为每个特效创建菜单项
            ForEach(ScreenEffect.allCases) { effect in
                Button(effect.rawValue) {
                    Task {
                        await screenEffectController.startEffect(effect)
                    }
                }
                .disabled(screenEffectController.isActive)
            }
            
            Button("停止扭曲") {
                screenEffectController.stopEffect()
            }
            .disabled(!screenEffectController.isActive)
            
            Divider()
            
            Button("退出") {
                // 确保退出前清理资源
                screenEffectController.stopEffect()
                NSApp.terminate(nil)
            }
        }
    }
}

// TODO: - 还没集成
struct FloatingGifWindow {
    private var window: NSWindow!
    
    init(gifName: String, size: CGSize = CGSize(width: 200, height: 200)) {
        let contentView = GifImage(gifName)
            .frame(width: size.width, height: size.height)
        
        let hosting = NSHostingView(rootView: contentView)
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        
    }
    
    private var flashWindow: FlashWindow = FlashWindow()
    
    func show(duration: TimeInterval = 4.0) {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - window.frame.width / 2
            let y = screenFrame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        flashWindow.startFlashing()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            flashWindow.stopFlashing()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            window.orderOut(nil)
        }
    }
}

struct GifImage: NSViewRepresentable {
    private let name: String
    
    init(_ name: String) {
        self.name = name
    }
    
    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.canDrawSubviewsIntoLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        
        if let url = Bundle.main.url(forResource: name, withExtension: "gif"),
           let data = try? Data(contentsOf: url),
           let image = NSImage(data: data) {
            imageView.image = image
            imageView.animates = true
        }
        
        return imageView
    }
    
    func updateNSView(_ nsView: NSImageView, context: Context) {
        
    }
}

class FlashWindow: NSWindow {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        self.isOpaque = false
        self.backgroundColor = .black
        self.level = .statusBar
        self.ignoresMouseEvents = true
    }
    
    var flashTimer: Timer?
    var flashWindow: NSWindow?
    
    func startFlashing() {
        guard let screenFrame = NSScreen.main?.frame else { return }
        flashWindow = FlashWindow(contentRect: screenFrame, styleMask: .borderless, backing: .buffered, defer: false)
        flashWindow?.makeKeyAndOrderFront(nil)
        
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.flashWindow?.alphaValue = self.flashWindow?.alphaValue == 0 ? 1 : 0
        }
    }
    
    func stopFlashing() {
        flashTimer?.invalidate()
        flashTimer = nil
        flashWindow?.orderOut(nil)
        flashWindow = nil
    }
}
