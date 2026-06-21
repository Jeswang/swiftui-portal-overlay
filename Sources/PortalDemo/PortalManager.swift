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

    /// Live a11y value for the content the placeholder adopts (see PortalAnchor).
    var contentAccessibilityValue: String { renderer?.accessibilityStatus ?? "initializing" }

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
        // Attach ABOVE SwiftUI's hosting content view by using the window's frame
        // view (contentView.superview). SwiftUI owns and continuously reorders its
        // own subtree, so a subview added there gets buried; the frame view doesn't.
        guard let host = window.contentView?.superview ?? window.contentView else { return }
        ensureOverlay(in: window, host: host)
        guard let overlay, let renderer else { return }

        // window base coords -> host coords
        let frameInContent = host.convert(windowRect, from: nil)
        let visible = clip.map { frameInContent.intersection(host.convert($0, from: nil)) } ?? frameInContent

        // Disable implicit CA animations: when the bottom edge clips we shift the
        // content layer's origin every scroll tick, and the default 0.25s action
        // would make it visibly "bounce"/swim. Position must be instantaneous.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        overlay.isHidden = visible.isEmpty
        overlay.frame = visible.isEmpty ? frameInContent : visible

        // Offset the content layer so the *visible* slice lines up when clipped
        // (the overlay's layer masks to its bounds).
        let offX = frameInContent.minX - overlay.frame.minX
        let offY = frameInContent.minY - overlay.frame.minY
        renderer.rootLayer.frame = CGRect(x: offX, y: offY,
                                          width: frameInContent.width, height: frameInContent.height)
        renderer.layout()

        CATransaction.commit()

        let didClip = !visible.equalTo(frameInContent)
        DispatchQueue.main.async {
            self.lastFrame = windowRect
            self.clipped = didClip
        }
    }

    // MARK: - Overlay management

    private func ensureOverlay(in window: NSWindow, host: NSView) {
        if overlay == nil {
            let v = NSView(frame: .zero)
            v.wantsLayer = true
            v.layer?.masksToBounds = true
            v.layer?.cornerRadius = 10
            // a11y bridge: the overlay sits under NSThemeFrame, out of logical
            // position. Hide it from accessibility; the placeholder exposes the
            // content instead, in the right spot in the tree.
            v.setAccessibilityElement(false)
            let r = ExpensiveRenderer()              // built exactly once, here, off the SwiftUI tree
            v.layer?.addSublayer(r.rootLayer)
            overlay = v
            renderer = r
            DispatchQueue.main.async { self.rendererBuilds = ExpensiveRenderer.creationCount }
        }
        guard let overlay else { return }
        // Attach to the frame view, above SwiftUI. Happens once; the overlay then
        // lives in the window for good (so the count below stays 0).
        if overlay.superview !== host {
            if overlay.window != nil { DispatchQueue.main.async { self.overlayLeftWindow += 1 } }
            overlay.removeFromSuperview()
            host.addSubview(overlay, positioned: .above, relativeTo: nil)
        }
    }
}
