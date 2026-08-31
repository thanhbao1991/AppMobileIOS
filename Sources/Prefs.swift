import Foundation

// Bắn khi APIClient phát hiện refresh token bị thu hồi/hết hạn thật (không tự cứu được nữa) —
// ContentView lắng nghe để đưa app quay lại LoginView thay vì để request lỗi âm thầm.
extension Notification.Name {
    static let sessionExpired = Notification.Name("sessionExpired")
}

enum Prefs {
    static let apiBase = "https://api.denncoffee.uk"
    // ĐÃ THỬ 1 domain gốc "denncoffee.uk" riêng (không "api.") cho link SMS 2026-08-22 nhưng
    // ROLLBACK NGAY TRONG NGÀY — dùng chung cert (SAN) + chung IP với api.denncoffee.uk khiến app
    // treo, không tải được dữ liệu ở MỌI tab (nghi HTTP/2 connection coalescing giữa 2 host cùng
    // cert). Xem memory project_sms_qr_link_bare_domain trước khi thử lại hướng này.
    private static let defaults = UserDefaults.standard
    private static let keyToken = "token"
    private static let keyRefreshToken = "refresh_token"
    private static let keyDisplayName = "display_name"
    private static let keyLastTaiKhoan = "last_tai_khoan"
    private static let keyManualLogout = "manual_logout"

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

    /// Tài khoản đăng nhập gần nhất, để tự điền lại khi hiện form thủ công (sau đăng xuất).
    static var lastTaiKhoan: String {
        get { defaults.string(forKey: keyLastTaiKhoan) ?? "admin" }
        set { defaults.set(newValue, forKey: keyLastTaiKhoan) }
    }

    /// True khi user vừa bấm "Đăng xuất" chủ động — LoginView phải đứng yên chờ bấm tay, không
    /// tự auto-login lại ngay. Reset về false ngay khi login (tự động hoặc thủ công) thành công.
    static var manualLogout: Bool {
        get { defaults.bool(forKey: keyManualLogout) }
        set { defaults.set(newValue, forKey: keyManualLogout) }
    }

    static func saveSession(token: String, refreshToken: String?, displayName: String?) {
        Prefs.token = token
        if let rt = refreshToken, !rt.isEmpty { Prefs.refreshToken = rt }
        if let dn = displayName, !dn.isEmpty { Prefs.displayName = dn }
        manualLogout = false
    }

    static func clear() {
        token = nil
        refreshToken = nil
        displayName = nil
    }
}
