#!/usr/bin/env xcrun swift

import AppKit
import QuartzCore
import Foundation

class JARVISOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        let view = JARVISOverlayView(frame: screenFrame)
        self.contentView = view
    }
    
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        contentView?.frame = NSRect(origin: .zero, size: frameRect.size)
    }
    
    func show() {
        self.orderFrontRegardless()
        self.alphaValue = 1.0
    }
    
    func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

class JARVISOverlayView: NSView {
    private var allLayers: [CALayer] = []
    private var textLayer: CATextLayer!
    private var centerRingLayer: CAShapeLayer!
    private var userTextLayer: CATextLayer!
    private var aiTextLayer: CATextLayer!
    
    // 四个独立的容器层，分别控制旋转
    private let mainContainerLayer = CALayer()
    private let outermostContainer = CALayer()
    private let doubleArcContainer = CALayer()
    private let dataRingContainer = CALayer()
    private let centerRingContainer = CALayer()
    
    private let containerSize: CGFloat = 600
    
    // AI 文本历史记录，用于滚动显示
    private var aiTextHistory: [String] = []
    private let maxAILines = 5
    
    private let cyanColor = NSColor(calibratedRed: 0.0, green: 0.95, blue: 1.0, alpha: 1.0)
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        let center = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
        let containerCenter = CGPoint(x: containerSize / 2, y: containerSize / 2)
        
        // 主容器跟随窗口居中
        mainContainerLayer.position = center
        
        // 子容器相对于主容器居中，保持锚点
        outermostContainer.position = containerCenter
        doubleArcContainer.position = containerCenter
        dataRingContainer.position = containerCenter
        centerRingContainer.position = containerCenter
        
        textLayer?.position = CGPoint(x: center.x, y: center.y)
        
        userTextLayer?.frame.origin = CGPoint(
            x: center.x - (userTextLayer?.bounds.width ?? 225) / 2,
            y: center.y - 270
        )
        
        aiTextLayer?.frame.origin = CGPoint(
            x: center.x - (aiTextLayer?.bounds.width ?? 225) / 2,
            y: center.y - 380
        )
        
        CATransaction.commit()
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        // 初始化所有容器层
        let containers = [mainContainerLayer, outermostContainer, doubleArcContainer, dataRingContainer, centerRingContainer]
        for container in containers {
            container.bounds = CGRect(x: 0, y: 0, width: containerSize, height: containerSize)
            container.backgroundColor = NSColor.clear.cgColor
        }
        
        // 主容器居中
        if let screen = NSScreen.main {
            mainContainerLayer.position = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        } else {
            mainContainerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        
        // 子容器相对于主容器居中，锚点设为(0.5, 0.5)确保围绕中心旋转
        let subContainers = [outermostContainer, doubleArcContainer, dataRingContainer, centerRingContainer]
        for container in subContainers {
            container.position = CGPoint(x: containerSize / 2, y: containerSize / 2)
            container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        }
        
        // 添加层级关系
        mainContainerLayer.addSublayer(outermostContainer)
        mainContainerLayer.addSublayer(doubleArcContainer)
        mainContainerLayer.addSublayer(dataRingContainer)
        mainContainerLayer.addSublayer(centerRingContainer)
        
        layer?.addSublayer(mainContainerLayer)
    }
    
    private func createAllLayers(addAnimations: Bool = true) {
        let center = CGPoint(x: containerSize / 2, y: containerSize / 2)
        
        // 每个圆环组添加到各自的容器中，独立旋转
        createOutermostRing(center: center, addAnimation: addAnimations)
        createOuterDoubleArcs(center: center, addAnimation: addAnimations)
        createDataRing(center: center, addAnimation: addAnimations)
        createCenterRing(center: center, addAnimation: addAnimations)
        createTextLayer(center: center)
    }
    
