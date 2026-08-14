import SwiftUI

enum NotchDashboardPage: String, CaseIterable, Identifiable {
    case home
    case usage

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .usage: "Usage"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .usage: "chart.bar.xaxis"
        }
    }
}

struct NotchDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vm: MMViewModel
    @State private var selectedPage = NotchDashboardPage.home

    let albumArtNamespace: Namespace.ID
    let topBarHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            navigation

            ZStack {
                page
                    .id(selectedPage)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(
                                with: .move(edge: .trailing)
                            )
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .onChange(of: selectedPage) { _, page in
            if page != .usage {
                setOpenHeight(openNotchSize.height)
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 6) {
            ForEach(NotchDashboardPage.allCases) { page in
                Button {
                    withAnimation(
                        reduceMotion
                            ? nil
                            : .easeOut(duration: 0.18)
                    ) {
                        selectedPage = page
                    }
                } label: {
                    Image(systemName: page.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    selectedPage == page
                                        ? Color.white.opacity(0.12)
                                        : Color.clear
                                )
                        )
                }
                .buttonStyle(NotchPressButtonStyle())
                .foregroundStyle(
                    selectedPage == page ? .white : .secondary
                )
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(
                    selectedPage == page ? .isSelected : []
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(height: topBarHeight, alignment: .center)
    }

    @ViewBuilder
    private var page: some View {
        switch selectedPage {
        case .home:
            NotchHomePage(albumArtNamespace: albumArtNamespace)
        case .usage:
            OpenUsageView(onPreferredHeightChange: setOpenHeight)
        }
    }

    private func setOpenHeight(_ height: CGFloat) {
        guard vm.notchState == .open else { return }
        let screenHeight = getScreenFrame(vm.screenUUID)?.height
        let maximumHeight = max(
            (screenHeight ?? 900) - 40,
            openNotchSize.height
        )
        let targetHeight = min(
            max(openNotchSize.height, height),
            maximumHeight
        )
        guard vm.notchSize.height != targetHeight else { return }

        vm.notchSize = CGSize(
            width: openNotchSize.width,
            height: targetHeight
        )
    }
}

struct NotchHomePage: View {
    let albumArtNamespace: Namespace.ID

    var body: some View {
        MusicPlayerView(albumArtNamespace: albumArtNamespace)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

struct NotchPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.96
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.1),
                value: configuration.isPressed
            )
    }
}
