import SwiftUI

/// Thống kê theo ngày — port từ TraSuaApp.Desktop/Controls/ThongKeTabControl (nguồn CHÍNH XÁC đã
/// xác nhận đang chạy production, KHÔNG dùng TraSuaApp.Mobile/Pages/ThongKe.cshtml vì trang đó
/// không còn liên kết từ navbar web, khả năng lỗi thời). Gọi 7 endpoint /api/ThongKe song song
/// theo 1 ngày cụ thể (Desktop cũng chỉ lọc theo NGÀY, không có khoảng ngày/tháng riêng — "tháng"
/// trong 2 field ChiTieuThang/DanhSachChiTieuThang là do BillThang=true, không phải filter khác).
/// Thứ tự card, tên card, tên mục con và màu đều khớp Y HỆT thứ tự WrapPanel + màu AddRow() bên
/// ThongKeTabControl.xaml(.cs) (Desktop) — không tự sáng tác lại.
/// Hiển thị dạng danh sách card — chạm vào 1 card để mở rộng NGAY TẠI CHỖ xem chi tiết (accordion),
/// không dùng sheet — nhiều card có thể mở cùng lúc để dễ so sánh.
struct ThongKeView: View {
    @State private var currentDate = Date()
    @State private var chiTieu: ThongKeChiTieuDto?
    @State private var congNo: ThongKeCongNoDto?
    @State private var thanhToan: ThongKeThanhToanDto?
    @State private var doanhThu: ThongKeDoanhThuNgayDto?
    @State private var traNo: ThongKeTraNoNgayDto?
    @State private var chuaThanhToan: ThongKeDonChuaThanhToanDto?
    @State private var tongNo: TongNoDto?
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var expandedCards: Set<ThongKeCard> = []
    @State private var selectedNoKhachHang: TongNoItemDto?
    @State private var selectedChiTieuTen: String?
    @State private var selectedThanhToanTen: String?
    @State private var selectedDoanhThuTen: String?
    @State private var selectedHoaDonId: String?
    @State private var selectedTraNoKhach: TraNoKhachSelection?
    /// Dữ liệu thô đúng NGÀY đang xem — dùng để lọc theo `ten` khi bấm vào 1 dòng trong card Chi tiêu
    /// mở ChiTieuThangDetailSheet (API chi-tieu-by-day trả cả 2 nhóm ngày/tháng cùng lúc, khớp cách
    /// GetThongKeChiTieuAsync ở Backend cộng dồn theo cùng khoảng NgayGio).
    @State private var chiTieuDayItems: [ChiTieuHangNgayDto] = []