    private func addRotationAnimations() {
        // 最外层：顺时针旋转（负值）
        outermostContainer.setValue(0, forKeyPath: "transform.rotation.z")
        let rotation1 = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation1.fromValue = 0
        rotation1.toValue = -CGFloat.pi * 2
        rotation1.duration = 12
        rotation1.repeatCount = .infinity
        rotation1.fillMode = .forwards
        rotation1.isRemovedOnCompletion = false
        outermostContainer.add(rotation1, forKey: "outermostRotation")
        
        // 第二层：逆时针旋转（正值）
        doubleArcContainer.setValue(0, forKeyPath: "transform.rotation.z")
        let rotation2 = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation2.fromValue = 0
        rotation2.toValue = CGFloat.pi * 2
        rotation2.duration = 4
        rotation2.repeatCount = .infinity
        rotation2.fillMode = .forwards
        rotation2.isRemovedOnCompletion = false
        doubleArcContainer.add(rotation2, forKey: "outerArcRotation")
        
        // 数据环：顺时针旋转（负值）
        dataRingContainer.setValue(0, forKeyPath: "transform.rotation.z")
        let rotation3 = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation3.fromValue = 0
        rotation3.toValue = -CGFloat.pi * 2
        rotation3.duration = 3
        rotation3.repeatCount = .infinity
        rotation3.fillMode = .forwards
        rotation3.isRemovedOnCompletion = false
        dataRingContainer.add(rotation3, forKey: "dataRingRotation")
        
        // 中心环：逆时针旋转（正值）
        centerRingContainer.setValue(0, forKeyPath: "transform.rotation.z")
        let rotation4 = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation4.fromValue = 0
        rotation4.toValue = CGFloat.pi * 2
        rotation4.duration = 8
        rotation4.repeatCount = .infinity
        rotation4.fillMode = .forwards
        rotation4.isRemovedOnCompletion = false
        centerRingContainer.add(rotation4, forKey: "centerRotation")
    }
    
    private func createOutermostRing(center: CGPoint, addAnimation: Bool = true) {
        let radius: CGFloat = 170
        
        for i in 0..<8 {
            let startAngle = CGFloat(i) * (.pi / 4) + 0.2
            let endAngle = startAngle + .pi / 6
            
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle * 180 / .pi, endAngle: endAngle * 180 / .pi, clockwise: false)
            
            let arcLayer = CAShapeLayer()
            arcLayer.path = path.cgPath
            arcLayer.fillColor = NSColor.clear.cgColor
            arcLayer.strokeColor = cyanColor.withAlphaComponent(0.4).cgColor
            arcLayer.lineWidth = 3
            arcLayer.lineCap = .round
            arcLayer.shadowColor = cyanColor.cgColor
            arcLayer.shadowRadius = 8
            arcLayer.shadowOpacity = 0.6
            arcLayer.shadowOffset = .zero
            
            let oscillation = CABasicAnimation(keyPath: "opacity")
            oscillation.fromValue = 0.3
            oscillation.toValue = 0.7
            oscillation.duration = 0.5 + Double(i) * 0.1
            oscillation.autoreverses = true
            oscillation.repeatCount = .infinity
            arcLayer.add(oscillation, forKey: "oscillation")
            
            outermostContainer.addSublayer(arcLayer)
            allLayers.append(arcLayer)
        }
        
