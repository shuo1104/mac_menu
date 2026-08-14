import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "Player"

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "Player") {
                    Label("播放器", systemImage: "music.note")
                }
                NavigationLink(value: "Usage") {
                    Label("用量", systemImage: "chart.bar.fill")
                }
                NavigationLink(value: "Appearance") {
                    Label("外观", systemImage: "paintbrush")
                }
                NavigationLink(value: "Behavior") {
                    Label("行为", systemImage: "rectangle.topthird.inset.filled")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("快捷键", systemImage: "keyboard")
                }
                NavigationLink(value: "About") {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch selectedTab {
                case "Usage":
                    OpenUsageSettings()
                case "Appearance":
                    PlayerAppearanceSettings()
                case "Behavior":
                    PlayerBehaviorSettings()
                case "Shortcuts":
                    PlayerShortcutSettings()
                case "About":
                    About()
                default:
                    PlayerSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .formStyle(.grouped)
        .frame(width: 700)
        .tint(.effectiveAccent)
    }
}

struct OpenUsageSettings: View {
    @ObservedObject private var usage = OpenUsageClient.shared

    var body: some View {
        Form {
            Section {
                ForEach(usage.providerSettings) { provider in
                    Toggle(
                        provider.name,
                        isOn: Binding(
                            get: { provider.isEnabled },
                            set: {
                                usage.setProviderEnabled(
                                    $0,
                                    id: provider.id
                                )
                            }
                        )
                    )
                }
            } header: {
                Text("提供商")
            } footer: {
                Text(
                    "MM 未启用 App Sandbox，以便读取你主目录下的本地 AI CLI 凭据和用量日志。凭据保留在其原始文件或 macOS 钥匙串中；下方输入的 API 密钥会以明文文件保存在 ~/.config/openusage/ 下。"
                )
            }

            if !usage.apiKeyProviders.isEmpty {
                Section("API 密钥") {
                    ForEach(usage.apiKeyProviders) { provider in
                        APIKeySettingsRow(provider: provider)
                    }
                }
            }

            Section("刷新") {
                Toggle(
                    "后台自动刷新用量",
                    isOn: $usage.backgroundRefreshEnabled
                )

                Picker(
                    "刷新间隔",
                    selection: $usage.refreshIntervalSeconds
                ) {
                    Text("30 秒").tag(30)
                    Text("5 分钟").tag(300)
                    Text("15 分钟").tag(900)
                    Text("30 分钟").tag(1800)
                    Text("1 小时").tag(3600)
                }
                .disabled(!usage.backgroundRefreshEnabled)

                Button {
                    Task { await usage.refresh() }
                } label: {
                    if usage.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("立即刷新")
                    }
                }
                .disabled(usage.isLoading)
            }

            Section("状态") {
                LabeledContent("数据来源") {
                    Text("内嵌采集器")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("上次更新") {
                    if let date = usage.lastUpdated {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未更新")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = usage.errorMessage {
                    Text(error)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("用量")
    }
}

/// One provider's key editor: a secure field + Save replaces the stored key, Clear removes it
/// (falling back to the environment variable when one is set). Status text reports where the
/// current key comes from so the user knows what Save will override.
private struct APIKeySettingsRow: View {
    let provider: OpenUsageAPIKeyProvider

    @ObservedObject private var usage = OpenUsageClient.shared
    @State private var input = ""
    @State private var actionError: String?

    private var statusText: String {
        switch provider.status {
        case .notSet: "未设置"
        case .fromEnvironment: "来自环境变量"
        case .saved: "已保存"
        case .overrideActive: "自定义密钥覆盖环境变量"
        }
    }

    private var canClear: Bool {
        provider.status == .saved || provider.status == .overrideActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.name)
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                SecureField(
                    "输入 API 密钥",
                    text: $input
                )
                .textFieldStyle(.roundedBorder)
                Button("保存") { save() }
                    .disabled(
                        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                if canClear {
                    Button("清除") { clear() }
                }
            }
            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private func save() {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try usage.saveAPIKey(key, providerID: provider.id)
            input = ""
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func clear() {
        do {
            try usage.deleteAPIKey(providerID: provider.id)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct PlayerSettings: View {
    @Default(.mediaController) private var mediaController
    @Default(.waitInterval) private var waitInterval
    @Default(.hideNotchOption) private var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) private var sneakPeekStyles
    @ObservedObject private var coordinator = MMViewCoordinator.shared

    private var availableMediaControllers: [MediaControllerType] {
        MediaControllerType.available
    }

    var body: some View {
        Form {
            Section("音乐来源") {
                Picker("来源", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(mediaControllerName(controller)).tag(controller)
                    }
                }
                .onAppear {
                    let resolved = MediaControllerType.resolved(mediaController)
                    if resolved != mediaController {
                        mediaController = resolved
                    }
                }
                .onChange(of: mediaController) {
                    let resolved = MediaControllerType.resolved(mediaController)
                    if resolved != mediaController {
                        mediaController = resolved
                        return
                    }
                    NotificationCenter.default.post(
                        name: .mediaControllerChanged,
                        object: nil
                    )
                }
            }

            Section("实时活动") {
                Toggle(
                    "刘海关闭时显示音乐",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle(
                    "显示切歌提示",
                    isOn: $enableSneakPeek
                )
                Picker("切歌提示样式", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(sneakPeekStyleName(style)).tag(style)
                    }
                }
                .disabled(!enableSneakPeek)

                Stepper(value: $waitInterval, in: 0...10, step: 1) {
                    LabeledContent("无操作超时") {
                        Text("\(waitInterval, specifier: "%.0f") 秒")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("全屏行为", selection: $hideNotchOption) {
                    Text("任何应用全屏时隐藏")
                        .tag(HideNotchOption.always)
                    Text("媒体全屏播放时隐藏")
                        .tag(HideNotchOption.nowPlayingOnly)
                    Text("从不隐藏")
                        .tag(HideNotchOption.never)
                }
            }

            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    Text("在艺术家下方显示歌词")
                }
            } header: {
                Text("控制按钮")
            } footer: {
                Text("选择展开播放器中显示的控制按钮。")
            }
        }
        .navigationTitle("播放器")
    }

    private func mediaControllerName(_ controller: MediaControllerType) -> String {
        switch controller {
        case .nowPlaying: "正在播放"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .youtubeMusic: "YouTube Music"
        }
    }

    private func sneakPeekStyleName(_ style: SneakPeekStyle) -> String {
        switch style {
        case .standard: "默认"
        case .inline: "内联"
        }
    }
}

struct PlayerAppearanceSettings: View {
    @Default(.sliderColor) private var sliderColor
    @Default(.useMusicVisualizer) private var useMusicVisualizer
    @Default(.useCustomAccentColor) private var useCustomAccentColor
    @State private var customAccentColor: Color = .accentColor

    var body: some View {
        Form {
            Section("封面与颜色") {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("用封面颜色为可视化着色")
                }
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("用封面颜色为播放器文字着色")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("显示封面光晕")
                }
                Picker("进度条颜色", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) {
                        Text(sliderColorName($0))
                    }
                }
                Toggle("使用音乐可视化频谱", isOn: $useMusicVisualizer)
            }

            Section("强调色") {
                Picker("强调色", selection: $useCustomAccentColor) {
                    Text("跟随系统").tag(false)
                    Text("自定义").tag(true)
                }
                .pickerStyle(.segmented)

                if useCustomAccentColor {
                    ColorPicker(
                        "自定义强调色",
                        selection: $customAccentColor,
                        supportsOpacity: false
                    )
                    .onChange(of: customAccentColor) { _, newColor in
                        saveCustomAccent(newColor)
                    }
                }
            }
            .onAppear(perform: loadCustomAccent)

            Section("刘海") {
                Defaults.Toggle(key: .enableShadow) {
                    Text("显示窗口阴影")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("展开时放大圆角")
                }
            }
        }
        .navigationTitle("外观")
    }

    private func sliderColorName(_ color: SliderColorEnum) -> String {
        switch color {
        case .white: "白色"
        case .albumArt: "匹配专辑封面"
        case .accent: "强调色"
        }
    }

    private func loadCustomAccent() {
        if let data = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSColor.self,
            from: data
           ) {
            customAccentColor = Color(nsColor: nsColor)
        }
    }

    private func saveCustomAccent(_ color: Color) {
        let nsColor = NSColor(color)
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: nsColor,
            requiringSecureCoding: false
        ) {
            Defaults[.customAccentColorData] = data
        }
    }
}

struct PlayerBehaviorSettings: View {
    @State private var screens = NSScreen.screens.compactMap { screen in
        screen.displayUUID.map { (uuid: $0, name: screen.localizedName) }
    }

