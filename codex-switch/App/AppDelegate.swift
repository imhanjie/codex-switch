import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = iconImage
        }

        let viewModel = MenuBarViewModel()
        statusBarController = StatusBarController(viewModel: viewModel)
    }
}
