import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    var body: some View {
        MusicControllerSelectionView {
            MMViewCoordinator.shared.firstLaunch = false
            onFinish()
        }
        .frame(width: 400, height: 600)
    }
}
