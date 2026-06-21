import AppKit
import QuartzCore

/// The expensive render component. In this demo it is owned by the PortalManager
/// and lives in an overlay attached to the window's content view — it is NEVER
/// inside a SwiftUI `NSViewRepresentable`, so SwiftUI cannot tear it down.
final class ExpensiveRenderer {
    static var creationCount = 0

    let rootLayer = CALayer()
    private let spinner = CALayer()
    private let tick = CATextLayer()
    private var timer: Timer?
    private var ticks = 0
    private let instance: Int
    private let createdAt = Date()

    init(simulatedCostSeconds: Double = 1.0) {
        ExpensiveRenderer.creationCount += 1
        instance = ExpensiveRenderer.creationCount

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        rootLayer.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.30).cgColor

        spinner.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        spinner.cornerRadius = 10
        spinner.borderWidth = 6
        spinner.borderColor = NSColor.systemBlue.cgColor
        spinner.shadowColor = NSColor.black.cgColor
        spinner.shadowOpacity = 0.35
        spinner.shadowRadius = 10
        rootLayer.addSublayer(spinner)

        tick.foregroundColor = NSColor.white.cgColor
        tick.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        tick.cornerRadius = 6
        tick.alignmentMode = .center
        tick.fontSize = 13
        tick.isWrapped = true
        tick.contentsScale = scale
        tick.zPosition = 10
        rootLayer.addSublayer(tick)

        if simulatedCostSeconds > 0 { Thread.sleep(forTimeInterval: simulatedCostSeconds) }

        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = 0
        rot.toValue = Double.pi * 2
        rot.duration = 3
        rot.repeatCount = .infinity
        rot.isRemovedOnCompletion = false
        spinner.add(rot, forKey: "spin")

        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickUpdate() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSLog("🛠  ExpensiveRenderer #\(instance) built (portal-owned)")
    }

    deinit { timer?.invalidate() }

    func layout() {
        let b = rootLayer.bounds
        guard b.width > 0, b.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(b.width, b.height) * 0.30
        spinner.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        spinner.position = CGPoint(x: b.midX, y: b.midY)
        tick.frame = CGRect(x: b.midX - 130, y: b.midY - 36, width: 260, height: 72)
        CATransaction.commit()
    }

    private func tickUpdate() {
        ticks += 1
        let alive = Date().timeIntervalSince(createdAt)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tick.string = """
        PORTAL renderer #\(instance)
        ticks: \(ticks)   alive: \(String(format: "%.1f", alive))s
        never inside SwiftUI's view tree
        """
        CATransaction.commit()
    }
}
