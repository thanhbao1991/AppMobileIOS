import Foundation

/// Port 1:1 từ AppMobileAndroid/ApiClient.kt (OkHttp+Gson → URLSession+Codable). Bearer token
/// tự đính kèm, tự refresh 1 lần khi gặp 401 rồi retry đúng request gốc — khớp hành vi
/// authenticator bên Android.
actor APIClient {
    static let shared = APIClient()

    private func jsonBody<T: Encodable>(_ obj: T) -> Data {
        try! JSONEncoder().encode(obj)
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil, authorized: Bool = true) -> URLRequest {
        var req = URLRequest(url: URL(string: Prefs.apiBase + path)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = Prefs.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    private func send(_ req: URLRequest, allowRefresh: Bool = true) async -> (Data?, HTTPURLResponse?) {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            if http?.statusCode == 401, allowRefresh, let refreshToken = Prefs.refreshToken {
                if let newToken = await doRefresh(refreshToken) {
                    var retried = req
                    retried.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    return await send(retried, allowRefresh: false)
                }
            }
            return (data, http)
        } catch {
            return (nil, nil)
        }
    }

    private func doRefresh(_ refreshToken: String) async -> String? {
        let req = makeRequest("/api/auth/refresh", method: "POST", body: jsonBody(RefreshRequest(refreshToken: refreshToken)), authorized: false)
        let (data, http) = await send(req, allowRefresh: false)
        guard let data, http?.statusCode == 200,
              let env = try? JSONDecoder().decode(ApiEnvelope<LoginResponse>.self, from: data),
              env.isSuccess, let resp = env.data, let token = resp.token else { return nil }
        Prefs.saveSession(token: token, refreshToken: resp.refreshToken, displayName: resp.tenHienThi)
        return token
    }

    func login(taiKhoan: String, matKhau: String) async -> LoginResult {
        let req = makeRequest("/api/auth/login", method: "POST", body: jsonBody(LoginRequest(taiKhoan: taiKhoan, matKhau: matKhau)), authorized: false)
        let (data, _) = await send(req, allowRefresh: false)
        guard let data else { return .networkError }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<LoginResponse>.self, from: data) else { return .networkError }
        if !env.isSuccess { return .rejected(env.message ?? "Sai tài khoản hoặc mật khẩu.") }
        guard let resp = env.data else { return .networkError }
        return .success(resp)
    }

    func getHoaDonListByDay(_ dateIso: String) async -> [HoaDonListDto] {
        let req = makeRequest("/api/dashboard/hoa-don-list?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getHoaDonDetail(_ id: String) async -> HoaDonDetailDto? {
        let req = makeRequest("/api/HoaDon/\(id)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<HoaDonDetailDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Parse thô bằng JSONSerialization (không ràng buộc shape "data") — khớp cách Kotlin dùng
    /// JsonParser thô cho các action, tránh Decodable fail nếu "data" trả về khác dự đoán.
    private func executeAction(_ req: URLRequest) async -> ActionResult {
        let (data, _) = await send(req)
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ActionResult(success: false, message: "Không có phản hồi từ server.")
        }
        let success = (obj["isSuccess"] as? Bool) ?? false
        let message = obj["message"] as? String
        return ActionResult(success: success, message: message)
    }

    private func isoNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Thu đủ số tiền còn lại — không hỗ trợ thu 1 phần/ví, khớp giới hạn khung bên Android.
    func thuTien(hoaDonId: String, isCash: Bool, soTien: Double, ten: String, khachHangId: String?) async -> ActionResult {
        let path = isCash ? "f1" : "f4"
        let now = isoNow()
        let body = ThanhToanRequest(
            ten: ten, hoaDonId: hoaDonId, soTien: soTien, ngayGio: now, ngay: now,
            khachHangId: khachHangId,
            phuongThucThanhToanId: isCash ? PaymentMethod.tienMatId : PaymentMethod.chuyenKhoanId
        )
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/\(path)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func ghiNo(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/f12", method: "PUT", body: jsonBody(IdOnlyRequest(id: hoaDonId)))
        return await executeAction(req)
    }

    func rollback(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/rollback", method: "PUT", body: jsonBody(IdOnlyRequest(id: hoaDonId)))
        return await executeAction(req)
    }

    func delete(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)", method: "DELETE")
        return await executeAction(req)
    }

    func ganShipper(hoaDonId: String, nguoiShip: String) async -> ActionResult {
        let now = isoNow()
        let body = GanShipperRequest(id: hoaDonId, nguoiShip: nguoiShip, ngayShip: now, ngayIn: now)
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/esc", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }
}
