import SwiftUI
import AppKit

/// The cheap, disposable placeholder that lives in the SwiftUI tree. Its only
/// job is to report where (in window coordinates) the portal content should
/// appear — and to keep reporting as it moves (scroll, resize, window move).
/// SwiftUI may create and destroy this freely; it owns nothing expensive.
final class PortalAnchorNSView: NSView {
    var id = "portal"

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupObservers()
        report()
    }

    override func layout() {
        super.layout()
        report()
    }

    private func setupObservers() {
        let nc = NotificationCenter.default
        nc.removeObserver(self)
        guard window != nil else { return }

        postsFrameChangedNotifications = true
        nc.addObserver(self, selector: #selector(reportNote), name: NSView.frameDidChangeNotification, object: self)

        // Follow scrolling: the enclosing clip view's bounds change on scroll.
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: #selector(reportNote), name: NSView.boundsDidChangeNotification, object: clip)
        }
        if let w = window {
            nc.addObserver(self, selector: #selector(reportNote), name: NSWindow.didResizeNotification, object: w)
            nc.addObserver(self, selector: #selector(reportNote), name: NSWindow.didMoveNotification, object: w)
        }
    }

    @objc private func reportNote() { report() }

    func report() {
        guard let w = window else { return }
        let rect = convert(bounds, to: nil)                                   // window base coords
        let clip = enclosingScrollView.map { $0.contentView.convert($0.contentView.bounds, to: nil) }
        PortalManager.shared.updateAnchor(id: id, windowRect: rect, window: w, clip: clip)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

struct PortalAnchor: NSViewRepresentable {
    let id: String

    func makeNSView(context: Context) -> PortalAnchorNSView {
        PortalManager.shared.anchorAppeared(id: id)
        let v = PortalAnchorNSView()
        v.id = id
        return v
    }

    func updateNSView(_ nsView: PortalAnchorNSView, context: Context) {
        nsView.id = id
        nsView.report()
    }

    static func dismantleNSView(_ nsView: PortalAnchorNSView, coordinator: ()) {
        PortalManager.shared.anchorDisappeared(id: nsView.id)
    }
}
