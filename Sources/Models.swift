import Foundation

// Port 1:1 từ AppMobileAndroid/Dtos.kt — field name phải khớp tuyệt đối JSON backend trả về
// (không có CodingKeys riêng, tên property Swift = tên field JSON).

struct ApiEnvelope<T: Decodable>: Decodable {
    let isSuccess: Bool
    let message: String?
    let data: T?
    let warnings: [String]?
}

// ---- Auth ----

struct LoginRequest: Encodable { let taiKhoan: String; let matKhau: String; let thietBi: String?; let nenTang: String?; let thietBiId: String? }
struct RefreshRequest: Encodable { let refreshToken: String; let thietBi: String?; let nenTang: String?; let thietBiId: String? }

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

// Danh sách thiết bị đang đăng nhập (màn hình "Thiết bị đăng nhập") — giống trang Tài khoản Apple.
struct PhienDangNhapDto: Decodable, Identifiable {
    let id: String
    let thietBi: String?
    let nenTang: String?
    let tenTaiKhoan: String?
    let ngayTao: String
    let hetHan: String
    let laThietBiHienTai: Bool
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
    /// true = có dòng chuyển khoản do SePay webhook tự thu — hiện icon robot trên badge "Chuyển khoản"
    /// để phân biệt với thu tay. Xem ChiTietHoaDonThanhToanDto.tuDongLuc.
    let isAutoBank: Bool?
    let thanhTien: Double
    let conLai: Double
    let tenMonSummary: String?
    /// "HD" + 8 ký tự đầu Id, tính sẵn bên Backend — dùng ghép nội dung QR khi gộp nhiều đơn
    /// (xem CongNoListView.copyBillImage), khỏi tự cắt chuỗi id ở client.
    let maHoaDon: String?
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
    let maHoaDonNoKhac: [String]?
    /// Nội dung chuyển khoản QR tính sẵn ("TEN HD1234 DEN HD9999") — Backend build (khớp
    /// BankQrConfig.BuildAddInfo / HoaDonPrinter Desktop), không tự ghép lại ở client nữa.
    let billAddInfo: String?
    /// Thông tin tài khoản nhận tiền — đọc thẳng từ Backend (BankQrConfig), không hardcode lại ở
    /// client, khớp nguyên tắc "1 nguồn duy nhất" (xem HoaDonDto.cs). Dùng để soạn SMS/hiển thị.
    let bankName: String?
    let bankAccountNo: String?
    let bankAccountName: String?
    let chiTietHoaDons: [ChiTietHoaDonResponseDto]?
    let chiTietHoaDonToppings: [ChiTietHoaDonToppingResponseDto]?
    let payments: [HoaDonPaymentBriefDto]?
    /// Tài khoản đã tạo đơn — nil nếu đơn khách tự đặt qua app (không phải nhân viên).
    let tenTaiKhoan: String?
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
    /// null = thu tay; có giá trị = SePay webhook tự thu — hiện icon robot phân biệt trên badge.
    let tuDongLuc: String?
    /// Tài khoản đã bấm thu tiền — nil nếu dòng do hệ thống tự thu (SePay webhook, xem tuDongLuc).
    let tenTaiKhoan: String?
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
    /// Tài khoản đã thêm dòng chi tiêu này — nil ở dữ liệu cũ trước khi có field.
    let tenTaiKhoan: String?
}

struct ChiTieuHangNgayCreateRequest: Encodable {
    let ten: String
    let soLuong: Double
    let donGia: Double
    let thanhTien: Double
    let ghiChu: String?
    let ngay: String
    let ngayGio: String
    let nguyenLieuId: String
    let billThang: Bool
}

// ---- Thêm chi tiêu từ ảnh hoá đơn (Gemini) ----

struct ReceiptParseLineDto: Decodable, Identifiable {
    var id: String { rawText }
    let rawText: String
    let soLuong: Double
    let donGia: Double
    let suggestedNguyenLieuId: String?
    let suggestedNguyenLieuTen: String?
    let suggestedFromLearnedAlias: Bool
}

struct ReceiptParseResultDto: Decodable {
    let lines: [ReceiptParseLineDto]
}

struct ChiTieuHangNgayBulkItemRequest: Encodable {
    let nguyenLieuId: String
    let ten: String?
    let soLuong: Double
    let donGia: Double
    let thanhTien: Double?
    let ghiChu: String?
    let billThang: Bool
    /// Có giá trị thì Backend tự học/ghi đè alias RawText → nguyenLieuId cho lần đọc ảnh sau —
    /// xem ChiTieuHangNgayBulkItemDto.RawText (Backend).
    let rawText: String?
}

struct ChiTieuHangNgayBulkCreateRequest: Encodable {
    let ngay: String
    let ngayGio: String?
    let billThang: Bool
    let items: [ChiTieuHangNgayBulkItemRequest]
}

struct NguyenLieuBanHangDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let donViTinh: String?
}

