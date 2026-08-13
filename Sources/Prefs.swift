import Foundation

enum Prefs {
    static let apiBase = "https://api.denncoffee.uk"
    private static let defaults = UserDefaults.standard
    private static let keyToken = "token"
    private static let keyRefreshToken = "refresh_token"
    private static let keyDisplayName = "display_name"

    static var token: String? {
        get { defaults.string(forKey: keyToken) }
        set { defaults.set(newValue, forKey: keyToken) }
    }
    static var refreshToken: String? {
        get { defaults.string(forKey: keyRefreshToken) }
        set { defaults.set(newValue, forKey: keyRefreshToken) }
    }
    static var displayName: String? {
        get { defaults.string(forKey: keyDisplayName) }
        set { defaults.set(newValue, forKey: keyDisplayName) }
    }
    static var isLoggedIn: Bool { !(token?.isEmpty ?? true) }

    static func saveSession(token: String, refreshToken: String?, displayName: String?) {
        Prefs.token = token
        if let rt = refreshToken, !rt.isEmpty { Prefs.refreshToken = rt }
        if let dn = displayName, !dn.isEmpty { Prefs.displayName = dn }
    }

    static func clear() {
        token = nil
        refreshToken = nil
        displayName = nil
    }
}
