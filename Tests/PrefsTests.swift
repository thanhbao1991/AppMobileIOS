import XCTest
@testable import AppMobileIOS

/// Prefs ghi thẳng vào UserDefaults.standard (không có suite riêng cho test) — mỗi test tự dọn sạch
/// trước/sau để không phụ thuộc thứ tự chạy hay rò dữ liệu giữa các lần chạy trên cùng simulator.
final class PrefsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Prefs.clear()
        Prefs.manualLogout = false
    }

    override func tearDown() {
        Prefs.clear()
        Prefs.manualLogout = false
        Prefs.lastTaiKhoan = "admin"
        super.tearDown()
    }

    func test_isLoggedIn_falseKhiChuaCoToken() {
        XCTAssertFalse(Prefs.isLoggedIn)
    }

    func test_saveSession_luuTokenVaBoManualLogout() {
        Prefs.manualLogout = true

        Prefs.saveSession(token: "t1", refreshToken: "r1", displayName: "Admin")

        XCTAssertTrue(Prefs.isLoggedIn)
        XCTAssertEqual(Prefs.token, "t1")
        XCTAssertEqual(Prefs.refreshToken, "r1")
        XCTAssertEqual(Prefs.displayName, "Admin")
        XCTAssertFalse(Prefs.manualLogout)
    }

    // Khi refresh token thành công nhưng backend không trả refreshToken mới (giữ nguyên cái cũ),
    // saveSession KHÔNG được ghi đè bằng chuỗi rỗng — mất refreshToken thì lần 401 sau không còn gì
    // để tự cứu phiên, bắt đăng xuất oan dù phiên còn sống (đúng lớp bug refresh-token race đã vá).
    func test_saveSession_refreshTokenRongThiGiuNguyenCaiCu() {
        Prefs.saveSession(token: "t1", refreshToken: "r-cu", displayName: "A")

        Prefs.saveSession(token: "t2", refreshToken: "", displayName: nil)

        XCTAssertEqual(Prefs.token, "t2")
        XCTAssertEqual(Prefs.refreshToken, "r-cu")
        XCTAssertEqual(Prefs.displayName, "A")
    }

    func test_clear_xoaSachToken() {
        Prefs.saveSession(token: "t1", refreshToken: "r1", displayName: "A")

        Prefs.clear()

        XCTAssertNil(Prefs.token)
        XCTAssertNil(Prefs.refreshToken)
        XCTAssertNil(Prefs.displayName)
        XCTAssertFalse(Prefs.isLoggedIn)
    }

    func test_lastTaiKhoan_macDinhLaAdmin_roiGhiDeDuoc() {
        XCTAssertEqual(Prefs.lastTaiKhoan, "admin")

        Prefs.lastTaiKhoan = "nhanvien1"

        XCTAssertEqual(Prefs.lastTaiKhoan, "nhanvien1")
    }
}
