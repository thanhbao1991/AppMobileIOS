import SwiftUI

/// Thống kê theo ngày — port từ TraSuaApp.Desktop/Controls/ThongKeTabControl (nguồn CHÍNH XÁC đã
/// xác nhận đang chạy production, KHÔNG dùng TraSuaApp.Mobile/Pages/ThongKe.cshtml vì trang đó
/// không còn liên kết từ navbar web, khả năng lỗi thời). Gọi 7 endpoint /api/ThongKe song song
/// theo 1 ngày cụ thể (Desktop cũng chỉ lọc theo NGÀY, không có khoảng ngày/tháng riêng — "tháng"
/// trong 2 field ChiTieuThang/DanhSachChiTieuThang là do BillThang=true, không phải filter khác).
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

    /// Tiền mặt tại quán trừ chi tiêu ngày — số tiền mặt lẽ ra còn trong ngăn kéo. Port y hệt cách
    /// Desktop tự cộng dồn 2 API (không phải field riêng từ server).
    private var kiemTien: Double? {
        guard let tm = thanhToan?.danhSachTienMat.first?.soTien, let chi = chiTieu?.chiTieuNgay else { return nil }
        return tm - chi
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayDateBar(date: $currentDate) { Task { await load() } }

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            if let doanhThu {
                                StatCard(icon: "chart.line.uptrend.xyaxis", title: "Doanh thu", value: doanhThu.tongDoanhThu, color: .brandPrimary, isExpanded: expandedCards.contains(.doanhThu)) {
                                    toggle(.doanhThu)
                                } content: {
                                    ForEach(doanhThu.danhSach) { item in
                                        AmountRow(label: item.ten, value: item.doanhThu)
                                    }
                                }
                            }
                            if let thanhToan {
                                StatCard(icon: "creditcard", title: "Thanh toán trong ngày", value: thanhToan.tongTienMat + thanhToan.tongChuyenKhoan, color: .brandPrimary, isExpanded: expandedCards.contains(.thanhToan)) {
                                    toggle(.thanhToan)
                                } content: {
                                    ForEach(thanhToan.danhSachTienMat) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                    }
                                    AmountRow(label: "Tổng chuyển khoản", value: thanhToan.tongChuyenKhoan)
                                    if let kiemTien {
                                        AmountRow(label: "Kiểm tiền (Nhã - Chi tiêu ngày)", value: kiemTien, color: .dangerColor)
                                    }
                                }
                            }
                            if let chiTieu {
                                StatCard(icon: "banknote", title: "Chi tiêu", value: chiTieu.chiTieuNgay + chiTieu.chiTieuThang, color: .warningColor, isExpanded: expandedCards.contains(.chiTieu)) {
                                    toggle(.chiTieu)
                                } content: {
                                    if chiTieu.danhSachChiTieuNgay.isEmpty && chiTieu.danhSachChiTieuThang.isEmpty {
                                        Text("Không có chi tiêu").foregroundColor(.textMuted).font(.footnote)
                                    } else {
                                        ForEach(chiTieu.danhSachChiTieuNgay) { item in
                                            AmountRow(label: item.ten, value: item.soTien)
                                        }
                                        ForEach(chiTieu.danhSachChiTieuThang) { item in
                                            AmountRow(label: item.ten, sub: "Bill tháng", value: item.soTien)
                                        }
                                    }
                                }
                            }
                            if let congNo {
                                StatCard(icon: "exclamationmark.circle", title: "Công nợ mới", value: congNo.tongCongNoNgay, color: .dangerColor, isExpanded: expandedCards.contains(.congNo)) {
                                    toggle(.congNo)
                                } content: {
                                    if congNo.danhSachCongNoNgay.isEmpty {
                                        Text("Không có công nợ mới").foregroundColor(.textMuted).font(.footnote)
                                    } else {
                                        ForEach(congNo.danhSachCongNoNgay) { item in
                                            AmountRow(label: item.tenKhachHang, sub: HoaDonFormatting.time(item.ngayGio), value: item.soTienNo)
                                        }
                                    }
                                }
                            }
                            if let traNo {
                                StatCard(icon: "checkmark.circle", title: "Trả nợ trong ngày", value: traNo.tongTraNoTaiQuan + traNo.tongTraNoShipper, color: .successColor, isExpanded: expandedCards.contains(.traNo)) {
                                    toggle(.traNo)
                                } content: {
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
                                }
                            }
                            if let chuaThanhToan {
                                StatCard(icon: "clock", title: "Đơn chưa thanh toán", value: chuaThanhToan.tongChuaThanhToan, color: .warningColor, isExpanded: expandedCards.contains(.chuaThanhToan)) {
                                    toggle(.chuaThanhToan)
                                } content: {
                                    if chuaThanhToan.danhSach.isEmpty {
                                        Text("Không có đơn treo").foregroundColor(.textMuted).font(.footnote)
                                    } else {
                                        ForEach(chuaThanhToan.danhSach) { item in
                                            AmountRow(label: item.tenKhachHang, value: item.soTien)
                                        }
                                    }
                                }
                            }
                            if let tongNo {
                                StatCard(icon: "chart.bar", title: "Tổng công nợ luỹ kế", value: tongNo.tongConLai, color: .dangerColor, isExpanded: expandedCards.contains(.tongNo)) {
                                    toggle(.tongNo)
                                } content: {
                                    ForEach(tongNo.danhSach) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.tongConLai)
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

        (chiTieu, congNo, thanhToan, doanhThu, traNo, chuaThanhToan, tongNo) = await (a, b, c, d, e, f, g)
        loading = false
        hasLoaded = true
    }
}

private enum ThongKeCard: Hashable {
    case doanhThu, thanhToan, chiTieu, congNo, traNo, chuaThanhToan, tongNo
}

/// Card tổng quan mỗi mục — cùng phong cách bo góc 14 + nền màu nhạt như HoaDonRowView/nút "+" của
/// tab Hoá đơn. Chạm vào header để mở rộng NGAY TẠI CHỖ (accordion) xem danh sách chi tiết, không
/// mở sheet riêng — chevron xoay theo trạng thái để báo hiệu có thể mở rộng.
private struct StatCard<Content: View>: View {
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
