import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let viewModel = MenuBarViewModel()
        statusBarController = StatusBarController(viewModel: viewModel)
    }
}
