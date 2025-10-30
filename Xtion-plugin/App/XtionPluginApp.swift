//
//  XtionPluginApp.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import SwiftUI
internal import Combine
import AVKit

@main
struct XtionPluginApp: App {
    @State private var screenEffect = EffectManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 显示当前触发词与下次切换时间
    @State private var currentTriggerWord: String = "-"
    @State private var nextSwitchLabel: String = "-"
    private let updateTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    private func updateRotatingInfo() {
        if let word = appDelegate.rotatingActiveWord() {
            currentTriggerWord = word
        } else {
            currentTriggerWord = "(未设定)"
        }
        if let next = appDelegate.rotatingNextSwitchDate() {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f.timeZone = .current
            nextSwitchLabel = f.string(from: next)
        } else {
            nextSwitchLabel = "(无后续切换)"
        }
    }
    
    var body: some Scene {
        MenuBarExtra("Xtion", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 8) {
                Text("当前触发词：\(currentTriggerWord)")
                Text("下次切换：\(nextSwitchLabel)")
                Button("刷新触发词") {
                    updateRotatingInfo()
                }
                Divider()
                // 为每个特效创建菜单项
                ForEach(ScreenEffect.allCases) { effect in
                    Button(effect.rawValue) {
                        Task {
                            await screenEffect.start(effect)
                        }
                    }
                    .disabled(screenEffect.isActive)
                }
                
                Button("停止扭曲") {
                    screenEffect.stop()
                }
                .disabled(!screenEffect.isActive)
                
                Divider()
                
                Button("退出") {
                    // 确保退出前清理资源
                    screenEffect.stop()
                    NSApp.terminate(nil)
                }
            }
            .onAppear { updateRotatingInfo() }
            .onReceive(updateTimer) { _ in updateRotatingInfo() }
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

struct FloatingVideoWindow {
    private var window: NSWindow!
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var estimatedDuration: TimeInterval = 6.0
    
    init(videoName: String, size: CGSize = CGSize(width: 800, height: 600)) {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.videoGravity = .resizeAspect
        
        let bundle = Bundle.main
        let url = bundle.url(forResource: videoName, withExtension: "mp4", subdirectory: "GIFGroup")
            ?? bundle.url(forResource: videoName, withExtension: "mp4")
        if let url {
            let asset = AVURLAsset(url: url)
            let seconds = CMTimeGetSeconds(asset.duration)
            if seconds.isFinite && seconds > 0 { estimatedDuration = seconds }
            let player = AVPlayer(url: url)
            playerView.player = player
            self.player = player
        }
        
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = playerView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        
        self.playerView = playerView
    }
    
    func show() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - window.frame.width / 2
            let y = screenFrame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            player?.play()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
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
        
        // 优先在 GIFGroup 子目录中查找，同时兼容 .gif / .GIF 扩展名
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: name, withExtension: "gif", subdirectory: "GIFGroup"),
            bundle.url(forResource: name, withExtension: "GIF", subdirectory: "GIFGroup"),
            bundle.url(forResource: name, withExtension: "gif"),
            bundle.url(forResource: name, withExtension: "GIF")
        ]
        if let url = candidates.compactMap({ $0 }).first,
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