    /// Tiền mặt tại quán trừ chi tiêu ngày — số tiền mặt lẽ ra còn trong ngăn kéo. Port y hệt cách
    /// Desktop tự cộng dồn 2 API (không phải field riêng từ server).
    private var kiemTien: Double? {
        guard let tm = thanhToan?.danhSachTienMat.first?.soTien, let chi = chiTieu?.chiTieuNgay else { return nil }
        return tm - chi
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayDateBar(
                    date: $currentDate,
                    trailing: AnyView(
                        NavigationLink {
                            ThongKeThangView()
                        } label: {
                            HStack(spacing: 4) {
                                Text("Thống kê tháng")
                                Image(systemName: "chevron.right")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.brandPrimary)
                        }
                    )
                ) { Task { await load() } }

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            // Thứ tự Y HỆT WrapPanel Desktop: Thanh toán, Doanh thu, Công nợ,
                            // Khách trả nợ, Chi tiêu, Chưa thanh toán, Tổng nợ.
                            if let thanhToan {
                                StatCard(icon: "creditcard", title: "Thanh toán", value: thanhToan.tongTienMat + thanhToan.tongChuyenKhoan, color: .thongKeBlue, isExpanded: expandedCards.contains(.thanhToan)) {
                                    toggle(.thanhToan)
                                } content: {
                                    ForEach(thanhToan.danhSachTienMat) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedThanhToanTen = item.ten }
                                    }
                                    if thanhToan.tongChuyenKhoan > 0 {
                                        AmountRow(label: "Chuyển khoản", value: thanhToan.tongChuyenKhoan)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedThanhToanTen = "Chuyển khoản" }
                                    }
                                    if let kiemTien {
                                        AmountRow(label: "Kiểm tiền", value: kiemTien, color: .thongKeBlue)
                                    }
                                }
                            }
                            if let doanhThu {
                                StatCard(icon: "chart.line.uptrend.xyaxis", title: "Doanh thu", value: doanhThu.tongDoanhThu, color: .thongKeGreen, isExpanded: expandedCards.contains(.doanhThu)) {
                                    toggle(.doanhThu)
                                } content: {
                                    ForEach(doanhThu.danhSach) { item in
                                        AmountRow(label: item.ten, value: item.doanhThu)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedDoanhThuTen = item.ten }
                                    }
                                }
                            }
                            if let congNo {
                                StatCard(icon: "exclamationmark.circle", title: "Công nợ", value: congNo.tongCongNoNgay, color: .thongKeBrown, isExpanded: expandedCards.contains(.congNo)) {
                                    toggle(.congNo)
                                } content: {
                                    ForEach(congNo.danhSachCongNoNgay) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.soTienNo)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                if let hoaDonId = item.hoaDonId { selectedHoaDonId = hoaDonId }
                                            }
                                    }
                                }
                            }
                            if let traNo {
                                StatCard(icon: "checkmark.circle", title: "Khách trả nợ", value: traNo.tongTraNoTaiQuan + traNo.tongTraNoShipper, color: .thongKePurple, isExpanded: expandedCards.contains(.traNo)) {
                                    toggle(.traNo)
                                } content: {
                                    SubTotalRow(label: "Trả nợ tại quán", value: traNo.tongTraNoTaiQuan, color: .thongKePurple)
                                    ForEach(traNo.traNoTaiQuan) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.soTien)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedTraNoKhach = TraNoKhachSelection(ten: item.tenKhachHang, isShipper: false) }
                                    }
                                    SubTotalRow(label: "Trả nợ shipper", value: traNo.tongTraNoShipper, color: .thongKePurple)
                                    ForEach(traNo.traNoShipper) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.soTien)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedTraNoKhach = TraNoKhachSelection(ten: item.tenKhachHang, isShipper: true) }
                                    }
                                }
                            }
                            if let chiTieu {
                                StatCard(icon: "banknote", title: "Chi tiêu", value: chiTieu.chiTieuNgay + chiTieu.chiTieuThang, color: .thongKeRed, isExpanded: expandedCards.contains(.chiTieu)) {
                                    toggle(.chiTieu)
                                } content: {
                                    SubTotalRow(label: "Chi tiêu ngày", value: chiTieu.chiTieuNgay, color: .thongKeRed)
                                    ForEach(chiTieu.danhSachChiTieuNgay) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedChiTieuTen = item.ten }
                                    }
                                    SubTotalRow(label: "Chi tiêu tháng", value: chiTieu.chiTieuThang, color: .thongKeRed)
                                    ForEach(chiTieu.danhSachChiTieuThang) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedChiTieuTen = item.ten }
                                    }
                                }
                            }
                            if let chuaThanhToan {
                                StatCard(icon: "clock", title: "Chưa thanh toán", value: chuaThanhToan.tongChuaThanhToan, color: .thongKeTeal, isExpanded: expandedCards.contains(.chuaThanhToan)) {
                                    toggle(.chuaThanhToan)
                                } content: {
                                    ForEach(chuaThanhToan.danhSach) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.soTien)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                if let hoaDonId = item.hoaDonId { selectedHoaDonId = hoaDonId }
                                            }
                                    }
                                }
                            }
                            if let tongNo {
                                StatCard(icon: "chart.bar", title: "Tổng nợ", value: tongNo.tongConLai, color: .thongKeOrange, isExpanded: expandedCards.contains(.tongNo)) {
                                    toggle(.tongNo)
                                } content: {
                                    ForEach(tongNo.danhSach) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.tongConLai)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedNoKhachHang = item }
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedNoKhachHang) { item in
            KhachHangNoDetailSheet(khachHangId: item.khachHangId, tenKhachHang: item.tenKhachHang)
        }
        .sheet(item: Binding(
            get: { selectedChiTieuTen.map { ChiTieuTenSelection(ten: $0) } },
            set: { selectedChiTieuTen = $0?.ten }
        )) { selection in
            ChiTieuThangDetailSheet(
                ten: selection.ten,
                items: chiTieuDayItems.filter { $0.ten == selection.ten }
            )
        }
        .sheet(item: Binding(
            get: { selectedThanhToanTen.map { ChiTieuTenSelection(ten: $0) } },
            set: { selectedThanhToanTen = $0?.ten }
        )) { selection in
            ThanhToanChiTietSheet(
                ten: selection.ten,
                currentDate: currentDate,
                ngayFilter: Calendar.current.component(.day, from: currentDate)
            )
        }
        .sheet(item: Binding(
            get: { selectedDoanhThuTen.map { ChiTieuTenSelection(ten: $0) } },
            set: { selectedDoanhThuTen = $0?.ten }
        )) { selection in
            DoanhThuChiTietSheet(
                ten: selection.ten,
                currentDate: currentDate,
                ngayFilter: Calendar.current.component(.day, from: currentDate)
            )
        }
        .sheet(item: Binding(
            get: { selectedHoaDonId.map { IdentifiableId($0) } },
            set: { selectedHoaDonId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {
                Task { await load() }
            }
        }
        .sheet(item: $selectedTraNoKhach) { selection in
            ThanhToanChiTietSheet(
                ten: selection.ten,
                currentDate: currentDate,
                ngayFilter: Calendar.current.component(.day, from: currentDate),
                traNoIsShipper: selection.isShipper
            )
        }
    }

    private func toggle(_ card: ThongKeCard) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCards.contains(card) {
                expandedCards.remove(card)
            } else {
                expandedCards.insert(card)
            }
        }
    }

    private func load() async {
        loading = true
        let cal = Calendar.current
        let ngay = cal.component(.day, from: currentDate)
        let thang = cal.component(.month, from: currentDate)
        let nam = cal.component(.year, from: currentDate)

        async let a = APIClient.shared.getThongKeChiTieu(ngay: ngay, thang: thang, nam: nam)
        async let b = APIClient.shared.getThongKeCongNo(ngay: ngay, thang: thang, nam: nam)
        async let c = APIClient.shared.getThongKeThanhToan(ngay: ngay, thang: thang, nam: nam)
        async let d = APIClient.shared.getThongKeDoanhThu(ngay: ngay, thang: thang, nam: nam)
        async let e = APIClient.shared.getThongKeTraNo(ngay: ngay, thang: thang, nam: nam)
        async let f = APIClient.shared.getThongKeDonChuaThanhToan(ngay: ngay, thang: thang, nam: nam)
        async let g = APIClient.shared.getTongNo()
        async let h = APIClient.shared.getChiTieuByDay(DateNavFormat.queryDate.string(from: currentDate))

        (chiTieu, congNo, thanhToan, doanhThu, traNo, chuaThanhToan, tongNo, chiTieuDayItems) = await (a, b, c, d, e, f, g, h)
        loading = false
        hasLoaded = true
    }
}

