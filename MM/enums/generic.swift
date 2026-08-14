import Defaults
import Foundation

enum NotchState {
    case closed
    case open
}

/// Raw values intentionally keep the historical strings so existing
/// UserDefaults entries from earlier builds continue to decode.
enum WindowHeightMode: String, Defaults.Serializable {
    case matchMenuBar = "Match menubar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"

    /// Friendly labels shown in Settings (independent of the storage key).
    var displayName: String {
        switch self {
        case .matchMenuBar: "匹配菜单栏高度"
        case .matchRealNotchSize: "匹配刘海高度"
        case .custom: "自定义高度"
        }
    }

    /// Accept both historical and current raw values after renames.
    static func migratePersistedValuesIfNeeded() {
        let defaults = UserDefaults.standard
        let renames: [(key: String, map: [String: String])] = [
            (
                "notchHeightMode",
                [
                    "Match menu bar height": WindowHeightMode.matchMenuBar.rawValue,
                    "Match hardware notch height":
                        WindowHeightMode.matchRealNotchSize.rawValue,
                ]
            ),
            (
                "nonNotchHeightMode",
                [
                    "Match menu bar height": WindowHeightMode.matchMenuBar.rawValue,
                    "Match hardware notch height":
                        WindowHeightMode.matchRealNotchSize.rawValue,
                ]
            ),
        ]
        for entry in renames {
            guard let current = defaults.string(forKey: entry.key),
                  let replacement = entry.map[current]
            else {
                continue
            }
            defaults.set(replacement, forKey: entry.key)
        }
    }
}

enum SliderColorEnum:
    String,
    CaseIterable,
    Defaults.Serializable
{
    case white = "White"
    case albumArt = "Match album art"
    case accent = "Accent color"
}
