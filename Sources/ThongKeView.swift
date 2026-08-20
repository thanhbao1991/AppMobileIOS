import SwiftUI

/// Thống kê theo ngày — port từ TraSuaApp.Desktop/Controls/ThongKeTabControl (nguồn CHÍNH XÁC đã
/// xác nhận đang chạy production, KHÔNG dùng TraSuaApp.Mobile/Pages/ThongKe.cshtml vì trang đó
/// không còn liên kết từ navbar web, khả năng lỗi thời). Gọi 7 endpoint /api/ThongKe song song
/// theo 1 ngày cụ thể (Desktop cũng chỉ lọc theo NGÀY, không có khoảng ngày/tháng riêng — "tháng"
/// trong 2 field ChiTieuThang/DanhSachChiTieuThang là do BillThang=true, không phải filter khác).
/// Hiển thị dạng lưới card (chạm vào mới xem chi tiết danh sách) — thay bản cũ liệt kê hết 1 lần.
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
    @State private var selectedCard: ThongKeCard?

    /// Tiền mặt tại quán trừ chi tiêu ngày — số tiền mặt lẽ ra còn trong ngăn kéo. Port y hệt cách
    /// Desktop tự cộng dồn 2 API (không phải field riêng từ server).
    private var kiemTien: Double? {
        guard let tm = thanhToan?.danhSachTienMat.first?.soTien, let chi = chiTieu?.chiTieuNgay else { return nil }
        return tm - chi
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayDateBar(date: $currentDate) { Task { await load() } }

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            if let doanhThu {
                                StatCard(icon: "chart.line.uptrend.xyaxis", title: "Doanh thu", value: doanhThu.tongDoanhThu, color: .brandPrimary) { selectedCard = .doanhThu }
                            }
                            if let thanhToan {
                                StatCard(icon: "creditcard", title: "Thanh toán trong ngày", value: thanhToan.tongTienMat + thanhToan.tongChuyenKhoan, color: .brandPrimary) { selectedCard = .thanhToan }
                            }
                            if let chiTieu {
                                StatCard(icon: "banknote", title: "Chi tiêu", value: chiTieu.chiTieuNgay + chiTieu.chiTieuThang, color: .warningColor) { selectedCard = .chiTieu }
                            }
                            if let congNo {
                                StatCard(icon: "exclamationmark.circle", title: "Công nợ mới", value: congNo.tongCongNoNgay, color: .dangerColor) { selectedCard = .congNo }
                            }
                            if let traNo {
                                StatCard(icon: "checkmark.circle", title: "Trả nợ trong ngày", value: traNo.tongTraNoTaiQuan + traNo.tongTraNoShipper, color: .successColor) { selectedCard = .traNo }
                            }
                            if let chuaThanhToan {
                                StatCard(icon: "clock", title: "Đơn chưa thanh toán", value: chuaThanhToan.tongChuaThanhToan, color: .warningColor) { selectedCard = .chuaThanhToan }
                            }
                            if let tongNo {
                                StatCard(icon: "chart.bar", title: "Tổng công nợ luỹ kế", value: tongNo.tongConLai, color: .dangerColor) { selectedCard = .tongNo }
                            }
                        }
                        .padding(12)
                    }
                    .refreshable { await load() }
                }
            }
        }
        .sheet(item: $selectedCard) { card in
            ThongKeDetailSheet(
                card: card, chiTieu: chiTieu, congNo: congNo, thanhToan: thanhToan,
                doanhThu: doanhThu, traNo: traNo, chuaThanhToan: chuaThanhToan, tongNo: tongNo,
                kiemTien: kiemTien
            )
        }
        .task { await load() }
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

        (chiTieu, congNo, thanhToan, doanhThu, traNo, chuaThanhToan, tongNo) = await (a, b, c, d, e, f, g)
        loading = false
        hasLoaded = true
    }
}

private enum ThongKeCard: String, Identifiable {
    case doanhThu, thanhToan, chiTieu, congNo, traNo, chuaThanhToan, tongNo
    var id: String { rawValue }
}

