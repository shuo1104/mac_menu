import AppKit
import SwiftUI

struct SneakPeekState {
    var show = false
}

struct ExpandedMusicState {
    var show = false
}

@MainActor
final class MMViewCoordinator: ObservableObject {
    static let shared = MMViewCoordinator()

    @AppStorage("firstLaunch") var firstLaunch = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled = true

    @AppStorage("preferred_screen_name")
    private var legacyPreferredScreenName: String?

    @AppStorage("preferred_screen_uuid")
    var preferredScreenUUID: String? {
        didSet {
            if let preferredScreenUUID {
                selectedScreenUUID = preferredScreenUUID
            }
            NotificationCenter.default.post(
                name: .selectedScreenChanged,
                object: nil
            )
        }
    }

    @Published var selectedScreenUUID =
        NSScreen.main?.displayUUID ?? ""
    @Published var sneakPeek = SneakPeekState()
    @Published var expandingView = ExpandedMusicState()

    private var sneakPeekTask: Task<Void, Never>?
    private var expandingViewTask: Task<Void, Never>?

    private init() {
        if preferredScreenUUID == nil,
           let legacyPreferredScreenName,
           let screen = NSScreen.screens.first(where: {
               $0.localizedName == legacyPreferredScreenName
           }) {
            preferredScreenUUID = screen.displayUUID
        }

        if preferredScreenUUID == nil {
            preferredScreenUUID = NSScreen.main?.displayUUID
        }

        selectedScreenUUID = preferredScreenUUID
            ?? NSScreen.main?.displayUUID
            ?? ""
        legacyPreferredScreenName = nil
    }

    func toggleSneakPeek(
        status: Bool,
        duration: TimeInterval = 1.5
    ) {
        sneakPeekTask?.cancel()
        withAnimation(.smooth) {
            sneakPeek.show = status
        }

        guard status else { return }
        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth) {
                    self?.sneakPeek.show = false
                }
            }
        }
    }

    func toggleExpandingView(status: Bool) {
        expandingViewTask?.cancel()
        withAnimation(.smooth) {
            expandingView.show = status
        }

        guard status else { return }
        expandingViewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth) {
                    self?.expandingView.show = false
                }
            }
        }
    }
}
