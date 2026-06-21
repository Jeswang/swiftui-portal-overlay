import SwiftUI
import AppKit

/// Owns the expensive content and an overlay `NSView` that is attached directly
/// to the window's `contentView` — OUTSIDE SwiftUI's hosting view. SwiftUI only
/// supplies a cheap placeholder (`PortalAnchor`) that reports its frame; this
/// manager tracks that frame and positions the overlay to match.
///
/// Because the content never lives in a SwiftUI `NSViewRepresentable`, SwiftUI
/// teardown/rebuild (scroll recycling, `.id()` changes, conditionals) cannot
/// destroy it and cannot pull it out of the window — no rebuild, no fence.
final class PortalManager: ObservableObject {
    static let shared = PortalManager()

    // Live metrics for the UI.
    @Published var rendererBuilds = 0      // how many ExpensiveRenderers ever built (stays 1)
    @Published var anchorMakes = 0         // SwiftUI created the placeholder representable
    @Published var anchorDismantles = 0    // SwiftUI destroyed the placeholder representable
    @Published var overlayLeftWindow = 0   // times the content left its window (stays 0)
    @Published var lastFrame: CGRect = .zero
    @Published var clipped = false

    private var overlay: NSView?
    private var renderer: ExpensiveRenderer?

    private init() {}

    // MARK: - Anchor lifecycle (called by PortalAnchor)

    func anchorAppeared(id: String) {
        DispatchQueue.main.async { self.anchorMakes += 1 }
    }

    func anchorDisappeared(id: String) {
        DispatchQueue.main.async { self.anchorDismantles += 1 }
        overlay?.isHidden = true
    }

    /// Position update. `windowRect` and `clip` are in the window's base
    /// coordinate system (from `view.convert(_, to: nil)`).
    func updateAnchor(id: String, windowRect: CGRect, window: NSWindow, clip: CGRect?) {
        guard let content = window.contentView else { return }
        ensureOverlay(in: window, content: content)
        guard let overlay, let renderer else { return }

        // window base coords -> contentView coords
        let frameInContent = content.convert(windowRect, from: nil)
        let visible = clip.map { frameInContent.intersection(content.convert($0, from: nil)) } ?? frameInContent

        overlay.isHidden = visible.isEmpty
        overlay.frame = visible.isEmpty ? frameInContent : visible

        // Offset the content layer so the *visible* slice lines up when clipped
        // (the overlay's layer masks to its bounds).
        let offX = frameInContent.minX - overlay.frame.minX
        let offY = frameInContent.minY - overlay.frame.minY
        renderer.rootLayer.frame = CGRect(x: offX, y: offY,
                                          width: frameInContent.width, height: frameInContent.height)
        renderer.layout()

        let didClip = !visible.equalTo(frameInContent)
        DispatchQueue.main.async {
            self.lastFrame = windowRect
            self.clipped = didClip
        }
    }

    // MARK: - Overlay management

    private func ensureOverlay(in window: NSWindow, content: NSView) {
        if overlay == nil {
            let host = NSView(frame: .zero)
            host.wantsLayer = true
            host.layer?.masksToBounds = true
            host.layer?.cornerRadius = 10
            let r = ExpensiveRenderer()              // built exactly once, here, off the SwiftUI tree
            host.layer?.addSublayer(r.rootLayer)
            overlay = host
            renderer = r
            DispatchQueue.main.async { self.rendererBuilds = ExpensiveRenderer.creationCount }
        }
        guard let overlay else { return }
        // Attach above the SwiftUI hosting view. This happens once; the overlay
        // then lives in the window for good (so the count below stays 0).
        if overlay.window !== window {
            if overlay.window != nil { DispatchQueue.main.async { self.overlayLeftWindow += 1 } }
            overlay.removeFromSuperview()
            content.addSubview(overlay, positioned: .above, relativeTo: nil)
        } else if overlay.superview == nil {
            content.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
    }
}