/// Định danh cho sheet(item:) khi bấm vào 1 khách trong card "Khách trả nợ" — cần cả `isShipper` vì
/// cùng 1 tên khách có thể xuất hiện độc lập ở cả 2 nhóm tại quán/shipper trong cùng ngày.
private struct TraNoKhachSelection: Identifiable {
    let ten: String
    let isShipper: Bool
    var id: String { ten + (isShipper ? "-ship" : "-taiquan") }
}

private enum ThongKeCard: Hashable {
    case thanhToan, doanhThu, congNo, traNo, chiTieu, chuaThanhToan, tongNo
}

/// Màu mỗi card lấy Y HỆT hex dùng trong AddRow() của ThongKeTabControl.xaml.cs (Desktop) — không
/// dùng warningColor (vàng) cho card nào, tránh Chi tiêu/Chưa thanh toán trùng màu "cảnh báo" gây
/// hiểu nhầm mức độ nghiêm trọng như nhau. Không đánh dấu private — ThongKeThangView tái dùng chung.
extension Color {
    static let thongKeBlue = Color(red: 0x0B / 255, green: 0x61 / 255, blue: 0xD6 / 255)
    static let thongKeGreen = Color(red: 0x0F / 255, green: 0x51 / 255, blue: 0x32 / 255)
    static let thongKeBrown = Color(red: 0x97 / 255, green: 0x4A / 255, blue: 0x05 / 255)
    static let thongKePurple = Color(red: 0x6D / 255, green: 0x28 / 255, blue: 0xD9 / 255)
    static let thongKeRed = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
    static let thongKeTeal = Color(red: 0x03 / 255, green: 0x69 / 255, blue: 0xA1 / 255)
    static let thongKeOrange = Color(red: 0xF9 / 255, green: 0x73 / 255, blue: 0x16 / 255)
}

/// Card tổng quan mỗi mục — cùng phong cách bo góc 14 + nền màu nhạt như HoaDonRowView/nút "+" của
/// tab Hoá đơn. Chạm vào header để mở rộng NGAY TẠI CHỖ (accordion) xem danh sách chi tiết, không
/// mở sheet riêng — chevron xoay theo trạng thái để báo hiệu có thể mở rộng. Không private —
/// ThongKeThangView tái dùng chung để giao diện khớp y hệt.
struct StatCard<Content: View>: View {
    let icon: String
    let title: String
    let value: Double
    var color: Color = .brandPrimary
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(color.opacity(0.15)).frame(width: 30, height: 30)
                        Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(HoaDonFormatting.money(value))
                        .font(.subheadline.bold())
                        .foregroundColor(color)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .foregroundColor(.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    Divider().padding(.horizontal, 12)
                    VStack(spacing: 4) {
                        content
                    }
                    .padding(12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Hàng tổng phụ (vd "Chi tiêu ngày"/"Chi tiêu tháng", "Trả nợ tại quán"/"Trả nợ shipper") — khớp
/// các dòng bold "CHI TIÊU NGÀY"/"TRẢ NỢ TẠI QUÁN"... trong AddRow() Desktop, đứng trước danh sách
/// item con của nhóm đó.
struct SubTotalRow: View {
    let label: String
    let value: Double
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label).font(.footnote.weight(.bold)).foregroundColor(.secondary)
            Spacer()
            Text(HoaDonFormatting.money(value))
                .font(.footnote.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.top, 4)
    }
}

struct AmountRow: View {
    let label: String
    var sub: String?
    let value: Double
    var color: Color = .primary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.medium))
                if let sub {
                    Text(sub).font(.caption).foregroundColor(.textMuted)
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(value))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
