import AppKit
import Carbon.HIToolbox
import SwiftUI

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let panel: FloatingPanel
    private let appState: AppState
    private var localEventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Late")
            button.imagePosition = .imageLeading
            button.title = " Late"
            button.target = self
            button.action = #selector(togglePanelFromStatusItem)
        }

        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.contentViewController = NSHostingController(
            rootView: WorkspaceView()
                .environmentObject(appState)
        )
        installLocalShortcuts()
    }

    deinit {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
    }

    @objc private func togglePanelFromStatusItem() {
        togglePanel()
    }

    func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        showPanel()
    }

    func showPanel() {
        centerPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Task { @MainActor [appState] in
            appState.focusPrompt()
        }
    }

    private func centerPanel() {
        let screen = screenContainingMouse() ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.midY - panelSize.height / 2 + 28
        )
        panel.setFrameOrigin(origin)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
    }

    private func installLocalShortcuts() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                self.panel.orderOut(nil)
                return nil
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == UInt16(kVK_ANSI_B), modifiers.contains(.command) {
                Task { @MainActor [appState] in
                    appState.toggleHistory()
                }
                return nil
            }

            return event
        }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            orderOut(nil)
            return
        }

        super.keyDown(with: event)
    }
}
