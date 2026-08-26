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
    @State private var chuaThanhToan: ThongKeDonChuaThanhToanDto?
    @State private var tongNo: TongNoDto?
    @State private var chiTieuMonthItems: [ChiTieuHangNgayDto] = []
    @State private var hasLoaded = false
    @State private var expandedCards: Set<ThongKeThangCard> = []
    @State private var selectedChiTieuTen: String?
    @State private var selectedHoaDonId: String?
    @State private var selectedNoKhachHang: TongNoItemDto?
    @State private var selectedThanhToanTen: String?
    @State private var selectedDoanhThuTen: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedThanhToanTen = item.ten }
                                    }
                                    if thanhToan.tongChuyenKhoan > 0 {
                                        AmountRow(label: "Chuyển khoản", value: thanhToan.tongChuyenKhoan)
                                            .contentShape(Rectangle())
                                            .onTapGesture { selectedThanhToanTen = "Chuyển khoản" }
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
                            if let chiTieu {
                                StatCard(icon: "banknote", title: "Chi tiêu", value: chiTieu.chiTieuNgay + chiTieu.chiTieuThang, color: .thongKeRed, isExpanded: expandedCards.contains(.chiTieu)) {
                                    toggle(.chiTieu)
                                } content: {
                                    ForEach(mergedChiTieu(chiTieu)) { item in
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
                                StatCard(icon: "chart.bar", title: "Tổng nợ hiện tại", value: tongNo.tongConLai, color: .thongKeOrange, isExpanded: expandedCards.contains(.tongNo)) {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MonthDateBar(date: $currentDate) { Task { await load() } }
                }
            }
        }
        .task { await load() }
        .sheet(item: Binding(
            get: { selectedChiTieuTen.map { ChiTieuTenSelection(ten: $0) } },
            set: { selectedChiTieuTen = $0?.ten }
        )) { selection in
            ChiTieuThangDetailSheet(
                ten: selection.ten,
                items: chiTieuMonthItems.filter { $0.ten == selection.ten }
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
        .sheet(item: $selectedNoKhachHang) { item in
            KhachHangNoDetailSheet(khachHangId: item.khachHangId, tenKhachHang: item.tenKhachHang)
        }
        .sheet(item: Binding(
            get: { selectedThanhToanTen.map { ChiTieuTenSelection(ten: $0) } },
            set: { selectedThanhToanTen = $0?.ten }
        )) { selection in
            ThanhToanChiTietSheet(ten: selection.ten, currentDate: currentDate)
        }
        .sheet(item: Binding(
            get: { selectedDoanhThuTen.map { ChiTieuTenSelection(ten: $0) } },
            set: { selectedDoanhThuTen = $0?.ten }
        )) { selection in
            DoanhThuChiTietSheet(ten: selection.ten, currentDate: currentDate)
        }
    }

    private func mergedChiTieu(_ chiTieu: ThongKeChiTieuDto) -> [NamedAmountDto] {
        let all = chiTieu.danhSachChiTieuNgay + chiTieu.danhSachChiTieuThang
        var totalByTen: [String: Double] = [:]
        var order: [String] = []
        for item in all {
            if totalByTen[item.ten] == nil { order.append(item.ten) }
            totalByTen[item.ten, default: 0] += item.soTien
        }
        return order
            .map { NamedAmountDto(ten: $0, soTien: totalByTen[$0]!) }
            .sorted { $0.soTien > $1.soTien }
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
        async let f = APIClient.shared.getThongKeDonChuaThanhToanThang(thang: thang, nam: nam)
        async let g = APIClient.shared.getTongNo()
        async let h = APIClient.shared.getChiTieuByMonth(year: nam, month: thang)

        (chiTieu, thanhToan, doanhThu, chuaThanhToan, tongNo, chiTieuMonthItems) = await (a, c, d, f, g, h)
        hasLoaded = true
    }
}

/// Không private — ThongKeView (bản ngày) tái dùng chung để bấm vào món chi tiêu/thanh toán/doanh
/// thu ra đúng sheet chi tiết này.
struct ChiTieuTenSelection: Identifiable {
    let ten: String
    var id: String { ten }
}

/// Không private — ThongKeView tái dùng, truyền items đã lọc theo ngày thay vì cả tháng.
struct ChiTieuThangDetailSheet: View {
    let ten: String
    let items: [ChiTieuHangNgayDto]

    @Environment(\.dismiss) private var dismiss

    /// Mới trước — khớp thứ tự dùng chung mọi list khác trong app (HoaDonListView, CongNoListView...).
    private var sorted: [ChiTieuHangNgayDto] {
        items.sorted { ($0.ngay ?? $0.ngayGio ?? "") > ($1.ngay ?? $1.ngayGio ?? "") }
    }

    private var total: Double { items.reduce(0) { $0 + $1.thanhTien } }

    private func dayLabel(_ item: ChiTieuHangNgayDto) -> String {
        guard let date = HoaDonFormatting.parseIso(item.ngay ?? item.ngayGio) else { return "?" }
        return DateNavFormat.dayTitle.string(from: date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Tổng cộng").foregroundColor(.textMuted)
                        Spacer()
                        Text(HoaDonFormatting.money(total)).font(.headline).monospacedDigit()
                    }
                }
                ForEach(sorted) { item in
                    HStack {
                        Text(dayLabel(item)).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(HoaDonFormatting.money(item.thanhTien))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(ten)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }
}

/// Chi tiết 1 khách trong card "Tổng nợ hiện tại"/"Tổng nợ" — TongNoItemDto chỉ có tổng cộng dồn,
/// không có hoaDonId (có thể gộp nhiều đơn), nên phải gọi lại /api/dashboard/cong-no-list rồi lọc
/// theo khachHangId (fallback so tên nếu khách lẻ không có id) để liệt kê từng đơn còn nợ. Không
/// private — ThongKeView (bản theo ngày) tái dùng chung để bấm vào khách trong card "Tổng nợ" ra
/// đúng layout này.
struct KhachHangNoDetailSheet: View {
    let khachHangId: String?
    let tenKhachHang: String

    @Environment(\.dismiss) private var dismiss
    @State private var items: [HoaDonListDto] = []
    @State private var hasLoaded = false
    @State private var selectedHoaDonId: String?

    private var filtered: [HoaDonListDto] {
        items.filter {
            if let khachHangId { return $0.khachHangId == khachHangId }
            return $0.tenKhachHangText == tenKhachHang
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        ForEach(filtered) { item in
                            CongNoRowView(item: item, onSelect: { selectedHoaDonId = item.id }, showName: false)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)

                    Divider()
                    CongNoFooterView(items: filtered, label: tenKhachHang, showName: false)
                }
            }
            .navigationTitle(tenKhachHang)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .task {
            items = await APIClient.shared.getCongNoList()
            hasLoaded = true
        }
        .sheet(item: Binding(
            get: { selectedHoaDonId.map { IdentifiableId($0) } },
            set: { selectedHoaDonId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {}
        }
    }
}

/// Không private — ThongKeView (bản ngày) tái dùng, `ngayFilter` lọc thêm về đúng 1 ngày (API chỉ có
/// bản theo tháng, không có bản theo ngày riêng). `traNoIsShipper` khác nil khi mở từ card "Khách trả
/// nợ" (`ten` khi đó là TÊN KHÁCH chứ không phải tên phương thức thanh toán) — gọi endpoint
/// tra-no-chi-tiet-thang thay vì thanh-toan-chi-tiet-thang.
struct ThanhToanChiTietSheet: View {
    let ten: String
    let currentDate: Date
    var ngayFilter: Int? = nil
    var traNoIsShipper: Bool? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var items: [ThanhToanChiTietItemDto] = []
    @State private var hasLoaded = false
    @State private var selectedHoaDonId: String?

    private var total: Double { items.reduce(0) { $0 + $1.soTien } }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Tổng cộng").foregroundColor(.textMuted)
                                Spacer()
                                Text(HoaDonFormatting.money(total)).font(.headline).monospacedDigit()
                            }
                        }
                        ForEach(items) { item in
                            Button {
                                selectedHoaDonId = item.hoaDonId
                            } label: {
                                HStack {
                                    Text(item.tenKhachHang)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(HoaDonFormatting.money(item.soTien))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(ten)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .task {
            let cal = Calendar.current
            var fetched: [ThanhToanChiTietItemDto]
            if let traNoIsShipper {
                fetched = await APIClient.shared.getTraNoChiTietThang(
                    thang: cal.component(.month, from: currentDate),
                    nam: cal.component(.year, from: currentDate),
                    ten: ten,
                    isShipper: traNoIsShipper
                )
            } else {
                fetched = await APIClient.shared.getThanhToanChiTietThang(
                    thang: cal.component(.month, from: currentDate),
                    nam: cal.component(.year, from: currentDate),
                    ten: ten
                )
            }
            if let ngayFilter {
                fetched = fetched.filter {
                    guard let date = HoaDonFormatting.parseIso($0.ngayGio) else { return false }
                    return cal.component(.day, from: date) == ngayFilter
                }
            }
            items = fetched
            hasLoaded = true
        }
        .sheet(item: Binding(
            get: { selectedHoaDonId.map { IdentifiableId($0) } },
            set: { selectedHoaDonId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {}
        }
    }
}

/// Không private — ThongKeView (bản ngày) tái dùng, `ngayFilter` lọc thêm về đúng 1 ngày (API chỉ có
/// bản theo tháng, không có bản theo ngày riêng).
struct DoanhThuChiTietSheet: View {
    let ten: String
    let currentDate: Date
    var ngayFilter: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var items: [HoaDonListDto] = []
    @State private var hasLoaded = false
    @State private var selectedHoaDonId: String?

    private var total: Double { items.reduce(0) { $0 + $1.thanhTien } }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Tổng cộng").foregroundColor(.textMuted)
                                Spacer()
                                Text(HoaDonFormatting.money(total)).font(.headline).monospacedDigit()
                            }
                        }
                        ForEach(items) { item in
                            Button {
                                selectedHoaDonId = item.id
                            } label: {
                                HStack {
                                    Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(HoaDonFormatting.money(item.thanhTien))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(ten)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
        .task {
            let cal = Calendar.current
            var fetched = await APIClient.shared.getDoanhThuChiTietThang(
                thang: cal.component(.month, from: currentDate),
                nam: cal.component(.year, from: currentDate),
                ten: ten
            )
            if let ngayFilter {
                fetched = fetched.filter {
                    guard let date = HoaDonFormatting.parseIso($0.ngayGio) else { return false }
                    return cal.component(.day, from: date) == ngayFilter
                }
            }
            items = fetched
            hasLoaded = true
        }
        .sheet(item: Binding(
            get: { selectedHoaDonId.map { IdentifiableId($0) } },
            set: { selectedHoaDonId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {}
        }
    }
}

private enum ThongKeThangCard: Hashable {
    case thanhToan, doanhThu, chiTieu, chuaThanhToan, tongNo
}