    @ObservedObject private var coordinator = MMViewCoordinator.shared
    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) private var automaticallySwitchDisplay
    @Default(.openNotchOnHover) private var openOnHover
    @Default(.enableGestures) private var enableGestures
    @Default(.minimumHoverDuration) private var hoverDelay
    @Default(.gestureSensitivity) private var gestureSensitivity
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.notchHeight) private var notchHeight
    @Default(.nonNotchHeight) private var nonNotchHeight

    var body: some View {
        Form {
            Section("系统") {
                Defaults.Toggle(key: .menubarIcon) {
                    Text("显示菜单栏图标")
                }
                LaunchAtLogin.Toggle("登录时启动")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("在所有显示器上显示")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: .showOnAllDisplaysChanged,
                        object: nil
                    )
                }

                Picker(
                    "首选显示器",
                    selection: $coordinator.preferredScreenUUID
                ) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .disabled(showOnAllDisplays)

                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("跟随活跃显示器")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(
                        name: .automaticallySwitchDisplayChanged,
                        object: nil
                    )
                }
                .disabled(showOnAllDisplays)

                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("在锁屏上显示")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("录屏时隐藏")
                }
            }

            notchSizeSection

            Section("交互") {
                Defaults.Toggle(key: .openNotchOnHover) {
                    Text("悬停时展开")
                }

                if openOnHover {
                    LabeledContent("悬停延迟") {
                        Text("\(hoverDelay, specifier: "%.1f") 秒")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $hoverDelay, in: 0...1, step: 0.1)
                }

                Defaults.Toggle(key: .enableGestures) {
                    Text("启用开合手势")
                }
                if enableGestures {
                    Defaults.Toggle(key: .closeGestureEnabled) {
                        Text("启用关闭手势")
                    }
                    Slider(
                        value: $gestureSensitivity,
                        in: 100...300,
                        step: 100
                    ) {
                        Text("手势灵敏度")
                    }
                }

                Defaults.Toggle(key: .enableHaptics) {
                    Text("启用触感反馈")
                }
            }
        }
        .navigationTitle("行为")
    }

    @ViewBuilder
    private var notchSizeSection: some View {
        Section("尺寸") {
            Picker("带刘海的显示器", selection: $notchHeightMode) {
                Text(WindowHeightMode.matchRealNotchSize.displayName)
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text(WindowHeightMode.matchMenuBar.displayName)
                    .tag(WindowHeightMode.matchMenuBar)
                Text(WindowHeightMode.custom.displayName)
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: notchHeightMode) {
                NotificationCenter.default.post(
                    name: .notchHeightChanged,
                    object: nil
                )
            }
            if notchHeightMode == .custom {
                Slider(value: $notchHeight, in: 15...45, step: 1)
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: .notchHeightChanged,
                            object: nil
                        )
                    }
            }

            Picker("其他显示器", selection: $nonNotchHeightMode) {
                Text(WindowHeightMode.matchMenuBar.displayName)
                    .tag(WindowHeightMode.matchMenuBar)
                Text(WindowHeightMode.matchRealNotchSize.displayName)
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text(WindowHeightMode.custom.displayName)
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                NotificationCenter.default.post(
                    name: .notchHeightChanged,
                    object: nil
                )
            }
            if nonNotchHeightMode == .custom {
                Slider(value: $nonNotchHeight, in: 0...40, step: 1)
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: .notchHeightChanged,
                            object: nil
                        )
                    }
            }
        }
    }
}

struct PlayerShortcutSettings: View {
    var body: some View {
        Form {
            Section("播放器") {
                KeyboardShortcuts.Recorder(
                    "显示歌曲信息",
                    name: .toggleSneakPeek
                )
                KeyboardShortcuts.Recorder(
                    "展开/收起播放器",
                    name: .toggleNotchOpen
                )
            }
        }
        .navigationTitle("快捷键")
    }
}

struct About: View {
    @State private var showBuildNumber = false

    var body: some View {
        Form {
            Section("版本") {
                LabeledContent("发布版本") {
                    Text(Defaults[.releaseName])
                        .foregroundStyle(.secondary)
                }
                LabeledContent("版本号") {
                    HStack(spacing: 4) {
                        Text(Bundle.main.releaseVersionNumber ?? "未知")
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .onTapGesture {
                    showBuildNumber.toggle()
                }
            }

            Section {
                Button("在 GitHub 上打开项目") {
                    guard let url = URL(
                        string: "https://github.com/shuo1104/mac_menu"
                    ) else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .navigationTitle("关于")
    }
}
