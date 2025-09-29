//
//  XtionPluginApp.swift
//  Xtion-plugin
//
//  Created by GH on 9/28/25.
//

import SwiftUI

@main
struct XtionPluginApp: App {
    // 使用单例模式避免创建多个实例
    @State private var distortionController = DistortionController()
    
    var body: some Scene {
        MenuBarExtra("扭曲", systemImage: "waveform") {
            Button("开始扭曲") {
                Task {
                    await distortionController.startDistortion()
                }
            }
            .disabled(distortionController.isActive)
            
            Button("停止扭曲") {
                distortionController.stopDistortion()
            }
            .disabled(!distortionController.isActive)
            
            Divider()
            
            Button("退出") {
                // 确保退出前清理资源
                distortionController.stopDistortion()
                NSApp.terminate(nil)
            }
        }
    }
}
