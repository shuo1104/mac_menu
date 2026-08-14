import Defaults
import SwiftUI

let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
let appVersion =
    "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") "
    + "(\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

struct CustomVisualizer: Codable, Hashable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

extension Notification.Name {
    static let mediaControllerChanged = Notification.Name(
        "mediaControllerChanged"
    )
    /// Posted when the keyboard-opened notch should cancel its auto-close timer.
    static let cancelNotchAutoClose = Notification.Name(
        "cancelNotchAutoClose"
    )
}

enum MediaControllerType:
    String,
    CaseIterable,
    Identifiable,
    Defaults.Serializable
{
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"

    var id: String { rawValue }

    /// Controllers the current OS can actually drive.
    static var available: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return allCases.filter { $0 != .nowPlaying }
        }
        return allCases
    }

    /// Preference used when nothing valid is stored yet.
    static var preferredDefault: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        }
        return .nowPlaying
    }

    /// Coerce a stored preference onto a controller the OS can use.
    static func resolved(_ preferred: MediaControllerType) -> MediaControllerType {
        if available.contains(preferred) {
            return preferred
        }
        return preferredDefault
    }
}

enum SneakPeekStyle:
    String,
    CaseIterable,
    Identifiable,
    Defaults.Serializable
{
    case standard = "Default"
    case inline = "Inline"

    var id: String { rawValue }
}

extension Defaults.Keys {
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>(
        "showOnAllDisplays",
        default: false
    )
    static let automaticallySwitchDisplay = Key<Bool>(
        "automaticallySwitchDisplay",
        default: true
    )
    static let releaseName = Key<String>(
        "releaseName",
        default: "Flying Rabbit 🐇🪽"
    )

    static let minimumHoverDuration = Key<TimeInterval>(
        "minimumHoverDuration",
        default: 0.3
    )
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>(
        "openNotchOnHover",
        default: true
    )
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: .matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: .matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>(
        "nonNotchHeight",
        default: 32
    )
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let showOnLockScreen = Key<Bool>(
        "showOnLockScreen",
        default: false
    )
    static let hideFromScreenRecording = Key<Bool>(
        "hideFromScreenRecording",
        default: false
    )

    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>(
        "cornerRadiusScaling",
        default: true
    )
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: .white
    )
    static let playerColorTinting = Key<Bool>(
        "playerColorTinting",
        default: true
    )
    static let useMusicVisualizer = Key<Bool>(
        "useMusicVisualizer",
        default: true
    )
    static let selectedVisualizer = Key<CustomVisualizer?>(
        "selectedVisualizer",
        default: nil
    )

    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>(
        "closeGestureEnabled",
        default: true
    )
    static let gestureSensitivity = Key<CGFloat>(
        "gestureSensitivity",
        default: 200
    )

    static let coloredSpectrogram = Key<Bool>(
        "coloredSpectrogram",
        default: true
    )
    static let enableSneakPeek = Key<Bool>(
        "enableSneakPeek",
        default: false
    )
    static let sneakPeekStyles = Key<SneakPeekStyle>(
        "sneakPeekStyles",
        default: .standard
    )
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    static let hideNotchOption = Key<HideNotchOption>(
        "hideNotchOption",
        default: .nowPlayingOnly
    )
    /// Default stays `.nowPlaying` for storage shape; runtime resolves via
    /// `MediaControllerType.resolved` once deprecation status is known.
    static let mediaController = Key<MediaControllerType>(
        "mediaController",
        default: .nowPlaying
    )

    static let useCustomAccentColor = Key<Bool>(
        "useCustomAccentColor",
        default: false
    )
    static let customAccentColorData = Key<Data?>(
        "customAccentColorData",
        default: nil
    )
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let didClearLegacyURLCacheV1 = Key<Bool>(
        "didClearLegacyURLCache_v1",
        default: false
    )
}