        // 最外层旋转动画在 addRotationAnimations() 中统一添加
    }
    
    private func createOuterDoubleArcs(center: CGPoint, addAnimation: Bool = true) {
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi / 6)
            let arcLength: CGFloat = .pi / 10
            let radius: CGFloat = 150
            
            let startAngle = angle
            let endAngle = angle + arcLength
            
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle * 180 / .pi, endAngle: endAngle * 180 / .pi, clockwise: false)
            
            let arcLayer = CAShapeLayer()
            arcLayer.path = path.cgPath
            arcLayer.fillColor = NSColor.clear.cgColor
            arcLayer.strokeColor = cyanColor.withAlphaComponent(0.6).cgColor
            arcLayer.lineWidth = 4
            arcLayer.lineCap = .round
            arcLayer.shadowColor = cyanColor.cgColor
            arcLayer.shadowRadius = 10
            arcLayer.shadowOpacity = 0.8
            arcLayer.shadowOffset = .zero
            
            doubleArcContainer.addSublayer(arcLayer)
            allLayers.append(arcLayer)
        }
        
        for i in 0..<10 {
            let angle = CGFloat(i) * (.pi / 5) + 0.15
            let arcLength: CGFloat = .pi / 8
            let radius: CGFloat = 135
            
            let startAngle = angle
            let endAngle = angle + arcLength
            
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle * 180 / .pi, endAngle: endAngle * 180 / .pi, clockwise: false)
            
            let arcLayer = CAShapeLayer()
            arcLayer.path = path.cgPath
            arcLayer.fillColor = NSColor.clear.cgColor
            arcLayer.strokeColor = cyanColor.withAlphaComponent(0.5).cgColor
            arcLayer.lineWidth = 3.5
            arcLayer.lineCap = .round
            arcLayer.shadowColor = cyanColor.cgColor
            arcLayer.shadowRadius = 8
            arcLayer.shadowOpacity = 0.7
            
            doubleArcContainer.addSublayer(arcLayer)
            allLayers.append(arcLayer)
        }
        
        // 第二层旋转动画在 addRotationAnimations() 中统一添加
    }
    
    private func createDataRing(center: CGPoint, addAnimation: Bool = true) {
        let radius: CGFloat = 100
        let localCenter = CGPoint(x: containerSize / 2, y: containerSize / 2)
        
        let ringPath = NSBezierPath(ovalIn: CGRect(x: localCenter.x - radius, y: localCenter.y - radius, width: radius * 2, height: radius * 2))
        
        let ringLayer = CAShapeLayer()
        ringLayer.path = ringPath.cgPath
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = cyanColor.withAlphaComponent(0.5).cgColor
        ringLayer.lineWidth = 2
        ringLayer.shadowColor = cyanColor.cgColor
        ringLayer.shadowRadius = 6
        ringLayer.shadowOpacity = 0.5
        
        dataRingContainer.addSublayer(ringLayer)
        allLayers.append(ringLayer)
        
        for i in 0..<48 {
            let angle = CGFloat(i) * (.pi / 24)
            let innerR: CGFloat = 62
            let outerR: CGFloat = 70
            
            let x1 = localCenter.x + innerR * cos(angle)
            let y1 = localCenter.y + innerR * sin(angle)
            let x2 = localCenter.x + outerR * cos(angle)
            let y2 = localCenter.y + outerR * sin(angle)
            
            let tickPath = NSBezierPath()
            tickPath.move(to: CGPoint(x: x1, y: y1))
            tickPath.line(to: CGPoint(x: x2, y: y2))
            
            let tickLayer = CAShapeLayer()
            tickLayer.path = tickPath.cgPath
            tickLayer.strokeColor = cyanColor.withAlphaComponent(0.8).cgColor
            tickLayer.lineWidth = 2
            
            dataRingContainer.addSublayer(tickLayer)
            allLayers.append(tickLayer)
        }
        
        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi / 6)
            let dotR: CGFloat = 75
            
            let x = localCenter.x + dotR * cos(angle)
            let y = localCenter.y + dotR * sin(angle)
            
            let dot = CALayer()
            dot.frame = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
            dot.cornerRadius = 2
            dot.backgroundColor = cyanColor.cgColor
            dot.shadowColor = cyanColor.cgColor
            dot.shadowRadius = 5
            dot.shadowOpacity = 0.9
            
            dataRingContainer.addSublayer(dot)
            allLayers.append(dot)
        }
        
        // 数据环旋转动画在 addRotationAnimations() 中统一添加
    }
    
    private func createCenterRing(center: CGPoint, addAnimation: Bool = true) {
        let radius: CGFloat = 22
        let localCenter = CGPoint(x: containerSize / 2, y: containerSize / 2)
        
        let ringPath = NSBezierPath(ovalIn: CGRect(x: localCenter.x - radius, y: localCenter.y - radius, width: radius * 2, height: radius * 2))
        
        centerRingLayer = CAShapeLayer()
        centerRingLayer.path = ringPath.cgPath
        centerRingLayer.fillColor = NSColor.clear.cgColor
        centerRingLayer.strokeColor = cyanColor.cgColor
        centerRingLayer.lineWidth = 10
        centerRingLayer.shadowColor = cyanColor.cgColor
        centerRingLayer.shadowRadius = 15
        centerRingLayer.shadowOpacity = 1.0
        centerRingLayer.shadowOffset = .zero
        
        centerRingContainer.addSublayer(centerRingLayer)
        
        // 中心环旋转动画在 addRotationAnimations() 中统一添加
        
        let glowLayer = CALayer()
        glowLayer.frame = CGRect(x: localCenter.x - 18, y: localCenter.y - 18, width: 36, height: 36)
        glowLayer.cornerRadius = 18
        glowLayer.backgroundColor = cyanColor.withAlphaComponent(0.2).cgColor
        glowLayer.shadowColor = cyanColor.cgColor
        glowLayer.shadowRadius = 20
        glowLayer.shadowOpacity = 0.8
        glowLayer.shadowOffset = .zero
        
        centerRingContainer.addSublayer(glowLayer)
        allLayers.append(glowLayer)
    }
    
    private func createTextLayer(center: CGPoint) {
        textLayer = CATextLayer()
        textLayer.string = "J.A.R.V.I.S."
        textLayer.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        textLayer.fontSize = 18
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 2.0
        
        let textSize = CGSize(width: 150, height: 24)
        textLayer.frame = CGRect(
            x: mainContainerLayer.position.x - textSize.width / 2,
            y: mainContainerLayer.position.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        textLayer.shadowColor = cyanColor.cgColor
        textLayer.shadowRadius = 10
        textLayer.shadowOpacity = 1.0
        textLayer.shadowOffset = .zero
        
        layer?.addSublayer(textLayer)
        
        // 用户文字区域 - 在圆环下方
        userTextLayer = CATextLayer()
        userTextLayer.string = ""
        userTextLayer.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        userTextLayer.fontSize = 14
        userTextLayer.foregroundColor = NSColor.white.withAlphaComponent(0.8).cgColor
        userTextLayer.alignmentMode = .left
        userTextLayer.contentsScale = 2.0
        userTextLayer.isWrapped = true
        userTextLayer.truncationMode = .end
        
        let userTextSize = CGSize(width: 450, height: 40)
        userTextLayer.frame = CGRect(
            x: mainContainerLayer.position.x - userTextSize.width / 2,
            y: mainContainerLayer.position.y - 270,
            width: userTextSize.width,
            height: userTextSize.height
        )
        
        userTextLayer.shadowColor = cyanColor.cgColor
        userTextLayer.shadowRadius = 5
        userTextLayer.shadowOpacity = 0.5
        userTextLayer.shadowOffset = .zero
        
        layer?.addSublayer(userTextLayer)
        
        // AI 文字区域 - 在用户文字下方（带滚动效果）
        aiTextLayer = CATextLayer()
        aiTextLayer.string = ""
        aiTextLayer.fontSize = 14
        aiTextLayer.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        aiTextLayer.foregroundColor = cyanColor.withAlphaComponent(0.9).cgColor
        aiTextLayer.alignmentMode = .left
        aiTextLayer.contentsScale = 2.0
        aiTextLayer.isWrapped = true
        aiTextLayer.truncationMode = .end
        
        // 增大高度以显示多行，实现滚动效果
        let aiTextSize = CGSize(width: 450, height: 100)
        aiTextLayer.frame = CGRect(
            x: mainContainerLayer.position.x - aiTextSize.width / 2,
            y: mainContainerLayer.position.y - 380,
            width: aiTextSize.width,
            height: aiTextSize.height
        )
        
        aiTextLayer.shadowColor = cyanColor.cgColor
        aiTextLayer.shadowRadius = 5
        aiTextLayer.shadowOpacity = 0.5
        aiTextLayer.shadowOffset = .zero
        
        layer?.addSublayer(aiTextLayer)
    }
    
    func updateUserText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            let truncated = text.count > 100 ? String(text.prefix(100)) + "..." : text
            self?.userTextLayer?.string = truncated
        }
    }
    
    func updateAIText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 将文本按行分割，保留最后 maxAILines 行实现滚动效果
            let lines = text.components(separatedBy: .newlines)
                .flatMap { $0.components(separatedBy: "。") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            // 更新历史记录
            self.aiTextHistory = lines
            
            // 只保留最后 maxAILines 行
            let displayLines = Array(lines.suffix(self.maxAILines))
            let displayText = displayLines.joined(separator: "\n")
            
            self.aiTextLayer?.string = displayText
        }
    }
    
    func clearTexts() {
        DispatchQueue.main.async { [weak self] in
            self?.userTextLayer?.string = ""
            self?.aiTextLayer?.string = ""
            self?.aiTextHistory.removeAll()
        }
    }
    
    func showWakeEffect() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // 清除所有子容器的内容
        outermostContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        doubleArcContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        dataRingContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        centerRingContainer.sublayers?.forEach { $0.removeFromSuperlayer() }
        allLayers.removeAll()
        
        // 重置所有容器的位置和锚点，确保旋转中心正确
        let center = CGPoint(x: containerSize / 2, y: containerSize / 2)
        
        if let screen = NSScreen.main {
            mainContainerLayer.position = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        }
        
        // 关键：移除之前的所有动画，并重置变换矩阵
        outermostContainer.removeAllAnimations()
        outermostContainer.transform = CATransform3DIdentity
        outermostContainer.position = center
        outermostContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        doubleArcContainer.removeAllAnimations()
        doubleArcContainer.transform = CATransform3DIdentity
        doubleArcContainer.position = center
        doubleArcContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        dataRingContainer.removeAllAnimations()
        dataRingContainer.transform = CATransform3DIdentity
        dataRingContainer.position = center
        dataRingContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        centerRingContainer.removeAllAnimations()
        centerRingContainer.transform = CATransform3DIdentity
        centerRingContainer.position = center
        centerRingContainer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        
        createAllLayers(addAnimations: false)
        
        for layer in allLayers {
            layer.opacity = 1.0
        }
        centerRingLayer?.opacity = 1.0
        textLayer?.opacity = 1.0
        
        CATransaction.commit()
        
        // 在 CATransaction 提交后再添加动画，避免初始跳跃
        addRotationAnimations()
        
        for layer in allLayers {
            let pulse = CABasicAnimation(keyPath: "transform.scale")
            pulse.fromValue = 0.95
            pulse.toValue = 1.05
            pulse.duration = 0.5
            pulse.autoreverses = true
            pulse.repeatCount = 3
            layer.add(pulse, forKey: "pulse")
        }
    }
    
    func hideEffects() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            for layer in self.allLayers {
                layer.opacity = 0.0
            }
            self.centerRingLayer?.opacity = 0.0
            self.textLayer?.opacity = 0.0
        })
    }
    
    func showProcessing() {
        for layer in allLayers {
            layer.opacity = 1.0
        }
        centerRingLayer?.opacity = 1.0
        textLayer?.opacity = 1.0
    }
    
    func showSuccess() {
        for layer in allLayers {
            layer.opacity = 1.0
            layer.shadowColor = NSColor.green.cgColor
        }
        centerRingLayer?.strokeColor = NSColor.green.cgColor
        centerRingLayer?.shadowColor = NSColor.green.cgColor
        textLayer?.foregroundColor = NSColor.green.cgColor
        textLayer?.shadowColor = NSColor.green.cgColor
    }
    
    func showError() {
        for layer in allLayers {
            layer.opacity = 1.0
            layer.shadowColor = NSColor.red.cgColor
        }
        centerRingLayer?.strokeColor = NSColor.red.cgColor
        centerRingLayer?.shadowColor = NSColor.red.cgColor
        textLayer?.foregroundColor = NSColor.red.cgColor
        textLayer?.shadowColor = NSColor.red.cgColor
    }
}

