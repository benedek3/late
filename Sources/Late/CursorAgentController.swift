import AppKit
import SwiftUI

final class CursorAgentController {
    private let panel: NSPanel
    private var trackingTimer: Timer?
    private let offset = NSPoint(x: 14, y: -14)

    init(appState: AppState) {
        self.panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 156, height: 58),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentViewController = NSHostingController(
            rootView: CursorAgentView()
                .environmentObject(appState)
        )
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            startTracking()
            panel.orderFrontRegardless()
        } else {
            stopTracking()
            panel.orderOut(nil)
        }
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        updatePosition()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updatePosition()
        }
        if let trackingTimer {
            RunLoop.main.add(trackingTimer, forMode: .common)
        }
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updatePosition() {
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: mouseLocation.x + offset.x,
            y: mouseLocation.y + offset.y - panelSize.height
        )
        panel.setFrameOrigin(clampedOrigin(origin, panelSize: panelSize))
    }

    private func clampedOrigin(_ origin: NSPoint, panelSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            return origin
        }

        let frame = screen.visibleFrame
        return NSPoint(
            x: min(max(origin.x, frame.minX + 8), frame.maxX - panelSize.width - 8),
            y: min(max(origin.y, frame.minY + 8), frame.maxY - panelSize.height - 8)
        )
    }
}

private struct CursorAgentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isBreathing = false

    var body: some View {
        HStack(spacing: 9) {
            agentOrb

            VStack(alignment: .leading, spacing: 1) {
                Text(agentTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(agentSubtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 6)
        .padding(7)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private var agentOrb: some View {
        ZStack {
            Circle()
                .stroke(agentAccent.opacity(appState.isLoading ? 0.48 : 0.24), lineWidth: 4)
                .scaleEffect(isBreathing ? 1.22 : 0.94)
                .opacity(isBreathing ? 0.18 : 0.5)

            Circle()
                .fill(Color.white)

            Image(systemName: appState.isLoading ? "sparkles" : "cursorarrow.rays")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
        }
        .frame(width: 30, height: 30)
    }

    private var agentTitle: String {
        if appState.isLoading {
            return "Working"
        }

        if appState.isTranslationMode {
            return "Translate"
        }

        return "Agent"
    }

    private var agentSubtitle: String {
        if appState.isLoading {
            return "following cursor"
        }

        if appState.isTranslationMode {
            return "ready"
        }

        return "around cursor"
    }

    private var agentAccent: Color {
        if appState.isLoading {
            return .white
        }

        if appState.isTranslationMode {
            return .green
        }

        return .accentColor
    }
}
