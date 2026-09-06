import XCTest
@testable import AppMobileIOS

/// Chặn URLSession.shared ở tầng URLProtocol — kỹ thuật chuẩn để mock network cho URLSession.shared
/// (không cần sửa APIClient để tiêm URLSession riêng). URLSession.shared vẫn tự tham chiếu các lớp
/// URLProtocol đã đăng ký qua URLProtocol.registerClass ngay cả sau khi đã khởi tạo.
final class MockURLProtocol: URLProtocol {
    struct Captured { let path: String; let authHeader: String? }

    private static let lock = NSLock()
    private static var _captured: [Captured] = []
    /// Trả (statusCode, body) cho 1 request — set lại mỗi test.
    static var handler: ((URLRequest) -> (Int, Data))?
    /// > 0: startLoading() busy-wait tới khi đã nhận đủ N request rồi mới trả lời TẤT CẢ — ép buộc
    /// race thật giữa nhiều request đang dùng CÙNG token cũ, thay vì trông chờ vào lịch trình ngẫu
    /// nhiên của actor scheduler (không ép thì dễ flaky: request đầu có thể refresh xong trước khi
    /// request 2/3 kịp build với token cũ, làm bài test không còn kiểm tra được race thật).
    static var awaitRequestCount = 0

    static var captured: [Captured] {
        lock.lock(); defer { lock.unlock() }
        return _captured
    }

    static func reset() {
        lock.lock()
        _captured = []
        lock.unlock()
        handler = nil
        awaitRequestCount = 0
    }

    // Chỉ chặn đúng request đi tới backend giả lập — canInit trả true vô điều kiện từng vô tình bắt
    // luôn cả traffic hệ thống không liên quan (app-launch telemetry của OS chạy nền lúc host app
    // khởi động cho test), làm lệch số đếm request nghiệp vụ trong bài test (7 thay vì 2 — không
    // phải bug thật của APIClient, mà do mock quá tham request).
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == URL(string: Prefs.apiBase)?.host
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let auth = request.value(forHTTPHeaderField: "Authorization")

        MockURLProtocol.lock.lock()
        MockURLProtocol._captured.append(.init(path: path, authHeader: auth))
        let target = MockURLProtocol.awaitRequestCount
        MockURLProtocol.lock.unlock()

        if target > 0 {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                MockURLProtocol.lock.lock()
                let count = MockURLProtocol._captured.count
                MockURLProtocol.lock.unlock()
                if count >= target { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        guard let handler = MockURLProtocol.handler,
              let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func jsonData(_ s: String) -> Data { Data(s.utf8) }

private enum Fixture {
    static let refreshSuccess = jsonData("""
    {"isSuccess":true,"message":null,"data":{"thanhCong":true,"message":null,"token":"token-moi","tenHienThi":"Admin","vaiTro":"Admin","refreshToken":"refresh-moi"},"warnings":null}
    """)
    static let refreshFailed = jsonData("""
    {"isSuccess":false,"message":"Refresh token het han that.","data":null,"warnings":null}
    """)
    static let sessionsEmpty = jsonData("""
    {"isSuccess":true,"message":null,"data":[],"warnings":null}
    """)
    static let loginSuccess = jsonData("""
    {"isSuccess":true,"message":null,"data":{"thanhCong":true,"message":null,"token":"t1","tenHienThi":"Admin","vaiTro":"Admin","refreshToken":"r1"},"warnings":null}
    """)
    static let loginRejected = jsonData("""
    {"isSuccess":false,"message":"Sai tai khoan hoac mat khau.","data":null,"warnings":null}
    """)
}

/// APIClient là actor singleton dùng chung URLSession.shared, tự refresh token khi 401 rồi retry
/// đúng request gốc — cùng cơ chế "gộp refresh" đã vá cho AppShipperAndroid/AppQuanLyIOS/
/// AppDatHangIOS (xem incident_multiclient_refresh_token_race_2026_09 trong memory): nhiều màn hình
/// bắn request song song, nếu KHÔNG gộp thì mỗi request tự refresh riêng, request thắng race lưu
/// token mới xong thì các request thua bị BE từ chối refresh token cũ (đã tiêu) → xoá sạch luôn
/// token mới vừa refresh thành công, bắt đăng xuất oan dù phiên còn sống.
final class APIClientRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        Prefs.clear()
    }

    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        Prefs.clear()
        super.tearDown()
    }

    func test_request200_khongCanRefresh() async {
        Prefs.token = "token-con-han"
        MockURLProtocol.handler = { _ in (200, Fixture.sessionsEmpty) }

        let sessions = await APIClient.shared.getSessions()

        XCTAssertTrue(sessions.isEmpty)
        XCTAssertFalse(MockURLProtocol.captured.contains { $0.path == "/api/auth/refresh" })
    }

