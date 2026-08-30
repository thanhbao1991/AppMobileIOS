import Foundation
import UIKit

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
                // Refresh thất bại thật (token bị thu hồi/hết hạn ở nơi khác) — không có gì tự cứu
                // được nữa, phải đưa app quay về màn hình login thay vì để lỗi 401 lặng lẽ.
                Prefs.clear()
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
            }
            return (data, http)
        } catch {
            return (nil, nil)
        }
    }

    private func doRefresh(_ refreshToken: String) async -> String? {
        let req = makeRequest("/api/auth/refresh", method: "POST",
                               body: jsonBody(RefreshRequest(refreshToken: refreshToken, thietBi: deviceName(), nenTang: "iOS", thietBiId: deviceId())),
                               authorized: false)
        let (data, http) = await send(req, allowRefresh: false)
        guard let data, http?.statusCode == 200,
              let env = try? JSONDecoder().decode(ApiEnvelope<LoginResponse>.self, from: data),
              env.isSuccess, let resp = env.data, let token = resp.token else { return nil }
        Prefs.saveSession(token: token, refreshToken: resp.refreshToken, displayName: resp.tenHienThi)
        return token
    }

    func login(taiKhoan: String, matKhau: String) async -> LoginResult {
        let req = makeRequest("/api/auth/login", method: "POST",
                               body: jsonBody(LoginRequest(taiKhoan: taiKhoan, matKhau: matKhau, thietBi: deviceName(), nenTang: "iOS", thietBiId: deviceId())),
                               authorized: false)
        let (data, _) = await send(req, allowRefresh: false)
        guard let data else { return .networkError }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<LoginResponse>.self, from: data) else { return .networkError }
        if !env.isSuccess { return .rejected(env.message ?? "Sai tài khoản hoặc mật khẩu.") }
        guard let resp = env.data else { return .networkError }
        return .success(resp)
    }

    private func deviceName() -> String {
        UIDevice.current.name
    }

    /// Định danh ổn định của máy (khác deviceName() — tên máy do người dùng đặt, dễ trùng nếu 2 máy
    /// cùng chưa đổi tên mặc định "iPhone", từng khiến backend dedupe nhầm 2 máy là 1, thu hồi phiên
    /// lẫn nhau — xem incident_ios_multidevice_same_name_session_kick). identifierForVendor ổn định
    /// qua các lần mở app, chỉ đổi nếu gỡ hết app của cùng vendor.
    private func deviceId() -> String? {
        UIDevice.current.identifierForVendor?.uuidString
    }

    // Danh sách/gỡ thiết bị đăng nhập — màn hình "Thiết bị đăng nhập" trong MoreMenuView.
    func getSessions() async -> [PhienDangNhapDto] {
        let req = makeRequest("/api/Auth/sessions")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[PhienDangNhapDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func revokeSession(id: String) async -> ActionResult {
        let req = makeRequest("/api/Auth/sessions/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    func getHoaDonListByDay(_ dateIso: String) async -> [HoaDonListDto] {
        let req = makeRequest("/api/dashboard/hoa-don-list?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getCongNoList() async -> [HoaDonListDto] {
        let req = makeRequest("/api/dashboard/cong-no-list")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getThanhToanByDay(_ dateIso: String) async -> [ChiTietHoaDonThanhToanDto] {
        let req = makeRequest("/api/ChiTietHoaDonThanhToan?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTietHoaDonThanhToanDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getChiTieuByDay(_ dateIso: String) async -> [ChiTieuHangNgayDto] {
        let req = makeRequest("/api/ChiTieuHangNgay?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTieuHangNgayDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getChiTieuByMonth(year: Int, month: Int) async -> [ChiTieuHangNgayDto] {
        let req = makeRequest("/api/ChiTieuHangNgay/month?year=\(year)&month=\(month)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTieuHangNgayDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func createChiTieu(_ body: ChiTieuHangNgayCreateRequest) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateChiTieu(id: String, _ body: ChiTieuHangNgayCreateRequest) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteChiTieu(id: String) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    func deleteThanhToan(id: String) async -> ActionResult {
        let req = makeRequest("/api/ChiTietHoaDonThanhToan/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    func doiPhuongThucThanhToan(id: String) async -> ActionResult {
        let req = makeRequest("/api/ChiTietHoaDonThanhToan/\(id)/doi-phuong-thuc", method: "PUT")
        return await executeAction(req)
    }

    func getNguyenLieuBanHang() async -> [NguyenLieuBanHangDto] {
        let req = makeRequest("/api/NguyenLieuBanHang?take=1000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[NguyenLieuBanHangDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Nguyên liệu NHẬP dùng cho form Thêm chi tiêu — khớp desktop ChiTieuInputPanel (GET /api/NguyenLieu).
    func getNguyenLieu() async -> [NguyenLieuDto] {
        let req = makeRequest("/api/NguyenLieu")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[NguyenLieuDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getCongViecList() async -> [CongViecNoiBoDto] {
        let req = makeRequest("/api/CongViecNoiBo")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[CongViecNoiBoDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func createCongViec(ten: String) async -> ActionResult {
        let body = CongViecNoiBoRequest(ten: ten, daHoanThanh: false, ngayGio: isoNow())
        let req = makeRequest("/api/CongViecNoiBo", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateCongViec(id: String, ten: String, daHoanThanh: Bool, ngayGio: String?) async -> ActionResult {
        let body = CongViecNoiBoRequest(ten: ten, daHoanThanh: daHoanThanh, ngayGio: ngayGio)
        let req = makeRequest("/api/CongViecNoiBo/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func getThongKeChiTieu(ngay: Int, thang: Int, nam: Int) async -> ThongKeChiTieuDto? {
        await getThongKe("chi-tieu-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeCongNo(ngay: Int, thang: Int, nam: Int) async -> ThongKeCongNoDto? {
        await getThongKe("cong-no-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeThanhToan(ngay: Int, thang: Int, nam: Int) async -> ThongKeThanhToanDto? {
        await getThongKe("thanh-toan-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeDoanhThu(ngay: Int, thang: Int, nam: Int) async -> ThongKeDoanhThuNgayDto? {
        await getThongKe("doanh-thu-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeTraNo(ngay: Int, thang: Int, nam: Int) async -> ThongKeTraNoNgayDto? {
        await getThongKe("tra-no-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeDonChuaThanhToan(ngay: Int, thang: Int, nam: Int) async -> ThongKeDonChuaThanhToanDto? {
        await getThongKe("don-chua-thanh-toan", ngay: ngay, thang: thang, nam: nam)
    }
    func getTongNo() async -> TongNoDto? {
        let req = makeRequest("/api/ThongKe/tong-no")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<TongNoDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    private func getThongKe<T: Decodable>(_ endpoint: String, ngay: Int, thang: Int, nam: Int) async -> T? {
        let req = makeRequest("/api/ThongKe/\(endpoint)?ngay=\(ngay)&thang=\(thang)&nam=\(nam)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<T>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getThongKeChiTieuThang(thang: Int, nam: Int) async -> ThongKeChiTieuDto? {
        await getThongKeThang("chi-tieu-thang", thang: thang, nam: nam)
    }
    func getThongKeThanhToanThang(thang: Int, nam: Int) async -> ThongKeThanhToanDto? {
        await getThongKeThang("thanh-toan-thang", thang: thang, nam: nam)
    }
    func getThongKeDoanhThuThang(thang: Int, nam: Int) async -> ThongKeDoanhThuNgayDto? {
        await getThongKeThang("doanh-thu-thang", thang: thang, nam: nam)
    }
    func getThongKeTraNoThang(thang: Int, nam: Int) async -> ThongKeTraNoNgayDto? {
        await getThongKeThang("tra-no-thang", thang: thang, nam: nam)
    }
    func getThongKeDonChuaThanhToanThang(thang: Int, nam: Int) async -> ThongKeDonChuaThanhToanDto? {
        await getThongKeThang("don-chua-thanh-toan-thang", thang: thang, nam: nam)
    }

    func getDoanhThuChiTietThang(thang: Int, nam: Int, ten: String) async -> [HoaDonListDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/doanh-thu-chi-tiet-thang?thang=\(thang)&nam=\(nam)&ten=\(tenEncoded)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getThanhToanChiTietThang(thang: Int, nam: Int, ten: String) async -> [ThanhToanChiTietItemDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/thanh-toan-chi-tiet-thang?thang=\(thang)&nam=\(nam)&ten=\(tenEncoded)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ThanhToanChiTietItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Chi tiết card "Khách trả nợ" (bản ngày) — GetTraNoAsync gộp SUM theo tên khách nên card không
    /// có hoaDonId để tap; endpoint riêng này giữ nguyên bộ lọc nhưng trả nguyên danh sách.
    func getTraNoChiTietThang(thang: Int, nam: Int, ten: String, isShipper: Bool) async -> [ThanhToanChiTietItemDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/tra-no-chi-tiet-thang?thang=\(thang)&nam=\(nam)&ten=\(tenEncoded)&isShipper=\(isShipper)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ThanhToanChiTietItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    private func getThongKeThang<T: Decodable>(_ endpoint: String, thang: Int, nam: Int) async -> T? {
        let req = makeRequest("/api/ThongKe/\(endpoint)?thang=\(thang)&nam=\(nam)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<T>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Proxy VietQR qua Backend (bank config chỉ sống ở BankQrConfig phía server — Desktop/Mobile
    /// dùng chung, iOS gọi qua đây nên đổi tài khoản 1 chỗ là mọi client ra cùng 1 mã QR).
    /// Ảnh HoaDonGrid mới nhất từ máy Desktop `label` (2026-08-27: đổi từ SignalR push sang HTTP
    /// GET thường, xem DesktopScreenController phía Backend + DesktopScreenView.swift) — trả kèm
    /// tuổi khung hình (ms) đọc từ header `X-Frame-Age-Ms` để view tự quyết "đã lâu không có khung
    /// mới" thay vì đo timestamp cục bộ, phòng đồng hồ máy lệch.
    func getDesktopScreenFrame(label: String) async -> (data: Data, ageMs: Int)? {
        let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? label
        let req = makeRequest("/api/desktopscreen/\(encodedLabel)/frame")
        let (data, http) = await send(req)
        guard let data, http?.statusCode == 200 else { return nil }
        let ageMs = Int(http?.value(forHTTPHeaderField: "X-Frame-Age-Ms") ?? "") ?? 0
        return (data, ageMs)
    }

    func getBillQrImage(amount: Double, addInfo: String) async -> Data? {
        let vnd = Int(amount.rounded())
        let query = "amount=\(vnd)&addInfo=\(addInfo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let req = makeRequest("/api/HoaDon/bill-qr?\(query)")
        let (data, http) = await send(req)
        guard let data, http?.statusCode == 200 else { return nil }
        return data
    }

    /// Nội dung chuyển khoản cho QR GỘP NHIỀU hoá đơn (CongNoListView) — tính trên Backend qua
    /// BankQrConfig.BuildAddInfo, KHÔNG tự build ở Swift nữa (từng lệch tiền tố "SEVQR" giữa 2 bên
    /// hồi 2026-08-23 vì có 2 bản implement song song).
    func getGopAddInfo(ten: String, maDau: String, maCuoi: String?) async -> String? {
        var query = "ten=\(ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" +
                    "&maDau=\(maDau.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let maCuoi, !maCuoi.isEmpty {
            query += "&maCuoi=\(maCuoi.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        let req = makeRequest("/api/HoaDon/gop-addinfo?\(query)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<String>.self, from: data), env.isSuccess else { return nil }
        return env.data
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

    func createHoaDonFull(_ body: HoaDonFullCreateRequest) async -> CreateActionResult {
        let req = makeRequest("/api/HoaDon", method: "POST", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data,
              let env = try? JSONDecoder().decode(ApiEnvelope<IdOnlyDto>.self, from: data) else {
            return CreateActionResult(success: false, message: "Không có phản hồi từ server.", id: nil)
        }
        return CreateActionResult(success: env.isSuccess, message: env.message, id: env.data?.id)
    }

    /// Danh sách sản phẩm/topping đang bán — tải 1 lần lúc mở form thêm hoá đơn rồi lọc/tìm cục bộ
    /// (khớp cách Desktop cache AppDataCache.SanPhams, không gọi search API theo từng phím gõ).
    func getSanPhamList() async -> [SanPhamDto] {
        let req = makeRequest("/api/SanPham")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[SanPhamDto]>.self, from: data), env.isSuccess else { return [] }
        return (env.data ?? []).filter { !$0.ngungBan }
    }

    func getToppingList() async -> [ToppingDto] {
        let req = makeRequest("/api/Topping")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ToppingDto]>.self, from: data), env.isSuccess else { return [] }
        return (env.data ?? []).filter { !$0.ngungBan }
    }

    /// Giá riêng đã lưu cho MỌI khách — endpoint không hỗ trợ lọc theo khách (khớp cách Desktop
    /// tải hết AppDataCache.GiaBanRiengs rồi lọc cục bộ theo KhachHangId khi cần).
    func getKhachHangGiaBanList() async -> [KhachHangGiaBanDto] {
        let req = makeRequest("/api/KhachHangGiaBan?take=5000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangGiaBanDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Toàn bộ khách hàng (không lọc) — dùng cho tính năng đồng bộ Danh bạ, take cao để chắc chắn
    /// lấy hết (GetAllAsync bên backend không có cap cứng, chỉ giới hạn khi truyền take).
    func getAllKhachHang() async -> [KhachHangDto] {
        let req = makeRequest("/api/KhachHang?take=100000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func searchKhachHang(_ q: String) async -> [KhachHangDto] {
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let query = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let req = makeRequest("/api/KhachHang/search?q=\(query)&take=20")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getKhachHangInfo(khachHangId: String) async -> KhachHangInfoDto? {
        let req = makeRequest("/api/HoaDon/get-khach-hang-info/\(khachHangId)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangInfoDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getKhachHangHayGoiSom() async -> [KhachHangGoiSomDto] {
        let req = makeRequest("/api/HoaDon/khach-hay-goi-som")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangGoiSomDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// "Bắt đơn App" — khớp GetDonAsync (Desktop). List() trả Result<object> (không phải
    /// Result<List<...>>) nhưng runtime type vẫn là mảng đơn khi thành công nên decode với
    /// ApiEnvelope<[AppOrderSummaryDto]> vẫn khớp; lúc lỗi (chưa cấu hình Shipping) data=null.
    func getAppOrderList() async -> (orders: [AppOrderSummaryDto], message: String?) {
        let req = makeRequest("/api/AppOrder/list")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[AppOrderSummaryDto]>.self, from: data) else {
            return ([], "Không có phản hồi từ server.")
        }
        guard env.isSuccess else { return ([], env.message) }
        return (env.data ?? [], nil)
    }

    func getAppOrderDetail(_ id: String) async -> (detail: AppOrderDetailDto?, message: String?, warnings: [String]) {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let req = makeRequest("/api/AppOrder/detail/\(encodedId)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<AppOrderDetailDto>.self, from: data) else {
            return (nil, "Không có phản hồi từ server.", [])
        }
        guard env.isSuccess else { return (nil, env.message, []) }
        return (env.data, nil, env.warnings ?? [])
    }

    func getKhachHangById(_ id: String) async -> KhachHangDto? {
        let req = makeRequest("/api/KhachHang/\(id)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Khớp CreateKhachBtn_Click (Desktop): trùng SĐT với khách có sẵn thì server trả lỗi kèm tên
    /// khách đó trong message — KHÔNG tự tìm/chọn lại giúp (khác Desktop có cache toàn bộ khách để
    /// tự dò), hiển thị lỗi để nhân viên tự tìm khách đó qua ô tìm kiếm.
    func createKhachHang(_ body: KhachHangCreateRequest) async -> (success: Bool, message: String?, khach: KhachHangDto?) {
        let req = makeRequest("/api/KhachHang", method: "POST", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangDto>.self, from: data) else {
            return (false, "Không có phản hồi từ server.", nil)
        }
        return (env.isSuccess, env.message, env.data)
    }

    /// Sửa tên/SĐT/địa chỉ (nhiều dòng)/voucher của khách đã có — khớp SaveKhachContactBtn_Click
    /// (Desktop): PUT full KhachHangDto, server tự thêm/xoá KhachHangPhones/Addresses theo Id khớp
    /// (KhachHangCrudService.UpdateAsync) — dòng có Id trùng thì sửa tại chỗ, không có thì thêm mới,
    /// bị thiếu trong payload thì xoá. KHÔNG đụng SoDu (server không đọc field này khi Update).
    func updateKhachHang(_ body: KhachHangDto) async -> (success: Bool, message: String?, khach: KhachHangDto?) {
        let req = makeRequest("/api/KhachHang/\(body.id)", method: "PUT", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangDto>.self, from: data) else {
            return (false, "Không có phản hồi từ server.", nil)
        }
        return (env.isSuccess, env.message, env.data)
    }

    func ganShipper(hoaDonId: String, nguoiShip: String) async -> ActionResult {
        let now = isoNow()
        let body = GanShipperRequest(id: hoaDonId, nguoiShip: nguoiShip, ngayShip: now, ngayIn: now)
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/esc", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }
}
