import Foundation

enum L10n {
    static func string(
        _ key: String,
        language: String? = nil,
        bundle: Bundle = .main
    ) -> String {
        let localizedBundle: Bundle
        if let language,
           let path = bundle.path(forResource: language, ofType: "lproj"),
           let languageBundle = Bundle(path: path)
        {
            localizedBundle = languageBundle
        } else {
            localizedBundle = bundle
        }
        return localizedBundle.localizedString(forKey: key, value: key, table: nil)
    }
}
