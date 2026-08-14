import Combine
import Defaults
import SwiftUI

final class MMViewModel: NSObject, ObservableObject {
    @ObservedObject private var detector = FullscreenMediaDetector.shared

    @Published private(set) var notchState: NotchState = .closed
    @Published var hideOnClosed = true
    @Published var screenUUID: String?
    @Published var notchSize: CGSize {
        didSet {
            guard notchSize != oldValue else { return }
            NotificationCenter.default.post(
                name: .notchWindowSizeChanged,
                object: self
            )
        }
    }
    @Published var closedNotchSize: CGSize

    private var cancellables: Set<AnyCancellable> = []

    init(screenUUID: String? = nil) {
        self.screenUUID = screenUUID
        let initialSize = getClosedNotchSize(screenUUID: screenUUID)
        notchSize = initialSize
        closedNotchSize = initialSize
        super.init()
        setupFullscreenDetection()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
    }

    private func setupFullscreenDetection() {
        let enabledPublisher = Defaults.publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        Publishers.CombineLatest3(
            screenPublisher,
            detector.$fullscreenStatus.removeDuplicates(),
            enabledPublisher
        )
        .map { screenUUID, fullscreenStatus, enabled in
            enabled && (fullscreenStatus[screenUUID] ?? false)
        }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak self] shouldHide in
            withAnimation(.smooth) {
                self?.hideOnClosed = shouldHide
            }
        }
        .store(in: &cancellables)
    }

    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let isFullscreenWithoutHardwareNotch =
            hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0)
        return isFullscreenWithoutHardwareNotch ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        guard Defaults[.hideTitleBar],
              notchState == .closed,
              effectiveClosedNotchHeight > 0,
              let currentScreen = screenUUID.flatMap({
                  NSScreen.screen(withUUID: $0)
              })
        else {
            return 0
        }

        let menuBarHeight =
            currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        return max(0, menuBarHeight - effectiveClosedNotchHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let frame = getScreenFrame(screenUUID) else { return false }
        let originY = frame.maxY - notchSize.height
        let originX = frame.midX - notchSize.width / 2
        return position.y >= originY
            && position.x >= originX
            && position.x <= originX + notchSize.width
    }

    func open() {
        notchSize = openNotchSize
        notchState = .open
        MusicManager.shared.forceUpdate()
    }

    func close() {
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize
        notchState = .closed
        MMViewCoordinator.shared.sneakPeek.show = false
    }
}