/// Card tổng quan mỗi mục — cùng phong cách bo góc 14 + nền màu nhạt như HoaDonRowView/nút "+" của
/// tab Hoá đơn, chạm vào mới mở sheet xem chi tiết (thay vì liệt kê hết ngay trên màn hình chính).
private struct StatCard: View {
    let icon: String
    let title: String
    let value: Double
    var color: Color = .brandPrimary
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(color)
                }
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(HoaDonFormatting.money(value))
                    .font(.subheadline.bold())
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ThongKeDetailSheet: View {
    let card: ThongKeCard
    let chiTieu: ThongKeChiTieuDto?
    let congNo: ThongKeCongNoDto?
    let thanhToan: ThongKeThanhToanDto?
    let doanhThu: ThongKeDoanhThuNgayDto?
    let traNo: ThongKeTraNoNgayDto?
    let chuaThanhToan: ThongKeDonChuaThanhToanDto?
    let tongNo: TongNoDto?
    let kiemTien: Double?

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch card {
        case .doanhThu: return "Doanh thu"
        case .thanhToan: return "Thanh toán trong ngày"
        case .chiTieu: return "Chi tiêu"
        case .congNo: return "Công nợ mới trong ngày"
        case .traNo: return "Trả nợ trong ngày"
        case .chuaThanhToan: return "Đơn chưa thanh toán"
        case .tongNo: return "Tổng công nợ luỹ kế (mọi thời điểm)"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                switch card {
                case .doanhThu:
                    if let doanhThu {
                        Section {
                            ForEach(doanhThu.danhSach) { item in
                                AmountRow(label: item.ten, value: item.doanhThu)
                            }
                        } header: {
                            TotalHeader(icon: "chart.line.uptrend.xyaxis", title: "Tổng doanh thu", value: doanhThu.tongDoanhThu)
                        }
                    }
                case .thanhToan:
                    if let thanhToan {
                        Section {
                            ForEach(thanhToan.danhSachTienMat) { item in
                                AmountRow(label: item.ten, value: item.soTien)
                            }
                            AmountRow(label: "Tổng chuyển khoản", value: thanhToan.tongChuyenKhoan)
                            if let kiemTien {
                                AmountRow(label: "Kiểm tiền (Nhã - Chi tiêu ngày)", value: kiemTien, color: .dangerColor)
                            }
                        } header: {
                            TotalHeader(icon: "creditcard", title: "Tổng thanh toán", value: thanhToan.tongTienMat + thanhToan.tongChuyenKhoan)
                        }
                    }
                case .chiTieu:
                    if let chiTieu {
                        Section {
                            if chiTieu.danhSachChiTieuNgay.isEmpty {
                                Text("Không có chi tiêu ngày").foregroundColor(.textMuted).font(.footnote)
                            } else {
                                ForEach(chiTieu.danhSachChiTieuNgay) { item in
                                    AmountRow(label: item.ten, value: item.soTien)
                                }
                            }
                        } header: {
                            TotalHeader(icon: "banknote", title: "Chi tiêu ngày", value: chiTieu.chiTieuNgay, color: .warningColor)
                        }
                        if !chiTieu.danhSachChiTieuThang.isEmpty {
                            Section {
                                ForEach(chiTieu.danhSachChiTieuThang) { item in
                                    AmountRow(label: item.ten, value: item.soTien)
                                }
                            } header: {
                                TotalHeader(icon: "banknote", title: "Chi tiêu bill tháng", value: chiTieu.chiTieuThang, color: .warningColor)
                            }
                        }
                    }
                case .congNo:
                    if let congNo {
                        Section {
                            if congNo.danhSachCongNoNgay.isEmpty {
                                Text("Không có công nợ mới").foregroundColor(.textMuted).font(.footnote)
                            } else {
                                ForEach(congNo.danhSachCongNoNgay) { item in
                                    AmountRow(label: item.tenKhachHang, sub: HoaDonFormatting.time(item.ngayGio), value: item.soTienNo)
                                }
                            }
                        } header: {
                            TotalHeader(icon: "exclamationmark.circle", title: "Tổng công nợ mới", value: congNo.tongCongNoNgay, color: .dangerColor)
                        }
                    }
                case .traNo:
                    if let traNo {
                        Section {
                            if traNo.traNoTaiQuan.isEmpty && traNo.traNoShipper.isEmpty {
                                Text("Không có khách trả nợ").foregroundColor(.textMuted).font(.footnote)
                            } else {
                                ForEach(traNo.traNoTaiQuan) { item in
                                    AmountRow(label: item.tenKhachHang, sub: "Tại quán", value: item.soTien)
                                }
                                ForEach(traNo.traNoShipper) { item in
                                    AmountRow(label: item.tenKhachHang, sub: "Qua shipper", value: item.soTien)
                                }
                            }
                        } header: {
                            TotalHeader(icon: "checkmark.circle", title: "Tổng trả nợ", value: traNo.tongTraNoTaiQuan + traNo.tongTraNoShipper, color: .successColor)
                        }
                    }
                case .chuaThanhToan:
                    if let chuaThanhToan {
                        Section {
                            if chuaThanhToan.danhSach.isEmpty {
                                Text("Không có đơn treo").foregroundColor(.textMuted).font(.footnote)
                            } else {
                                ForEach(chuaThanhToan.danhSach) { item in
                                    AmountRow(label: item.tenKhachHang, value: item.soTien)
                                }
                            }
                        } header: {
                            TotalHeader(icon: "clock", title: "Tổng chưa thanh toán", value: chuaThanhToan.tongChuaThanhToan, color: .warningColor)
                        }
                    }
                case .tongNo:
                    if let tongNo {
                        Section {
                            ForEach(tongNo.danhSach) { item in
                                AmountRow(label: item.tenKhachHang, value: item.tongConLai)
                            }
                        } header: {
                            TotalHeader(icon: "chart.bar", title: "Tổng công nợ luỹ kế", value: tongNo.tongConLai, color: .dangerColor)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Header mỗi section: icon trong badge tròn màu nhạt + tên mục + tổng tiền nổi bật.
private struct TotalHeader: View {
    let icon: String
    let title: String
    let value: Double
    var color: Color = .brandPrimary

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 26, height: 26)
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
            }
            Text(title).textCase(nil).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
            Spacer()
            Text(HoaDonFormatting.money(value))
                .font(.subheadline.weight(.bold))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

private struct AmountRow: View {
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
