//
//  Clipboard.swift
//  Xtion-plugin
//
//  Created by GH on 10/13/25.
//

import Cocoa

class Clipboard {
    static let shared = Clipboard()
    
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var eventMonitor: Any?
    
    var content: String? {
        get {
            return pasteboard.string(forType: .string)
        } set {
            guard let newValue else { return }
            pasteboard.setString(newValue, forType: .string)
            
            changeCount = pasteboard.changeCount
        }
    }
    
    private init() {
        changeCount = pasteboard.changeCount
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.modifierFlags.contains(.command), 
               let char = event.charactersIgnoringModifiers,
               char == "c" || char == "x" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.checkForChanges()
                }
            }
        }
    }
    
    private func checkForChanges() {
        let current = pasteboard.changeCount
        if current != changeCount {
            changeCount = current
            if let content = pasteboard.string(forType: .string) {
                print("Clipboard: \(content)")
            }
        }
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
