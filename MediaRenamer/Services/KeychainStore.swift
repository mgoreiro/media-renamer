import Foundation
import Security

/// Almacén mínimo en el Llavero (contraseñas genéricas) para secretos como la API key.
enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.rosso27.MediaRenamer"

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Guarda el valor; una cadena vacía borra la entrada.
    static func write(_ value: String, account: String) {
        guard !value.isEmpty else {
            SecItemDelete(baseQuery(account: account) as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(account: account)
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }
}
