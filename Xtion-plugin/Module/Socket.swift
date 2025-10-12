//
//  Socket.swift
//  Rebuild-Z-iOS
//
//  Created by GH on 8/23/25.
//

import Foundation
import Starscream

@Observable
final class Socket: WebSocketDelegate {
    static let shared = Socket()
    
    var url: URLRequest = URLRequest(url: URL(string: "ws://192.168.171.201:8081")!)
    private var socket: WebSocket?
    
    private init() {
        connect()
    }
    
    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        switch event {
        case .connected(let dictionary):
            print("WebSocket Connected")
            print("连接详情: \(dictionary)")
            
        case .disconnected(let reason, let code):
            print("WebSocket Disconnected")
            print("断开原因: \(reason), 错误码: \(code)")
            reconnect()
            
        case .text(let string):
            print("📝 收到文本消息: \(string)")
            
        case .binary(let data):
            print("📦 收到二进制数据: \(data.count) 字节")
            
        case .pong(let data):
            print("🏓 收到 Pong: \(data?.count ?? 0) 字节")
            
        case .ping(let data):
            print("🏓 收到 Ping: \(data?.count ?? 0) 字节")
            
        case .error(let error):
            print("⚠️ WebSocket 错误: \(error?.localizedDescription ?? "未知错误")")
            reconnect()
            
        case .viabilityChanged(let isViable):
            print("🔄 连接可用性变化: \(isViable ? "可用" : "不可用")")
            
        case .reconnectSuggested(let shouldReconnect):
            print("💡 建议重连: \(shouldReconnect)")
            if shouldReconnect {
                reconnect()
            }
            
        case .cancelled:
            print("🚫 WebSocket 连接已取消")
            
        case .peerClosed:
            print("👋 对方关闭了连接")
            reconnect()
        }
    }
    
    func send(_ text: String) {
        socket?.write(string: text)
        print("WebSocket Send: \(text)")
    }
    
    private func connect() {
        print("Start connect WebSocket...")
        socket = WebSocket(request: url)
        socket?.delegate = self
        socket?.connect()
    }
    
    private func reconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.socket?.disconnect()
            self.socket = nil
            self.connect()
        }
    }
    
    func changeURL(_ urlString: String) {
        guard let newURL = URL(string: urlString) else {
            return
        }
        
        guard urlString.hasPrefix("ws://") || urlString.hasPrefix("wss://") else {
            print("❌ URL 必须以 ws:// 或 wss:// 开头")
            return
        }
        
        socket?.disconnect()
        socket = nil
        
        url = URLRequest(url: newURL)
        
        connect()
    }
}
