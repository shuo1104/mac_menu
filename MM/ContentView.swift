import Defaults
import SwiftUI

@MainActor
struct ContentView: View {
    @EnvironmentObject private var vm: MMViewModel
    @ObservedObject private var coordinator = MMViewCoordinator.shared
    @ObservedObject private var musicManager = MusicManager.shared

    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering = false
    @State private var gestureProgress: CGFloat = .zero
    @State private var haptics = false
    @State private var outsideClickMonitor = NotchOutsideClickMonitor()
    @Namespace private var albumArtNamespace

    @Default(.useMusicVisualizer) private var useMusicVisualizer

    private let animationSpring = Animation.interactiveSpring(
        response: 0.38,
        dampingFraction: 0.8,
        blendDuration: 0
    )

    private var topCornerRadius: CGFloat {
        vm.notchState == .open && Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: vm.notchState == .open && Defaults[.cornerRadiusScaling]
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        guard vm.notchState == .closed,
              coordinator.musicLiveActivityEnabled,
              !vm.hideOnClosed,
              musicManager.isPlaying || !musicManager.isPlayerIdle
        else {
            return vm.closedNotchSize.width
        }

        return vm.closedNotchSize.width
            + (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
    }

    var body: some View {
        let gestureScale = max(0.6, 1 + gestureProgress * 0.01)

        VStack(spacing: 0) {
            notchLayout
                .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                .padding(
                    .horizontal,
                    vm.notchState == .open
                        ? (Defaults[.cornerRadiusScaling]
                            ? cornerRadiusInsets.opened.top
                            : cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                )
                .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                .background(.black)
                .clipShape(currentNotchShape)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.black)
                        .frame(height: 1)
                        .padding(.horizontal, topCornerRadius)
                }
                .shadow(
                    color: (vm.notchState == .open || isHovering) && Defaults[.enableShadow]
                        ? .black.opacity(0.7)
                        : .clear,
                    radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                )
                .padding(.bottom, vm.effectiveClosedNotchHeight == 0 ? 10 : 0)
                .animation(
                    vm.notchState == .open
                        ? .spring(response: 0.42, dampingFraction: 0.8)
                        : .spring(response: 0.45, dampingFraction: 1),
                    value: vm.notchState
                )
                .animation(.smooth, value: gestureProgress)
                .contentShape(Rectangle())
                .onHover(perform: handleHover)
                .onTapGesture(perform: openNotch)
                .conditionalModifier(Defaults[.enableGestures]) { view in
                    view.panGesture(direction: .down) { translation, phase in
                        handleDownGesture(translation: translation, phase: phase)
                    }
                }
                .conditionalModifier(
                    Defaults[.closeGestureEnabled] && Defaults[.enableGestures]
                ) { view in
                    view.panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
                }
                .sensoryFeedback(.alignment, trigger: haptics)
                .contextMenu {
                    Button("Settings") {
                        SettingsWindowController.shared.showWindow()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }

            if vm.chinHeight > 0 {
                Rectangle()
                    .fill(Color.black.opacity(0.01))
                    .frame(width: computedChinWidth, height: vm.chinHeight)
            }
        }
        .padding(.bottom, 8)
        .frame(
            width: windowSize.width,
            height: max(
                windowSize.height,
                vm.notchSize.height + shadowPadding
            ),
            alignment: .top
        )
        .compositingGroup()
        .scaleEffect(x: gestureScale, y: gestureScale, anchor: .top)
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onAppear {
            outsideClickMonitor.start {
                guard vm.notchState == .open else { return }
                withAnimation(animationSpring) {
                    vm.close()
                }
            }
        }
        .onDisappear {
            outsideClickMonitor.stop()
        }
    }

    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.notchState == .closed {
                closedPlayer
            } else {
                NotchDashboardView(
                    albumArtNamespace: albumArtNamespace,
                    topBarHeight: max(24, vm.effectiveClosedNotchHeight)
                )
                    .transition(
                        .scale(scale: 0.8, anchor: .top)
                            .combined(with: .opacity)
                    )
                    .allowsHitTesting(true)
                    .opacity(gestureProgress == 0 ? 1 : 1 - min(abs(gestureProgress) * 0.1, 0.3))
            }
        }
    }

    @ViewBuilder
    private var closedPlayer: some View {
        if (musicManager.isPlaying || !musicManager.isPlayerIdle),
           coordinator.musicLiveActivityEnabled,
           !vm.hideOnClosed {
            musicLiveActivity
        } else {
            Color.clear
                .frame(
                    width: max(0, vm.closedNotchSize.width - 20),
                    height: vm.effectiveClosedNotchHeight
                )
        }

        if coordinator.sneakPeek.show,
           !vm.hideOnClosed,
           Defaults[.sneakPeekStyles] == .standard {
            HStack {
                Image(systemName: "music.note")
                GeometryReader { geometry in
                    MarqueeText(
                        .constant("\(musicManager.songTitle) - \(musicManager.artistName)"),
                        textColor: Defaults[.playerColorTinting]
                            ? Color(nsColor: musicManager.avgColor)
                                .ensureMinimumBrightness(factor: 0.6)
                            : .gray,
                        minDuration: 1,
                        frameWidth: geometry.size.width
                    )
                }
            }
            .foregroundStyle(.gray)
            .padding(.bottom, 10)
            .fixedSize()
        }
    }

    private var musicLiveActivity: some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay {
                    if coordinator.expandingView.show,
                       Defaults[.sneakPeekStyles] == .inline {
                        HStack {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: liveActivityColor,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .foregroundStyle(liveActivityColor)
                        }
                    }
                }
                .frame(
                    width: coordinator.expandingView.show
                        && Defaults[.sneakPeekStyles] == .inline
                        ? 380
                        : vm.closedNotchSize.width - cornerRadiusInsets.closed.top
                )

            Group {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(liveActivityColor.gradient)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                }
            }
            .frame(
                width: max(0, vm.effectiveClosedNotchHeight - 12 + gestureProgress / 2),
                height: max(0, vm.effectiveClosedNotchHeight - 12)
            )
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    private var liveActivityColor: Color {
        Defaults[.coloredSpectrogram]
            ? Color(nsColor: musicManager.avgColor)
            : .gray
    }

    private func openNotch() {
        guard vm.notchState == .closed else { return }
        NotificationCenter.default.post(name: .cancelNotchAutoClose, object: nil)
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard !coordinator.firstLaunch else { return }
        hoverTask?.cancel()

        if hovering {
            NotificationCenter.default.post(name: .cancelNotchAutoClose, object: nil)
            withAnimation(animationSpring) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }

            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover]
            else {
                return
            }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard vm.notchState == .closed, isHovering, !coordinator.sneakPeek.show else {
                        return
                    }
                    openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(animationSpring) {
                        isHovering = false
                    }
                    if vm.notchState == .open {
                        vm.close()
                    }
                }
            }
        }
    }

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            return
        }

        gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            gestureProgress = .zero
            openNotch()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open else { return }

        gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        if phase == .ended {
            gestureProgress = .zero
        }

        if translation > Defaults[.gestureSensitivity] {
            isHovering = false
            gestureProgress = .zero
            vm.close()
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

#Preview {
    let vm = MMViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
