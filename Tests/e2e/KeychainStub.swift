enum KeychainStore {  // en memoria: no toca el Llavero real
    static var store: [String: String] = [:]
    static func read(account: String) -> String? { store[account] }
    static func write(_ v: String, account: String) { store[account] = v }
}