/// Nguyên liệu NHẬP (mục để chi, vd "Shoppee A ty") — /api/NguyenLieu, khác hẳn NguyenLieuBanHangDto
/// (nguyên liệu công thức bán hàng). Khớp TraSuaApp.Desktop/Controls/ChiTieuInputPanel dùng NguyenLieuDto.
struct NguyenLieuDto: Decodable, Identifiable {
    let id: String
    let ten: String
    let giaNhap: Double
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

// ---- Thông báo/khuyến mãi (app khách AppDatHangIOS đọc qua ThongBaoService, quản trị ở đây) ----

struct ThongBaoQuanDto: Codable, Identifiable {
    let id: String
    var tieude: String
    var noiDung: String
    var dangHoatDong: Bool
    let ngayTao: String?
}

struct ThongBaoQuanRequest: Encodable {
    let tieude: String
    let noiDung: String
    let dangHoatDong: Bool
}

// ---- Cấu hình ngưỡng/số tiền gamification (app khách AppDatHangIOS) ----

struct VongQuayPhanThuongDto: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var label: String
    var trongSo: Int
    var thuong: Double
}

struct GamificationConfigDto: Codable {
    var lyBiMatGiaTraTien: Double
    var lyBiMatNguongGiaThat: Double
    var gioiThieuThuong: Double
    var sinhNhatThuong: Double
    var stampMocThuong: Int
    var vongQuayPhanThuong: [VongQuayPhanThuongDto]
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

struct ThanhToanChiTietItemDto: Decodable, Identifiable {
    let hoaDonId: String
    let tenKhachHang: String
    let ngayGio: String
    let soTien: Double
    var id: String { hoaDonId + ngayGio }
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

struct GiamGiaItemDto: Decodable, Identifiable {
    let hoaDonId: String
    let tenKhachHang: String
    let soTien: Double
    var id: String { hoaDonId }
}

struct ThongKeGiamGiaDto: Decodable {
    let tongGiamGia: Double
    let tongDonQuan: Double
    let danhSachDonQuan: [GiamGiaItemDto]
    let tongDonApp: Double
    let danhSachDonApp: [GiamGiaItemDto]
    let tongDonMuaHo: Double
    let danhSachDonMuaHo: [GiamGiaItemDto]
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
    let facebookThreadId: String?
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

/// Khách hay gọi trước 7h (nút "Đơn 7h") — khớp HoaDonTabControl.Board.cs (Desktop):
/// KhachGoiSomAsync + OpenKhachGoiSom (SetPhanLoai(Ship) + PreFillKhachHang kèm món cuối).
struct KhachHangGoiSomDto: Decodable, Identifiable {
    let khachHangId: String
    let ten: String
    let soLan: Int
    let tenSanPham: String
    let tenBienThe: String
    let laKhachMoi: Bool
    var id: String { khachHangId }
}

// ---- Bắt đơn App (store shippershipping) ----
// Khớp GetDonAsync (Desktop, HoaDonTabControl.Board.cs): /api/AppOrder/list → chọn 1 đơn →
// /api/AppOrder/detail/{id} trả sẵn HoaDonDto với ChiTietHoaDons đã map SanPhamBienTheId thật
// (AppOrderService.ParseHoaDon/MapBienThe phía server) — client chỉ cần add thẳng, không tự map lại.

struct AppOrderSummaryDto: Decodable, Identifiable {
    let id: String
    let code: String
    let customerName: String
    let address: String
    let note: String
    let total: Double
    let displayTime: String
    /// Đã có HoaDon nào (MaHoaDon = code, PhanLoai App) trong hệ thống chưa — đơn đã "bắt" rồi.
    let isImported: Bool
    /// Tên shipper (driver store) đã nhận đơn — nil nếu đơn chưa có ai nhận.
    let shipperName: String?
}

struct AppOrderChiTietToppingDto: Decodable {
    let id: String
    let ten: String
    let gia: Double
    let soLuong: Int
}

struct AppOrderChiTietDto: Decodable {
    let sanPhamBienTheId: String
    let tenSanPham: String
    let tenBienThe: String
    let donGia: Double
    let soLuong: Int
    let toppingDtos: [AppOrderChiTietToppingDto]?
}

struct AppOrderDetailDto: Decodable {
    let ghiChu: String?
    let chiTietHoaDons: [AppOrderChiTietDto]?
    /// Khách "<Tên> App" nội bộ đã khớp được driver store (MapShipperAsync, Backend) — nil nếu
    /// server chưa nhận diện được shipper. Thiếu field này khiến đơn bắt qua iOS trống shipper so
    /// với Desktop (vốn đọc thẳng cả HoaDonDto nên có sẵn).
    let khachHangId: String?
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
    let thuTu: Int
    let bienThe: [SanPhamBienTheDto]
    /// Chuỗi token đã chuẩn hoá sẵn từ server (SanPhamSearchHelper.BuildTimKiem: tên không dấu +
    /// tên liền không cách + viết tắt tự nhận diện ("ts") + VietTat tự đặt tay ("cfk"...), nối bằng
    /// ";"). Dùng để tìm món khớp Desktop (SanPhamMatchHelper.Search) thay vì so trực tiếp `ten`.
    let timKiem: String?
    /// Ảnh menu cho AppDatHangIOS (app khách đặt hàng) — nil nếu chưa có ảnh khớp/upload.
    let hinhAnh: String?
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
