import AppKit

@main
@MainActor
enum UsageApp {
    static func main() {
        let application = NSApplication.shared
        let coordinator = AppCoordinator()
        application.delegate = coordinator
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(coordinator) {
            application.run()
        }
    }
}
