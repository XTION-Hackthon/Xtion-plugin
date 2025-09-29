//
//  AppDelegate.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import Cocoa
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = KeySpy()
    var statusItem: NSStatusItem!
    var floating: FloatingGifWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        monitor.checkAccessibilityPermission()
    }
    
    func showGif() {
        floating = FloatingGifWindow(gifName: "halloween", size: CGSize(width: 800, height: 800))
        floating?.show()
    }
}
