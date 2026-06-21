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

    // MARK: - Accessibility bridge
    //
    // The overlay content lives under NSThemeFrame, divorced from its logical
    // position — so by default VoiceOver finds it out of reading order (or not at
    // all, since the placeholder is empty). This placeholder IS in the right spot
    // in the SwiftUI/AX tree, so we make it ADOPT the content: VoiceOver reaches
    // it in order and finds the portal content's element here, framed on-screen
    // where the content actually is. (The overlay is marked non-accessible in
    // PortalManager so it isn't also exposed out of place.)

    private lazy var contentElement: NSAccessibilityElement = {
        let e = NSAccessibilityElement()
        e.setAccessibilityRole(.staticText)
        e.setAccessibilityLabel("Portal renderer")
        e.setAccessibilityParent(self)
        return e
    }()

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Portal content region" }

    override func accessibilityChildren() -> [Any]? {
        // Updated on demand (VoiceOver reads when focused), so value + frame are
        // always current even after scrolling.
        contentElement.setAccessibilityValue(PortalManager.shared.contentAccessibilityValue)
        contentElement.setAccessibilityFrame(contentScreenFrame())
        return [contentElement]
    }

    /// The on-screen rect the content occupies (so the VoiceOver cursor lands on it).
    private func contentScreenFrame() -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }
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
