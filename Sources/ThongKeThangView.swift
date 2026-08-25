import SwiftUI

/// Thống kê theo THÁNG — giống hệt bố cục/màu/thứ tự card của ThongKeView (theo ngày), chỉ khác dữ
/// liệu lấy theo cả tháng đang xem (có thể đổi tháng qua MonthDateBar). Gọi 5 endpoint /api/ThongKe
/// *-thang song song (thêm GetTongNo dùng chung, vốn đã là số toàn cục không lọc theo kỳ). StatCard/
/// AmountRow/SubTotalRow/màu thongKe* tái dùng nguyên từ ThongKeView.swift (đã bỏ `private` ở đó).
/// Không có card "Công nợ" (khác bản ngày) — số đó chỉ là tập con của "Tổng nợ hiện tại" trong tháng
/// hiện tại, và với tháng đã qua thì tụt về gần 0 khi nợ đã trả hết, gây hiểu nhầm "tháng đó không nợ".
/// Không có dòng "Kiểm tiền" trong card Thanh toán — kiểm tiền là thao tác đối chiếu ngăn kéo cuối
/// NGÀY, cộng dồn cả tháng thành 1 số không còn ý nghĩa vật lý (không có số dư đầu kỳ).
struct ThongKeThangView: View {
    @State private var currentDate = Date()
    @State private var chiTieu: ThongKeChiTieuDto?
    @State private var thanhToan: ThongKeThanhToanDto?
    @State private var doanhThu: ThongKeDoanhThuNgayDto?
    @State private var traNo: ThongKeTraNoNgayDto?
    @State private var chuaThanhToan: ThongKeDonChuaThanhToanDto?
    @State private var tongNo: TongNoDto?
    @State private var hasLoaded = false
    @State private var expandedCards: Set<ThongKeThangCard> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonthDateBar(date: $currentDate) { Task { await load() } }

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            if let thanhToan {
                                StatCard(icon: "creditcard", title: "Thanh toán", value: thanhToan.tongTienMat + thanhToan.tongChuyenKhoan, color: .thongKeBlue, isExpanded: expandedCards.contains(.thanhToan)) {
                                    toggle(.thanhToan)
                                } content: {
                                    ForEach(thanhToan.danhSachTienMat) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                    }
                                    if thanhToan.tongChuyenKhoan > 0 {
                                        AmountRow(label: "Chuyển khoản", value: thanhToan.tongChuyenKhoan)
                                    }
                                }
                            }
                            if let doanhThu {
                                StatCard(icon: "chart.line.uptrend.xyaxis", title: "Doanh thu", value: doanhThu.tongDoanhThu, color: .thongKeGreen, isExpanded: expandedCards.contains(.doanhThu)) {
                                    toggle(.doanhThu)
                                } content: {
                                    ForEach(doanhThu.danhSach) { item in
                                        AmountRow(label: item.ten, value: item.doanhThu)
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
                                    }
                                    SubTotalRow(label: "Trả nợ shipper", value: traNo.tongTraNoShipper, color: .thongKePurple)
                                    ForEach(traNo.traNoShipper) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.soTien)
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
                                    }
                                    SubTotalRow(label: "Chi tiêu tháng", value: chiTieu.chiTieuThang, color: .thongKeRed)
                                    ForEach(chiTieu.danhSachChiTieuThang) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                    }
                                }
                            }
                            if let chuaThanhToan {
                                StatCard(icon: "clock", title: "Chưa thanh toán", value: chuaThanhToan.tongChuaThanhToan, color: .thongKeTeal, isExpanded: expandedCards.contains(.chuaThanhToan)) {
                                    toggle(.chuaThanhToan)
                                } content: {
                                    ForEach(chuaThanhToan.danhSach) { item in
                                        AmountRow(label: item.tenKhachHang, value: item.soTien)
                                    }
                                }
                            }
                            if let tongNo {
                                StatCard(icon: "chart.bar", title: "Tổng nợ hiện tại", value: tongNo.tongConLai, color: .thongKeOrange, isExpanded: expandedCards.contains(.tongNo)) {
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
            .navigationTitle("Thống kê tháng")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func toggle(_ card: ThongKeThangCard) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedCards.contains(card) {
                expandedCards.remove(card)
            } else {
                expandedCards.insert(card)
            }
        }
    }

    private func load() async {
        let cal = Calendar.current
        let thang = cal.component(.month, from: currentDate)
        let nam = cal.component(.year, from: currentDate)

        async let a = APIClient.shared.getThongKeChiTieuThang(thang: thang, nam: nam)
        async let c = APIClient.shared.getThongKeThanhToanThang(thang: thang, nam: nam)
        async let d = APIClient.shared.getThongKeDoanhThuThang(thang: thang, nam: nam)
        async let e = APIClient.shared.getThongKeTraNoThang(thang: thang, nam: nam)
        async let f = APIClient.shared.getThongKeDonChuaThanhToanThang(thang: thang, nam: nam)
        async let g = APIClient.shared.getTongNo()

        (chiTieu, thanhToan, doanhThu, traNo, chuaThanhToan, tongNo) = await (a, c, d, e, f, g)
        hasLoaded = true
    }
}

private enum ThongKeThangCard: Hashable {
    case thanhToan, doanhThu, traNo, chiTieu, chuaThanhToan, tongNo
}
