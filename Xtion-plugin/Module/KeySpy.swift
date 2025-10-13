//
//  KeySpy.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import AppKit

extension Notification.Name {
    static let XtionKeyBufferUpdated = Notification.Name("XtionKeyBufferUpdated")
    // 新增：特殊按键通知（在 AppDelegate 里监听）
    static let XtionSpecialKeyPressed = Notification.Name("XtionSpecialKeyPressed")
}

final class KeySpy {
    private var monitor: Any?
    private var pressedKeys: Set<UInt16> = []
    private var recentChars: [Character] = []
    
    func checkAccessibilityPermission() {
        if AXIsProcessTrusted() {
            start()
        } else {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPermissionAlert()
            }
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "请在系统设置 > 隐私与安全性 > 辅助功能中添加此应用"
        alert.addButton(withTitle: "打开设置")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            NSApp.terminate(nil)
        }
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .systemDefined]) { event in
            let keyCode = event.keyCode
            
            // 处理系统媒体键（如 F10 静音）作为 NSSystemDefined 事件
            if event.type == .systemDefined, event.subtype.rawValue == 8 {
                let data1 = event.data1
                // 高 16 位为 NX 媒体键代码；低字节标志 0xA 表示 keyDown
                let nxKeyCode = UInt16((data1 & 0xFFFF0000) >> 16)
                let isKeyDown = ((data1 & 0x0000FF00) >> 8) == 0x0A
                if isKeyDown {
                    // 广播为特殊按键，供 AppDelegate 统一处理（支持 NX 媒体键码）
                    NotificationCenter.default.post(name: .XtionSpecialKeyPressed, object: nil, userInfo: ["keyCode": nxKeyCode])
                }
                return
            }
            
            if event.type == .keyDown && !self.pressedKeys.contains(keyCode) {
                self.pressedKeys.insert(keyCode)
                
                if let chars = event.charactersIgnoringModifiers {
                    for ch in chars {
                        self.recentChars.append(ch)
                    }
                    if self.recentChars.count > 10 {
                        self.recentChars.removeFirst(self.recentChars.count - 10)
                    }
                    // 广播最新的字符缓冲，供 APP 侧进行灵活匹配
                    NotificationCenter.default.post(name: .XtionKeyBufferUpdated, object: nil, userInfo: ["buffer": String(self.recentChars)])
                }
                
                // 广播特殊按键（例如 esc/delete/enter/F 功能键）供 AppDelegate 播放音效
                NotificationCenter.default.post(name: .XtionSpecialKeyPressed, object: nil, userInfo: ["keyCode": keyCode])
                
                print(event.characters ?? "")
            } else if event.type == .keyUp {
                self.pressedKeys.remove(keyCode)
            }
        }
    }
    
    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
