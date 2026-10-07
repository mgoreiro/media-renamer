import Foundation

/// Ajustes de la app. La API key vive en el Llavero; el idioma, en UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let languages: [(code: String, name: String)] = [
        ("es-ES", "Español (España)"), ("es-MX", "Español (México)"), ("en-US", "English"),
        ("ca-ES", "Català"), ("fr-FR", "Français"), ("de-DE", "Deutsch"),
        ("it-IT", "Italiano"), ("pt-PT", "Português")
    ]

    private static let keychainAccount = "tmdb-api-key"
    private static let legacyDefaultsKey = "tmdbAPIKey"
    private static let languageKey = "tmdbLanguage"

    @Published var apiKey: String {
        didSet { KeychainStore.write(apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                     account: Self.keychainAccount) }
    }

    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Self.languageKey) }
    }

    private init() {
        // Migra la clave de versiones anteriores (UserDefaults en claro) al Llavero.
        if let legacy = UserDefaults.standard.string(forKey: Self.legacyDefaultsKey) {
            if !legacy.isEmpty, KeychainStore.read(account: Self.keychainAccount) == nil {
                KeychainStore.write(legacy, account: Self.keychainAccount)
            }
            UserDefaults.standard.removeObject(forKey: Self.legacyDefaultsKey)
        }
        apiKey = KeychainStore.read(account: Self.keychainAccount) ?? ""
        language = UserDefaults.standard.string(forKey: Self.languageKey) ?? "es-ES"
    }
}
