import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let viewModel: MenuBarViewModel
    private let statusItem: NSStatusItem
    private var panel: FloatingPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        let event = NSApp.currentEvent

        if event?.type == .rightMouseUp {
            closePanel()
            showStatusMenu(from: button, event: event)
        } else {
            togglePanel(relativeTo: button)
        }
    }

    @objc private func captureCurrentAccount() {
        viewModel.captureCurrentAccount()
    }

    @objc private func loginNewAccount() {
        viewModel.loginNewAccount()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Codex Switch")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func showStatusMenu(from button: NSStatusBarButton, event: NSEvent?) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "收录当前账号", action: #selector(captureCurrentAccount), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "登录新账号", action: #selector(loginNewAccount), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApplication), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        button.highlight(true)
        if let event {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 6), in: button)
        }
        button.highlight(false)
    }

    private func togglePanel(relativeTo button: NSStatusBarButton) {
        if let panel, panel.isVisible {
            closePanel()
            return
        }

        let panel = makePanelIfNeeded()
        positionPanel(panel, relativeTo: button)
        statusItem.button?.highlight(true)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
        viewModel.loadPanel()
    }

    private func makePanelIfNeeded() -> FloatingPanel {
        if let panel {
            return panel
        }

        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 640))
        panel.delegate = self
        panel.onCancel = { [weak self] in
            self?.closePanel()
        }
        panel.contentView = NSHostingView(rootView: MenuBarPanelView(viewModel: viewModel))
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: FloatingPanel, relativeTo button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        let desiredX = buttonFrameOnScreen.maxX - panel.frame.width
        let clampedX = max(visibleFrame.minX + 8, min(desiredX, visibleFrame.maxX - panel.frame.width - 8))
        let desiredY = buttonFrameOnScreen.minY - panel.frame.height - 8
        let minY = visibleFrame.minY + 8
        panel.setFrameOrigin(NSPoint(x: clampedX, y: max(desiredY, minY)))
    }

    private func closePanel() {
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        removeEventMonitors()
    }

    private func installEventMonitors() {
        removeEventMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanelIfNeeded(for: NSEvent.mouseLocation)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.closePanelIfNeeded(for: NSEvent.mouseLocation)
            return event
        }
    }

    private func removeEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func closePanelIfNeeded(for screenPoint: NSPoint) {
        guard let panel, panel.isVisible else { return }

        let inPanel = panel.frame.contains(screenPoint)
        let inStatusItem = statusItem.button.flatMap { button in
            guard let window = button.window else { return false }
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            return buttonFrame.contains(screenPoint)
        } ?? false

        if !inPanel && !inStatusItem {
            closePanel()
        }
    }
}
