import AppKit

@main
@MainActor
enum UsageApp {
    static func main() {
        let application = NSApplication.shared
        guard !hasEarlierInstance else { return }
        let coordinator = AppCoordinator()
        application.delegate = coordinator
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(coordinator) {
            application.run()
        }
    }

    private static var hasEarlierInstance: Bool {
        let current = NSRunningApplication.current
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains { instance in
            guard instance.processIdentifier != current.processIdentifier, !instance.isTerminated else { return false }
            if instance.isFinishedLaunching { return true }
            if let launch = instance.launchDate, let currentLaunch = current.launchDate, launch != currentLaunch {
                return launch < currentLaunch
            }
            return instance.processIdentifier < current.processIdentifier
        }
    }
}
