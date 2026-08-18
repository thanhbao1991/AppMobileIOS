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
    let diaChiText: String?
    let soDienThoaiText: String?
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

struct HoaDonPaymentBriefDto: Decodable, Identifiable {
    let id: String
    let phuongThucThanhToanId: String
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
    let ngayNo: String?
    let tongTien: Double
    let giamGia: Double
    let thanhTien: Double
    let daThu: Double
    let conLai: Double
    let tongNoKhachHang: Double?
    let chiTietHoaDons: [ChiTietHoaDonResponseDto]?
    let chiTietHoaDonToppings: [ChiTietHoaDonToppingResponseDto]?
    let payments: [HoaDonPaymentBriefDto]?
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

// ---- Thanh toán (chi tiết) ----

struct ChiTietHoaDonThanhToanDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let loaiThanhToan: String?
    let soTien: Double
    let ngayGio: String?
    let ngay: String?
    let hoaDonId: String
    let ghiChu: String?
    let tenMonSummary: String?
    let phuongThucThanhToanId: String?
}

// ---- Chi tiêu hằng ngày ----

struct ChiTieuHangNgayDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let soLuong: Double
    let donGia: Double
    let thanhTien: Double
    let ghiChu: String?
    let ngay: String?
    let ngayGio: String?
    let nguyenLieuId: String
    let billThang: Bool
}

struct ChiTieuHangNgayCreateRequest: Encodable {
    let soLuong: Double
    let donGia: Double
    let thanhTien: Double
    let ghiChu: String?
    let ngay: String
    let ngayGio: String
    let nguyenLieuId: String
    let billThang: Bool
}

struct NguyenLieuBanHangDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let donViTinh: String?
}

// ---- Công việc nội bộ ----

struct CongViecNoiBoDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let daHoanThanh: Bool
    let ngayGio: String?
}

struct CongViecNoiBoRequest: Encodable {
    let ten: String
    let daHoanThanh: Bool
    let ngayGio: String?
}

// ---- Thống kê (port từ TraSuaApp.Desktop ThongKeTabControl — nguồn chính xác, KHÔNG dùng
// TraSuaApp.Mobile/Pages/ThongKe.cshtml vì trang đó không còn liên kết từ navbar) ----

struct NamedAmountDto: Decodable, Identifiable {
    let ten: String
    let soTien: Double
    var id: String { ten }
}

struct DoanhThuItemDto: Decodable, Identifiable {
    let ten: String
    let doanhThu: Double
    var id: String { ten }
}

struct KhachTienDto: Decodable, Identifiable {
    let tenKhachHang: String
    let soTien: Double
    var id: String { tenKhachHang }
}

struct CongNoItemDto: Decodable, Identifiable {
    let khachHangId: String?
    let hoaDonId: String?
    let ngayGio: String?
    let tenKhachHang: String
    let soTienNo: Double
    var id: String { hoaDonId ?? (khachHangId ?? tenKhachHang) }
}

struct DonChuaThanhToanItemDto: Decodable, Identifiable {
    let khachHangId: String?
    let hoaDonId: String?
    let tenKhachHang: String
    let soTien: Double
    var id: String { hoaDonId ?? (khachHangId ?? tenKhachHang) }
}

struct TongNoItemDto: Decodable, Identifiable {
    let khachHangId: String?
    let tenKhachHang: String
    let tongConLai: Double
    var id: String { khachHangId ?? tenKhachHang }
}

struct ThongKeChiTieuDto: Decodable {
    let chiTieuNgay: Double
    let danhSachChiTieuNgay: [NamedAmountDto]
    let chiTieuThang: Double
    let danhSachChiTieuThang: [NamedAmountDto]
}

struct ThongKeCongNoDto: Decodable {
    let tongCongNoNgay: Double
    let danhSachCongNoNgay: [CongNoItemDto]
}

struct ThongKeThanhToanDto: Decodable {
    let tongTienMat: Double
    let tongChuyenKhoan: Double
    let danhSachTienMat: [NamedAmountDto]
}

struct ThongKeDoanhThuNgayDto: Decodable {
    let tongDoanhThu: Double
    let danhSach: [DoanhThuItemDto]
}

struct ThongKeTraNoNgayDto: Decodable {
    let tongTraNoTaiQuan: Double
    let tongTraNoShipper: Double
    let traNoTaiQuan: [KhachTienDto]
    let traNoShipper: [KhachTienDto]
}

struct ThongKeDonChuaThanhToanDto: Decodable {
    let tongChuaThanhToan: Double
    let danhSach: [DonChuaThanhToanItemDto]
}

struct TongNoDto: Decodable {
    let tongConLai: Double
    let danhSach: [TongNoItemDto]
}

struct IdOnlyRequest: Encodable { let id: String }
struct GanShipperRequest: Encodable { let id: String; let nguoiShip: String; let ngayShip: String; let ngayIn: String }

struct ActionResult { let success: Bool; let message: String? }

// ---- Khách hàng (tìm/tạo trong form thêm hoá đơn) ----

