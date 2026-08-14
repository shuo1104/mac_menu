import Foundation

struct KimiAuth: Hashable, Sendable {
    var apiKey: String
}

enum KimiAuthError: Error, LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case saveFailed
    case deleteFailed

    init(_ failure: UserAPIKeyStore.Failure) {
        switch failure {
        case .missingKey: self = .missingKey
        case .saveFailed: self = .saveFailed
        case .deleteFailed: self = .deleteFailed
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Kimi API key. Set KIMI_API_KEY or add it to ~/.config/openusage/kimi.json."
        case .invalidKey:
            return "Kimi API key invalid. Check your Kimi For Coding key at kimi.com/code."
        case .saveFailed:
            return "Couldn't save the Kimi API key."
        case .deleteFailed:
            return "Couldn't remove the saved Kimi API key."
        }
    }
}

/// Reads a [Kimi For Coding](https://www.kimi.com/code/) subscription key the user has already placed
/// on the machine. Kimi has no companion CLI that stashes a credential in a known spot, so the key
/// comes from an environment variable or a small config file (see `UserAPIKeyStore` for the
/// config-over-env precedence and the login-shell environment capture).
///
/// Note the two Kimi lines: the open platform (`api.moonshot.cn`, pay-as-you-go) has no subscription
/// usage endpoint; this store is for the Kimi For Coding line (`api.kimi.com/coding/v1`), whose key
/// is the only one the `/usages` endpoint accepts.
struct KimiAuthStore: Sendable {
    /// Config files checked in order; first readable key wins. JSON (`apiKey` / `api_key` / `key`) or a
    /// plain-text file containing only the key.
    static let configPaths = [
        "~/.config/openusage/kimi.json"
    ]
    /// Environment variables checked in order. `KIMI_API_KEY` is the natural name; `KIMI_CODING_API_KEY`
    /// disambiguates for users who also carry an open-platform key in `KIMI_API_KEY`-adjacent names.
    static let environmentNames = ["KIMI_API_KEY", "KIMI_CODING_API_KEY"]

    private let store: UserAPIKeyStore

    init(
        files: TextFileAccessing = LocalTextFileAccessor(),
        environment: EnvironmentReading = ProcessEnvironmentReader()
    ) {
        store = UserAPIKeyStore(
            configPaths: Self.configPaths,
            environmentNames: Self.environmentNames,
            files: files,
            environment: environment,
            makeError: { KimiAuthError($0) }
        )
    }

    func loadAPIKey() -> KimiAuth? { store.loadKey().map(KimiAuth.init(apiKey:)) }
    func currentAPIKey() -> String? { store.loadKey() }
    func keyStatus() -> APIKeyStatus { store.keyStatus() }
    func saveAPIKey(_ key: String) throws { try store.saveKey(key) }
    func deleteAPIKey() throws { try store.deleteKey() }
}