    func test_401_refreshThanhCong_tuDongRetryVaTraKetQuaThat() async {
        Prefs.token = "token-het-han"
        Prefs.refreshToken = "refresh-con-han"
        MockURLProtocol.handler = { req in
            if req.url?.path == "/api/auth/refresh" { return (200, Fixture.refreshSuccess) }
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer token-het-han" { return (401, Data()) }
            return (200, Fixture.sessionsEmpty)
        }

        let sessions = await APIClient.shared.getSessions()

        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(Prefs.token, "token-moi")
        XCTAssertEqual(Prefs.refreshToken, "refresh-moi")
        // Đúng 1 request nghiệp vụ với token cũ (401) + 1 refresh + 1 request nghiệp vụ retry với
        // token mới — không lặp vô hạn, không bỏ sót retry.
        let businessCalls = MockURLProtocol.captured.filter { $0.path != "/api/auth/refresh" }
        XCTAssertEqual(businessCalls.count, 2)
        XCTAssertEqual(MockURLProtocol.captured.filter { $0.path == "/api/auth/refresh" }.count, 1)
    }

    // Refresh token cũng hết hạn/bị thu hồi — không có gì tự cứu được nữa, phải đưa app về màn hình
    // login (Prefs.clear() + NotificationCenter .sessionExpired) thay vì để lỗi 401 lặng lẽ.
    func test_401_refreshThatBai_xoaPhienVaBaoSessionExpired() async {
        Prefs.token = "token-het-han"
        Prefs.refreshToken = "refresh-cung-het-han"
        MockURLProtocol.handler = { req in
            if req.url?.path == "/api/auth/refresh" { return (200, Fixture.refreshFailed) }
            return (401, Data())
        }

        var didPostSessionExpired = false
        let observer = NotificationCenter.default.addObserver(forName: .sessionExpired, object: nil, queue: nil) { _ in
            didPostSessionExpired = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let sessions = await APIClient.shared.getSessions()

        XCTAssertTrue(sessions.isEmpty)
        XCTAssertNil(Prefs.token)
        XCTAssertNil(Prefs.refreshToken)
        XCTAssertTrue(didPostSessionExpired)
    }

    // Trái tim của bug đã vá: 3 request cùng dính 401 vì cùng dùng 1 token đã hết hạn — CHỈ được gọi
    // /api/auth/refresh ĐÚNG 1 LẦN, không phải 3 lần (3 lần thì backend xoay vòng refresh token
    // one-time-use, request thua cuộc bị từ chối rồi tự xoá sạch token mới vừa refresh thành công).
    func test_nhieuRequestCungLucDinh401_ChiRefreshDUNG_1_Lan() async {
        Prefs.token = "token-het-han"
        Prefs.refreshToken = "refresh-con-han"
        MockURLProtocol.awaitRequestCount = 3
        MockURLProtocol.handler = { req in
            if req.url?.path == "/api/auth/refresh" { return (200, Fixture.refreshSuccess) }
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer token-het-han" { return (401, Data()) }
            return (200, Fixture.sessionsEmpty)
        }

        async let r1 = APIClient.shared.getSessions()
        async let r2 = APIClient.shared.getSessions()
        async let r3 = APIClient.shared.getSessions()
        _ = await (r1, r2, r3)

        let refreshCalls = MockURLProtocol.captured.filter { $0.path == "/api/auth/refresh" }.count
        XCTAssertEqual(refreshCalls, 1, "3 request cùng 401 nhưng phải gộp lại chỉ 1 lần gọi refresh")
        XCTAssertEqual(Prefs.token, "token-moi")
    }

    func test_login_thanhCong() async {
        MockURLProtocol.handler = { req in
            XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"), "login không được đính kèm Bearer token cũ")
            return (200, Fixture.loginSuccess)
        }

        let result = await APIClient.shared.login(taiKhoan: "admin", matKhau: "matkhau")

        guard case .success(let resp) = result else {
            return XCTFail("Kỳ vọng .success, nhận \(result)")
        }
        XCTAssertEqual(resp.token, "t1")
    }

    func test_login_saiMatKhau_traVeRejectedKemMessage() async {
        MockURLProtocol.handler = { _ in (200, Fixture.loginRejected) }

        let result = await APIClient.shared.login(taiKhoan: "admin", matKhau: "sai")

        guard case .rejected(let message) = result else {
            return XCTFail("Kỳ vọng .rejected, nhận \(result)")
        }
        XCTAssertEqual(message, "Sai tai khoan hoac mat khau.")
    }
}
