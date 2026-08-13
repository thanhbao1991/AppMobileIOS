import Foundation

// Port 1:1 từ AppMobileAndroid/Dtos.kt — field name phải khớp tuyệt đối JSON backend trả về
// (không có CodingKeys riêng, tên property Swift = tên field JSON).

struct ApiEnvelope<T: Decodable>: Decodable {
    let isSuccess: Bool
    let message: String?
    let data: T?
}

// ---- Auth ----

struct LoginRequest: Encodable { let taiKhoan: String; let matKhau: String }
struct RefreshRequest: Encodable { let refreshToken: String }

struct LoginResponse: Decodable {
    let thanhCong: Bool?
    let message: String?
    let token: String?
    let tenHienThi: String?
    let vaiTro: String?
    let refreshToken: String?
}

enum LoginResult {
    case success(LoginResponse)
    case rejected(String)
    case networkError
}

// ---- Hoá đơn ----

struct HoaDonListDto: Decodable, Identifiable {
    let id: String
    let khachHangId: String?
    let tenKhachHangText: String?
    let tenBan: String?
    let phanLoai: String?
    let ngayGio: String?
    let lastModified: String?
    let ngayShip: String?
    let ngayNo: String?
    let ngayIn: String?
    let ngayThanhToan: String?
    let nguoiShip: String?
    let ghiChu: String?
    let ghiChuShipper: String?
    let isBank: Bool?
    let thanhTien: Double
    let conLai: Double
    let tenMonSummary: String?
}

struct ChiTietHoaDonToppingResponseDto: Decodable, Identifiable {
    var id: String { ten }
    let ten: String
    let soLuong: Int
    let gia: Double
}

struct ChiTietHoaDonResponseDto: Decodable, Identifiable {
    let id: String
    let tenSanPham: String
    let tenBienThe: String?
    let soLuong: Int
    let donGia: Double
    let noteText: String?
    let toppingText: String?
}

struct HoaDonDetailDto: Decodable {
    let id: String
    let khachHangId: String?
    let phanLoai: String?
    let tenBan: String?
    let ngayGio: String?
    let tenKhachHangText: String?
    let soDienThoaiText: String?
    let diaChiText: String?
    let ghiChu: String?
    let ghiChuShipper: String?
    let nguoiShip: String?
    let tongTien: Double
    let giamGia: Double
    let thanhTien: Double
    let daThu: Double
    let conLai: Double
    let tongNoKhachHang: Double?
    let chiTietHoaDons: [ChiTietHoaDonResponseDto]?
    let chiTietHoaDonToppings: [ChiTietHoaDonToppingResponseDto]?
}

// ---- Thao tác nhanh trên hoá đơn ----
// Route + body xác nhận từ TraSuaApp.Desktop/Controls/HoaDonTabControl.Actions.cs, giống hệt
// AppMobileAndroid/ApiClient.kt — KHÔNG đoán, API động vào tiền thật.

enum PaymentMethod {
    static let tienMatId = "0121fc04-0469-4908-8b9a-7002f860fb5c"
    static let chuyenKhoanId = "2cf9a88f-3bc0-4d4b-940d-f8ffa4affa02"
}

struct ThanhToanRequest: Encodable {
    let ten: String
    let hoaDonId: String
    let soTien: Double
    let ngayGio: String
    let ngay: String
    let khachHangId: String?
    let phuongThucThanhToanId: String
    let viTien: Bool = false
}

struct IdOnlyRequest: Encodable { let id: String }
struct GanShipperRequest: Encodable { let id: String; let nguoiShip: String; let ngayShip: String; let ngayIn: String }

struct ActionResult { let success: Bool; let message: String? }
