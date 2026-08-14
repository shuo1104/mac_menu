import AppKit

@MainActor
final class NotchOutsideClickMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onOutsideClick: (() -> Void)?

    func start(onOutsideClick: @escaping () -> Void) {
        stop()
        self.onOutsideClick = onOutsideClick

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleClick()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handleClick()
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        onOutsideClick = nil
    }

    private func handleClick() {
        let point = NSEvent.mouseLocation
        // Any visible window owned by this process counts as "inside"
        // (Settings, open panels, onboarding), not only the notch panel.
        let clickedOwnWindow = NSApp.windows.contains { window in
            window.isVisible && window.frame.contains(point)
        }

        if !clickedOwnWindow {
            onOutsideClick?()
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
