import Defaults
import KeyboardShortcuts
import SwiftUI

@main
struct MMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Default(.menubarIcon) private var showMenuBarIcon

    init() {
        WindowHeightMode.migratePersistedValuesIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            Button("Settings") {
                SettingsWindowController.shared.showWindow()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Restart MM") {
                ApplicationRelauncher.restart()
            }

            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            GaugeMenuBarIcon()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [String: NSWindow] = [:]
    private var viewModels: [String: MMViewModel] = [:]
    private var window: NSWindow?
    private let viewModel = MMViewModel()
    private let coordinator = MMViewCoordinator.shared
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked = false
    private var closeNotchTask: Task<Void, Never>?

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(
                screenLockedObserver
            )
        }
        if let screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(
                screenUnlockedObserver
            )
        }
        MusicManager.shared.destroy()
        cleanupWindows()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeDisplayChanges()
        configureKeyboardShortcuts()

        if Defaults[.showOnAllDisplays] {
            adjustWindowPosition(changeAlpha: true)
        } else if let screen = NSScreen.main ?? NSScreen.screens.first {
            window = createNotchWindow(for: screen, viewModel: viewModel)
            adjustWindowPosition(changeAlpha: true)
        }

        // Defer onboarding until MusicManager finishes its deprecation probe so
        // the available-controller list and default preference are correct.
        Task { @MainActor in
            await self.presentOnboardingIfNeeded()
        }

        previousScreens = NSScreen.screens
    }

    private func presentOnboardingIfNeeded() async {
        // Wait briefly for MusicManager's async deprecation check.
        for _ in 0..<40 {
            if MusicManager.shared.didFinishDeprecationCheck {
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }

        let preferred = Defaults[.mediaController]
        let resolved = MediaControllerType.resolved(preferred)
        if resolved != preferred {
            Defaults[.mediaController] = resolved
            NotificationCenter.default.post(
                name: .mediaControllerChanged,
                object: nil
            )
        }

        let needsSourcePick =
            coordinator.firstLaunch
            || (MusicManager.shared.isNowPlayingDeprecated
                && preferred == .nowPlaying)

        if needsSourcePick {
            showMusicSourceOnboarding()
        }
    }

    private func observeDisplayChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: .selectedScreenChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .notchHeightChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .notchWindowSizeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let model = notification.object as? MMViewModel
            else {
                return
            }
            Task { @MainActor in
                self.resizeNotchWindow(for: model)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .automaticallySwitchDisplayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window else { return }
            window.alphaValue =
                self.coordinator.selectedScreenUUID
                == self.coordinator.preferredScreenUUID ? 1 : 0
        }

        NotificationCenter.default.addObserver(
            forName: .showOnAllDisplaysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.cleanupWindows(invertingDisplayMode: true)
            self.adjustWindowPosition(changeAlpha: true)
        }

        NotificationCenter.default.addObserver(
            forName: .cancelNotchAutoClose,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelNotchAutoClose()
            }
        }

        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenLock()
            }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleScreenUnlock()
            }
        }
    }

    private func configureKeyboardShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) {
            let coordinator = MMViewCoordinator.shared
            if Defaults[.sneakPeekStyles] == .inline {
                coordinator.toggleExpandingView(
                    status: !coordinator.expandingView.show
                )
            } else {
                coordinator.toggleSneakPeek(
                    status: !coordinator.sneakPeek.show,
                    duration: 3
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            guard let self else { return }
            let target = self.viewModelUnderMouse()
            self.cancelNotchAutoClose()

            if target.notchState == .closed {
                target.open()
                self.closeNotchTask = Task { [weak target] in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        target?.close()
                    }
                }
            } else {
                target.close()
            }
        }
    }

    private func cancelNotchAutoClose() {
        closeNotchTask?.cancel()
        closeNotchTask = nil
    }

    private func viewModelUnderMouse() -> MMViewModel {
        guard Defaults[.showOnAllDisplays] else { return viewModel }
        let location = NSEvent.mouseLocation

        for screen in NSScreen.screens where screen.frame.contains(location) {
            if let uuid = screen.displayUUID,
               let viewModel = viewModels[uuid] {
                return viewModel
            }
        }
        return viewModel
    }

    private func createNotchWindow(
        for screen: NSScreen,
        viewModel: MMViewModel
    ) -> NSWindow {
        let window = MMSkyLightWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: windowSize.width,
                height: windowSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )

        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        let hostingView = NSHostingView(
            rootView: ContentView().environmentObject(viewModel)
        )
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        return window
    }

    private func position(
        _ window: NSWindow,
        on screen: NSScreen,
        changeAlpha: Bool
    ) {
        if changeAlpha {
            window.alphaValue = 0
        }
        window.setFrameOrigin(
            NSPoint(
                x: screen.frame.midX - window.frame.width / 2,
                y: screen.frame.maxY - window.frame.height
            )
        )
        window.alphaValue = 1
    }

    private func resizeNotchWindow(for model: MMViewModel) {
        let targetWindow: NSWindow?
        if Defaults[.showOnAllDisplays],
           let screenUUID = model.screenUUID {
            targetWindow = windows[screenUUID]
        } else {
            targetWindow = window
        }

        guard let targetWindow,
              let screen = model.screenUUID.flatMap({
                  NSScreen.screen(withUUID: $0)
              }) ?? NSScreen.main
        else {
            return
        }

        let targetHeight = max(
            windowSize.height,
            model.notchSize.height + shadowPadding
        )
        targetWindow.setFrame(
            NSRect(
                x: screen.frame.midX - windowSize.width / 2,
                y: screen.frame.maxY - targetHeight,
                width: windowSize.width,
                height: targetHeight
            ),
            display: true
        )
    }

    @objc
    private func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let activeScreenIDs = Set(
                NSScreen.screens.compactMap(\.displayUUID)
            )

            for uuid in windows.keys where !activeScreenIDs.contains(uuid) {
                if let staleWindow = windows.removeValue(forKey: uuid) {
                    staleWindow.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(staleWindow)
                }
                viewModels.removeValue(forKey: uuid)
            }

            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                if windows[uuid] == nil {
                    let model = MMViewModel(screenUUID: uuid)
                    windows[uuid] = createNotchWindow(
                        for: screen,
                        viewModel: model
                    )
                    viewModels[uuid] = model
                }

                if let window = windows[uuid],
                   let model = viewModels[uuid] {
                    position(window, on: screen, changeAlpha: changeAlpha)
                    // Only recompute closed metrics when closed. Force-closing
                    // an open notch was a regression that wiped dashboard state.
                    if model.notchState == .closed {
                        model.close()
                    } else {
                        resizeNotchWindow(for: model)
                    }
                }
            }
            return
        }

        let selectedScreen: NSScreen?
        if let preferredUUID = coordinator.preferredScreenUUID,
           let preferredScreen = NSScreen.screen(withUUID: preferredUUID) {
            selectedScreen = preferredScreen
        } else if Defaults[.automaticallySwitchDisplay] {
            selectedScreen = NSScreen.main
        } else {
            selectedScreen = nil
        }

        guard let selectedScreen else {
            window?.alphaValue = 0
            return
        }

        coordinator.selectedScreenUUID = selectedScreen.displayUUID ?? ""
        viewModel.screenUUID = selectedScreen.displayUUID

        let closedSize = getClosedNotchSize(
            screenUUID: selectedScreen.displayUUID
        )
        viewModel.closedNotchSize = closedSize
        if viewModel.notchState == .closed {
            viewModel.notchSize = closedSize
        }

        if window == nil {
            window = createNotchWindow(
                for: selectedScreen,
                viewModel: viewModel
            )
        }
        if let window {
            position(window, on: selectedScreen, changeAlpha: changeAlpha)
            if viewModel.notchState == .closed {
                viewModel.close()
            } else {
                resizeNotchWindow(for: viewModel)
            }
        }
    }

    @objc
    private func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens
        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap(\.displayUUID))
                != Set(previousScreens?.compactMap(\.displayUUID) ?? [])
            || Set(currentScreens.map(\.frame))
                != Set(previousScreens?.map(\.frame) ?? [])

        previousScreens = currentScreens
        if screensChanged {
            cleanupWindows()
            adjustWindowPosition()
        }
    }

    private func handleScreenLock() {
        isScreenLocked = true
        if Defaults[.showOnLockScreen] {
            allWindows.forEach {
                ($0 as? MMSkyLightWindow)?.enableSkyLight()
            }
        } else {
            cleanupWindows()
        }
    }

    private func handleScreenUnlock() {
        isScreenLocked = false
        if Defaults[.showOnLockScreen] {
            allWindows.forEach {
                ($0 as? MMSkyLightWindow)?.disableSkyLight()
            }
        } else {
            adjustWindowPosition(changeAlpha: true)
        }
    }

    private var allWindows: [NSWindow] {
        if Defaults[.showOnAllDisplays] {
            return Array(windows.values)
        }
        return window.map { [$0] } ?? []
    }

    private func cleanupWindows(invertingDisplayMode: Bool = false) {
        let cleanMultiple = invertingDisplayMode
            ? !Defaults[.showOnAllDisplays]
            : Defaults[.showOnAllDisplays]

        if cleanMultiple {
            windows.values.forEach {
                $0.close()
                NotchSpaceManager.shared.notchSpace.windows.remove($0)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            self.window = nil
        }
    }

    private func showMusicSourceOnboarding() {
        let onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            // Not closable: closing without finishing left firstLaunch=true
            // and permanently disabled hover-open.
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        onboardingWindow.center()
        onboardingWindow.title = "Choose Music Source"
        onboardingWindow.titlebarAppearsTransparent = true
        onboardingWindow.titleVisibility = .hidden
        onboardingWindow.contentView = NSHostingView(
            rootView: OnboardingView { [weak onboardingWindow] in
                onboardingWindow?.close()
                NSApp.deactivate()
            }
        )
        onboardingWindow.isRestorable = false
        onboardingWindowController = NSWindowController(window: onboardingWindow)

        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let notchWindowSizeChanged = Notification.Name(
        "NotchWindowSizeChanged"
    )
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name(
        "automaticallySwitchDisplayChanged"
    )
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }
}