struct KhachHangPhoneDto: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    let soDienThoai: String
    let isDefault: Bool
}

struct KhachHangAddressDto: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    let diaChi: String
    let isDefault: Bool
}

/// KHÔNG dùng field "dienThoai"/"diaChi" (computed property phía server) — với kết quả từ
/// /api/KhachHang/search, backend build Phones/Addresses thủ công (KhachHangQueryService.SearchAsync)
/// và không set IsDefault, khiến 2 getter đó trả rỗng dù phones/addresses có dữ liệu. Luôn lấy trực
/// tiếp từ phones[0]/addresses[0] (server đã OrderByDescending IsDefault/LastModified sẵn).
struct KhachHangDto: Codable, Identifiable {
    let id: String
    let ten: String
    let soDu: Double
    let duocNhanVoucher: Bool
    let phones: [KhachHangPhoneDto]
    let addresses: [KhachHangAddressDto]
}

struct KhachHangCreateRequest: Encodable {
    let ten: String
    let duocNhanVoucher: Bool
    let phones: [KhachHangPhoneDto]
    let addresses: [KhachHangAddressDto]
}

struct KhachHangFavoriteItemDto: Decodable, Identifiable {
    var id: String { "\(tenSanPham)|\(tenBienThe)" }
    let tenSanPham: String
    let tenBienThe: String
}

/// Khớp KhachHangInfoDto (Backend) — thông tin điểm/nợ/ví/voucher/món yêu thích khi chọn khách
/// trong form thêm hoá đơn. Field "soDu"/"tongNo"/"donKhac" khác tên với HoaDonDto (soDuVi/
/// tongNoKhachHang/tongDonKhacDangGiao) vì đây là 2 DTO backend riêng biệt — không đoán gộp.
struct KhachHangInfoDto: Decodable {
    let khachHangId: String
    let duocNhanVoucher: Bool
    let daNhanVoucher: Bool
    let diemThangNay: Int
    let diemThangTruoc: Int
    let soDu: Double
    let tongNo: Double
    let donKhac: Double
    let monGanDay: [KhachHangFavoriteItemDto]
    let monHayMua: [KhachHangFavoriteItemDto]
}

/// Giá riêng đã lưu theo khách (KhachHangGiaBan) — chỉ cần 2 field để build map áp giá tự động,
/// không cần fetch riêng theo khách vì backend không có filter, tải hết 1 lần rồi lọc local.
struct KhachHangGiaBanDto: Decodable {
    let khachHangId: String
    let sanPhamBienTheId: String
    let giaBan: Double
}

// ---- Sản phẩm / Topping (chọn món trong form thêm hoá đơn) ----

struct SanPhamBienTheDto: Decodable, Identifiable, Hashable {
    let id: String
    let sanPhamId: String
    let tenBienThe: String
    let giaBan: Double
    let macDinh: Bool
}

struct SanPhamDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let ngungBan: Bool
    let tenNhomSanPham: String?
    let bienThe: [SanPhamBienTheDto]
}

struct ToppingDto: Decodable, Identifiable, Hashable {
    let id: String
    let ten: String
    let gia: Double
    let ngungBan: Bool
}

// ---- Tạo hoá đơn đầy đủ (món + khách + giảm giá) ----
// Payload khớp HoaDonChiTietService.AddAsync (Backend): "id" của từng dòng chỉ dùng để liên kết
// topping cùng dòng qua chiTietHoaDonToppings[].chiTietHoaDonId, KHÔNG phải Id thật sẽ lưu (server
// tự sinh SequentialGuid riêng) — dùng UUID() cục bộ là đủ.

struct ChiTietHoaDonToppingCreateDto: Encodable {
    let chiTietHoaDonId: String
    let toppingId: String
    let ten: String
    let soLuong: Int
    let gia: Double
}

struct ChiTietHoaDonCreateDto: Encodable {
    let id: String
    let sanPhamBienTheId: String
    let soLuong: Int
    let donGia: Double
    let tenSanPham: String
    let tenBienThe: String
    let toppingText: String?
    let noteText: String?
}

struct HoaDonFullCreateRequest: Encodable {
    let phanLoai: String
    let tenBan: String?
    let khachHangId: String?
    let tenKhachHangText: String?
    let soDienThoaiText: String?
    let diaChiText: String?
    let ghiChu: String?
    let giamGia: Double
    let chiTietHoaDons: [ChiTietHoaDonCreateDto]
    let chiTietHoaDonToppings: [ChiTietHoaDonToppingCreateDto]
}

// ---- Tạo hoá đơn mới ----
// Backend (HoaDonCrudService.CreateAsync) tự sinh Id (SequentialGuid) khi thiếu, tự set
// Ngay/NgayGio = giờ hiện tại. TenBan bắt buộc riêng cho "Tại Chỗ" (RequireTableMessage phía server).
struct IdOnlyDto: Decodable { let id: String }
struct CreateActionResult { let success: Bool; let message: String?; let id: String? }
