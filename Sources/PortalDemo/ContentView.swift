import SwiftUI

struct ContentView: View {
    @StateObject private var portal = PortalManager.shared

    @State private var identity = 0       // bump to force SwiftUI to tear down the placeholder
    @State private var present = true     // conditionally remove the placeholder entirely
    @State private var inScrollView = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            metricsPanel
            Divider()
            stage
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 700)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Portal / overlay: content hosted entirely outside SwiftUI")
                .font(.title2).bold()
            Text("The spinning content is owned by a manager and drawn in an overlay on the window's content view. SwiftUI only places a placeholder that reports its frame. The overlay tracks it.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { identity += 1 } label: {
                Label("Force teardown (toggle .id)", systemImage: "arrow.triangle.2.circlepath")
            }
            Toggle("Present placeholder", isOn: $present).toggleStyle(.switch)
            Toggle("In ScrollView", isOn: $inScrollView).toggleStyle(.switch)
            Spacer()
        }
    }

    private var metricsPanel: some View {
        HStack(spacing: 22) {
            stat("Renderer builds", portal.rendererBuilds,
                 color: portal.rendererBuilds <= 1 ? .green : .red, hint: "stays 1 forever")
            stat("Content left window", portal.overlayLeftWindow,
                 color: portal.overlayLeftWindow == 0 ? .green : .red, hint: "never → no fence")
            stat("Anchor makes", portal.anchorMakes, color: .primary, hint: "SwiftUI churn")
            stat("Anchor dismantles", portal.anchorDismantles, color: .primary, hint: "harmless")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
        .overlay(alignment: .bottomTrailing) {
            Text(portal.clipped ? "clipped to scroll viewport" : "frame: \(Int(portal.lastFrame.width))×\(Int(portal.lastFrame.height))")
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }
    }

    private func stat(_ title: String, _ value: Int, color: Color, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.title2).monospacedDigit().foregroundColor(color)
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // The placeholder, with a dashed outline so you can see SwiftUI's slot.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .foregroundStyle(.secondary)
            VStack {
                Spacer()
                Text("SwiftUI placeholder — content rendered by the portal above")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
            if present {
                PortalAnchor(id: "main")
                    .id(identity)   // changing identity forces make/dismantle of the placeholder
            }
        }
        .frame(height: 260)
    }

    @ViewBuilder private var stage: some View {
        if inScrollView {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(0..<6) { i in filler(i) }
                    placeholder
                    ForEach(6..<12) { i in filler(i) }
                }
                .padding(.vertical, 8)
            }
        } else {
            placeholder
            Spacer()
        }
    }

    private func filler(_ i: Int) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.10))
            .frame(height: 60)
            .overlay(Text("scroll filler \(i)").font(.caption).foregroundStyle(.secondary))
    }
}
