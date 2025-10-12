//
//  KeySpy.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import AppKit

extension Notification.Name {
    static let XtionKeyBufferUpdated = Notification.Name("XtionKeyBufferUpdated")
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
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let keyCode = event.keyCode
            
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