class SocketServer {
    var serverSocket: Int32 = -1
    var clientSocket: Int32 = -1
    var isRunning = false
    
    func start(port: UInt16) -> Bool {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return false }
        
        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else { return false }
        guard listen(serverSocket, 5) >= 0 else { return false }
        
        isRunning = true
        return true
    }
    
    func acceptClient() -> Int32? {
        guard isRunning else { return nil }
        
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverSocket, sockPtr, &addrLen)
            }
        }
        
        guard client >= 0 else { return nil }
        clientSocket = client
        return client
    }
    
    func receiveMessage() -> String? {
        guard clientSocket >= 0 else { return nil }
        
        var buffer = [CChar](repeating: 0, count: 256)
        let bytesRead = recv(clientSocket, &buffer, buffer.count - 1, 0)
        
        guard bytesRead > 0 else { return nil }
        return String(cString: buffer)
    }
    
    func closeClient() {
        if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }
    }
    
    func stop() {
        isRunning = false
        closeClient()
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: JARVISOverlayWindow!
    var socketServer: SocketServer!
    var serverThread: Thread?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = JARVISOverlayWindow()
        
        socketServer = SocketServer()
        
        serverThread = Thread { [weak self] in
            self?.runServer()
        }
        serverThread?.start()
    }
    
    func runServer() {
        guard socketServer.start(port: 17889) else { return }
        
        while socketServer.isRunning {
            if let client = socketServer.acceptClient() {
                while socketServer.isRunning {
                    if let message = socketServer.receiveMessage() {
                        handleMessage(message)
                    } else { break }
                }
                socketServer.closeClient()
            }
            usleep(100000)
        }
    }
    
    func handleMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed == "wake" { doUIForWake() }
        else if trimmed == "hide" { doUIForHide() }
        else if trimmed == "processing" { doUIForProcessing() }
        else if trimmed == "success" { doUIForSuccess() }
        else if trimmed == "error" { doUIForError() }
        else if trimmed.hasPrefix("user:") {
            let text = String(trimmed.dropFirst(5))
            doUIForUserText(text)
        }
        else if trimmed.hasPrefix("ai:") {
            let text = String(trimmed.dropFirst(3))
            doUIForAIText(text)
        }
    }
    
    func doUIForUserText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.window?.contentView as? JARVISOverlayView else { return }
            view.updateUserText(text)
        }
    }
    
    func doUIForAIText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.window?.contentView as? JARVISOverlayView else { return }
            view.updateAIText(text)
        }
    }
    
    func doUIForWake() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let view = self.window?.contentView as? JARVISOverlayView else { return }
            
            if let screen = NSScreen.main {
                self.window?.setFrame(screen.frame, display: true)
            }
            
            self.window?.orderFrontRegardless()
            self.window?.alphaValue = 1.0
            view.showWakeEffect()
        }
    }
    
    func doUIForHide() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let view = self.window?.contentView as? JARVISOverlayView else { return }
            view.hideEffects()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.window?.animator().alphaValue = 0.0
            }, completionHandler: {
                self.window?.orderOut(nil)
            })
        }
    }
    
    func doUIForProcessing() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let view = self.window?.contentView as? JARVISOverlayView else { return }
            
            if let screen = NSScreen.main {
                self.window?.setFrame(screen.frame, display: true)
            }
            
            self.window?.orderFrontRegardless()
            view.showProcessing()
        }
    }
    
    func doUIForSuccess() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let view = self.window?.contentView as? JARVISOverlayView else { return }
            view.showSuccess()
        }
    }
    
    func doUIForError() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let view = self.window?.contentView as? JARVISOverlayView else { return }
            view.showError()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        socketServer.stop()
        serverThread?.cancel()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
