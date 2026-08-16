import SwiftUI

/// Thống kê theo ngày — port từ TraSuaApp.Desktop/Controls/ThongKeTabControl (nguồn CHÍNH XÁC đã
/// xác nhận đang chạy production, KHÔNG dùng TraSuaApp.Mobile/Pages/ThongKe.cshtml vì trang đó
/// không còn liên kết từ navbar web, khả năng lỗi thời). Gọi 7 endpoint /api/ThongKe song song
/// theo 1 ngày cụ thể (Desktop cũng chỉ lọc theo NGÀY, không có khoảng ngày/tháng riêng — "tháng"
/// trong 2 field ChiTieuThang/DanhSachChiTieuThang là do BillThang=true, không phải filter khác).
/// Không có biểu đồ bên Desktop — giữ nguyên dạng danh sách tên + số tiền.
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

    /// Tiền mặt tại quán trừ chi tiêu ngày — số tiền mặt lẽ ra còn trong ngăn kéo. Port y hệt cách
    /// Desktop tự cộng dồn 2 API (không phải field riêng từ server).
    private var kiemTien: Double? {
        guard let tm = thanhToan?.danhSachTienMat.first?.soTien, let chi = chiTieu?.chiTieuNgay else { return nil }
        return tm - chi
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayNavBar(date: $currentDate) { Task { await load() } }

                if loading {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        if let doanhThu {
                            Section {
                                ForEach(doanhThu.danhSach) { item in
                                    AmountRow(label: item.ten, value: item.doanhThu)
                                }
                            } header: {
                                TotalHeader(title: "Doanh thu", value: doanhThu.tongDoanhThu)
                            }
                        }

                        if let thanhToan {
                            Section {
                                ForEach(thanhToan.danhSachTienMat) { item in
                                    AmountRow(label: item.ten, value: item.soTien)
                                }
                                if let kiemTien {
                                    AmountRow(label: "Kiểm tiền (mặt − chi tiêu ngày)", value: kiemTien, emphasize: true)
                                }
                                AmountRow(label: "Tổng chuyển khoản", value: thanhToan.tongChuyenKhoan, emphasize: true)
                            } header: {
                                TotalHeader(title: "Thanh toán trong ngày", value: thanhToan.tongTienMat + thanhToan.tongChuyenKhoan)
                            }
                        }

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
                                TotalHeader(title: "Chi tiêu ngày", value: chiTieu.chiTieuNgay)
                            }
                            if !chiTieu.danhSachChiTieuThang.isEmpty {
                                Section {
                                    ForEach(chiTieu.danhSachChiTieuThang) { item in
                                        AmountRow(label: item.ten, value: item.soTien)
                                    }
                                } header: {
                                    TotalHeader(title: "Chi tiêu bill tháng", value: chiTieu.chiTieuThang)
                                }
                            }
                        }

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
                                TotalHeader(title: "Công nợ mới trong ngày", value: congNo.tongCongNoNgay, color: .dangerColor)
                            }
                        }

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
                                TotalHeader(title: "Trả nợ trong ngày", value: traNo.tongTraNoTaiQuan + traNo.tongTraNoShipper, color: .successColor)
                            }
                        }

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
                                TotalHeader(title: "Đơn chưa thanh toán", value: chuaThanhToan.tongChuaThanhToan, color: .warningColor)
                            }
                        }

                        if let tongNo {
                            Section {
                                ForEach(tongNo.danhSach) { item in
                                    AmountRow(label: item.tenKhachHang, value: item.tongConLai)
                                }
                            } header: {
                                TotalHeader(title: "Tổng công nợ luỹ kế (mọi thời điểm)", value: tongNo.tongConLai, color: .dangerColor)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Thống kê")
            .navigationBarTitleDisplayMode(.inline)
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
    }
}

private struct TotalHeader: View {
    let title: String
    let value: Double
    var color: Color = .brandPrimary

    var body: some View {
        HStack {
            Text(title).textCase(nil)
            Spacer()
            Text(HoaDonFormatting.money(value)).font(.footnote.bold()).foregroundColor(color)
        }
    }
}

private struct AmountRow: View {
    let label: String
    var sub: String?
    let value: Double
    var emphasize: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                if let sub {
                    Text(sub).font(.caption).foregroundColor(.textMuted)
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(value))
                .font(.subheadline)
                .fontWeight(emphasize ? .bold : .regular)
                .foregroundColor(emphasize ? .brandPrimary : .primary)
        }
    }
}
