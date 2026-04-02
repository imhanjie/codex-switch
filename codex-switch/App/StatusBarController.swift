import AppKit
import Combine
import SwiftUI

private final class PanelGlassContainerView: NSView {
    init(contentView hostedView: NSView, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true

        // Use the long-supported visual effect view so release builds stay
        // compatible with older GitHub Actions macOS/Xcode runner images.
        let backgroundView = NSVisualEffectView(frame: .zero)
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
        addSubview(hostedView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let viewModel: MenuBarViewModel
    private let statusItem: NSStatusItem
    private var panel: FloatingPanel?
    private var hostingView: NSHostingView<MenuBarPanelView>?
    private var containerView: PanelGlassContainerView?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var themeModeCancellable: AnyCancellable?

    init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        bindThemeMode()
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
        let image = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: "Codex Switch")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func showStatusMenu(from button: NSStatusBarButton, event: NSEvent?) {
        let menu = NSMenu()
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
        panel.invalidateShadow()
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
        let hostingView = NSHostingView(
            rootView: MenuBarPanelView(
                viewModel: viewModel,
                closePanel: { [weak self] in
                    self?.closePanel()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        let containerView = PanelGlassContainerView(contentView: hostingView, cornerRadius: 18)
        panel.contentView = containerView
        self.hostingView = hostingView
        self.containerView = containerView
        applyPanelAppearance(for: viewModel.themeMode)
        panel.invalidateShadow()
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

    private func bindThemeMode() {
        themeModeCancellable = viewModel.$themeMode
            .sink { [weak self] mode in
                self?.applyPanelAppearance(for: mode)
            }
    }

    private func applyPanelAppearance(for mode: PanelThemeMode) {
        let appearance = mode.nsAppearance
        panel?.appearance = appearance
        hostingView?.appearance = appearance
        containerView?.appearance = appearance
        panel?.invalidateShadow()
        panel?.contentView?.needsDisplay = true
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
