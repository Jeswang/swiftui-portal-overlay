# SwiftUI Portal / Overlay Demo

Exploring **Option B (portal / overlay, full form)**: hosting an expensive
render component **entirely outside SwiftUI's view hierarchy**. SwiftUI never
owns the content — it only places a cheap **placeholder** whose frame an overlay
tracks.

This is the counterpart to the reparenting/pooling approach in
[swiftui-calayer-hosting](https://github.com/Jeswang/swiftui-calayer-hosting).
There the expensive view lived *inside* a `NSViewRepresentable` (and we fought
SwiftUI's teardown + the WindowServer fence). Here it never enters SwiftUI's
tree at all, so those problems can't occur by construction.

## How it works

- `ExpensiveRenderer` (the heavy CALayer content) is owned by `PortalManager`,
  built **once**, and drawn in an overlay `NSView` attached directly to the
  window's `contentView` — above the SwiftUI hosting view.
- `PortalAnchor` is a tiny, disposable `NSViewRepresentable` placeholder in the
  SwiftUI layout. On layout / scroll / window move it reports its rect in window
  coordinates (`convert(bounds, to: nil)`) to the manager.
- `PortalManager` positions the overlay to match, intersecting with the
  enclosing scroll view's viewport to clip.

```
SwiftUI tree:   … → PortalAnchor (cheap placeholder, reports its frame)
window.contentView
  ├─ NSHostingView (SwiftUI)
  └─ overlay NSView  ← ExpensiveRenderer lives here, tracks the placeholder
```

## Run

```sh
swift run
```

## What to try

- **Force teardown (toggle .id)** — SwiftUI destroys & recreates the placeholder
  on every click. `Anchor dismantles`/`makes` climb; **`Renderer builds` stays 1**
  and the spinner never even flinches. The content isn't in the torn-down subtree.
- **Present placeholder off** — removes the placeholder entirely; the overlay
  hides. Toggle back on: same renderer, still spinning, `builds` still 1.
- **In ScrollView** — the overlay follows the placeholder as you scroll and
  **clips to the scroll viewport** (`clipped` indicator). Resize the window — it
  tracks that too.
- Watch **`Content left window` = 0** the whole time: the content is parented to
  the window once and never leaves, so it never triggers a CoreAnimation fence.

## Tradeoffs (the honest part)

The portal buys total immunity from SwiftUI's lifecycle, but you give up SwiftUI
composition and inherit manual bookkeeping:

- **Frame sync is yours.** Scroll, resize, window move, live-resize, full-screen,
  Spaces — every geometry change must be tracked (here via frame/bounds/window
  notifications). Anything you miss = the overlay lagging or detached.
- **Clipping & masking are manual.** Nested scroll views, corner radius, shadows,
  `.clipShape`, transforms — none compose; you replicate them by hand.
- **Z-order.** This variant draws the content *above* the hosting view, so it
  covers (and takes mouse events from) any SwiftUI on top of it. To put SwiftUI
  controls over the content you need the **content-below + transparent-hole**
  variant (overlay added `.below` the hosting view, with the placeholder region
  punched transparent via a mask) — more faithful to the classic map-view trick,
  and noted here as the next step.
- **No SwiftUI transitions/animations** apply to the content.
- **Accessibility is wrong by default** — see below.

## Accessibility bridge

macOS's accessibility tree follows the *view hierarchy*. Because the overlay
lives under `NSThemeFrame` (not in the placeholder's logical spot), VoiceOver
finds the content out of reading order — and the placeholder itself is an empty
hole in the tree. So a11y must be bridged back manually:

- The overlay is marked **non-accessible** (`setAccessibilityElement(false)`) so
  it isn't exposed out of place at the window-frame level.
- `PortalAnchor` — which *is* in the right logical position — **adopts** the
  content: it reports itself as a group and vends an `NSAccessibilityElement` for
  the content, framed (in screen coordinates) where the content actually is. So
  VoiceOver reaches it in reading order and lands on the content on-screen.

Verify with **Accessibility Inspector** (hover the placeholder → "Portal content
region" group with a "Portal renderer" child, and no stray group under the
window) or VoiceOver. Still your responsibility beyond this demo: the key-view
(Tab) loop, and clamping the element's frame to the scroll viewport when clipped.

This is itself a reason the reparenting/pooling approach often wins: there the
content stays in a sensible tree location, so accessibility is correct while
visible with no bridging.

Use a portal when you need hard isolation (a continuous render loop, window-level
separation, escaping clipping). For most "don't rebuild my expensive view" cases
the reparenting/pooling approach in the sibling repo is lighter and composes far
better.
