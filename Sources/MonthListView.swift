import SwiftUI

/// Khung dùng chung cho 7 trang báo cáo theo tháng (Đơn Tại chỗ/Mua về/Ship/Mua hộ/App, Chi tiết
/// tháng, Chi tiêu tháng) — khớp ý tưởng MonthListActivity.kt bên Android (share layout, chỉ khác
/// nguồn dữ liệu + cách hiển thị dòng), nhưng ở đây generic bằng Swift thay vì Intent extra.
private struct IndexedItem<T>: Identifiable {
    let index: Int
    let value: T
    var id: Int { index }
}

struct MonthListView<T, RowContent: View>: View {
    let title: String
    let loader: (Int, Int) async -> [T]
    let totalText: ([T]) -> String
    /// Trả về true nếu item khớp từ khoá tìm kiếm — truyền nil để ẩn hẳn ô search (không cần cho
    /// mọi trang, nhưng cả 7 trang báo cáo đều có search bên web nên luôn truyền ở BaoCaoMenuView).
    let matches: ((T, String) -> Bool)?
    @ViewBuilder let rowContent: (T) -> RowContent

    @State private var year: Int
    @State private var month: Int
    @State private var items: [T] = []
    @State private var loading = false
    @State private var searchText = ""

    init(title: String, loader: @escaping (Int, Int) async -> [T], totalText: @escaping ([T]) -> String, matches: ((T, String) -> Bool)? = nil, @ViewBuilder rowContent: @escaping (T) -> RowContent) {
        self.title = title
        self.loader = loader
        self.totalText = totalText
        self.matches = matches
        self.rowContent = rowContent
        let now = Date()
        let cal = Calendar.current
        _year = State(initialValue: cal.component(.year, from: now))
        _month = State(initialValue: cal.component(.month, from: now))
    }

    private var filteredItems: [T] {
        guard let matches, !searchText.isEmpty else { return items }
        return items.filter { matches($0, searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            MonthNavBar(year: $year, month: $month) { Task { await load() } }
            if matches != nil {
                SearchBar(text: $searchText, placeholder: "Tìm kiếm...")
            }

            if loading {
                Spacer(); ProgressView(); Spacer()
            } else if filteredItems.isEmpty {
                Spacer()
                Text("Không có dữ liệu").foregroundColor(.textMuted)
                Spacer()
            } else {
                List(filteredItems.indices.map { IndexedItem(index: $0, value: filteredItems[$0]) }) { wrapped in
                    rowContent(wrapped.value)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }

            Divider()
            HStack {
                Text("Tổng").font(.subheadline).foregroundColor(.textMuted)
                Spacer()
                Text(totalText(filteredItems)).font(.headline)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = await loader(year, month)
        loading = false
    }
}

// ---- Row views cho từng loại dữ liệu ----

struct DonMuaHoRowView: View {
    let item: DonMuaHoDto

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : "Khách lẻ").font(.subheadline.bold())
                if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                    Text(ghiChu).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
                if item.giamGia > 0 {
                    Text("-\(HoaDonFormatting.money(item.giamGia))").font(.caption2).foregroundColor(.dangerColor)
                }
            }
        }
    }
}

struct ChiTietThangRowView: View {
    let item: ChiTietThangDto

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                Text(item.tenKhachHang.isEmpty ? "Khách lẻ" : item.tenKhachHang).font(.subheadline.bold())
                if !item.mons.isEmpty {
                    Text(item.mons.joined(separator: ", ")).font(.footnote).foregroundColor(.textMuted).lineLimit(2)
                }
            }
            Spacer()
            Text("x\(item.soLuong)").font(.subheadline.bold())
        }
    }
}

struct ChiTieuThangRowView: View {
    let item: ChiTieuHangNgayDto

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.ten).font(.subheadline.bold())
                    Text(item.billThang ? "#tháng" : "#ngày").font(.caption2.bold()).foregroundColor(item.billThang ? .brandPrimary : .textMuted)
                }
                if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                    Text(ghiChu).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
        }
    }
}

/// Màn "Báo cáo" liệt kê 7 trang tháng — không tự mở NavigationStack (được push từ NavigationStack
/// của tab "Thêm" trong MainTabView, back button tự có từ đó).
struct BaoCaoMenuView: View {
    var body: some View {
            List {
                NavigationLink("Đơn Tại chỗ") {
                    MonthListView(title: "Đơn Tại chỗ", loader: { y, m in await APIClient.shared.getDonTaiCho(year: y, month: m) },
                                  totalText: { HoaDonFormatting.money($0.reduce(0) { $0 + $1.thanhTien }) },
                                  matches: { anyMatchesSearch($1, $0.tenKhachHangText, $0.ghiChu) }) { DonMuaHoRowView(item: $0) }
                }
                NavigationLink("Đơn Mua về") {
                    MonthListView(title: "Đơn Mua về", loader: { y, m in await APIClient.shared.getDonMuaVe(year: y, month: m) },
                                  totalText: { HoaDonFormatting.money($0.reduce(0) { $0 + $1.thanhTien }) },
                                  matches: { anyMatchesSearch($1, $0.tenKhachHangText, $0.ghiChu) }) { DonMuaHoRowView(item: $0) }
                }
                NavigationLink("Đơn Ship") {
                    MonthListView(title: "Đơn Ship", loader: { y, m in await APIClient.shared.getDonShip(year: y, month: m) },
                                  totalText: { HoaDonFormatting.money($0.reduce(0) { $0 + $1.thanhTien }) },
                                  matches: { anyMatchesSearch($1, $0.tenKhachHangText, $0.ghiChu) }) { DonMuaHoRowView(item: $0) }
                }
                NavigationLink("Đơn Mua hộ") {
                    MonthListView(title: "Đơn Mua hộ", loader: { y, m in await APIClient.shared.getDonMuaHo(year: y, month: m) },
                                  totalText: { HoaDonFormatting.money($0.reduce(0) { $0 + $1.thanhTien }) },
                                  matches: { anyMatchesSearch($1, $0.tenKhachHangText, $0.ghiChu) }) { DonMuaHoRowView(item: $0) }
                }
                NavigationLink("Đơn App") {
                    MonthListView(title: "Đơn App", loader: { y, m in await APIClient.shared.getDonApp(year: y, month: m) },
                                  totalText: { HoaDonFormatting.money($0.reduce(0) { $0 + $1.thanhTien }) },
                                  matches: { anyMatchesSearch($1, $0.tenKhachHangText, $0.ghiChu) }) { DonMuaHoRowView(item: $0) }
                }
                NavigationLink("Chi tiết tháng") {
                    MonthListView(title: "Chi tiết tháng", loader: { y, m in await APIClient.shared.getChiTietThang(year: y, month: m) },
                                  totalText: { "\($0.reduce(0) { $0 + $1.soLuong }) món" },
                                  matches: { anyMatchesSearch($1, $0.tenKhachHang, $0.mons.joined(separator: " ")) }) { ChiTietThangRowView(item: $0) }
                }
                NavigationLink("Chi tiêu tháng") {
                    MonthListView(title: "Chi tiêu tháng", loader: { y, m in await APIClient.shared.getChiTieuByMonth(year: y, month: m) },
                                  totalText: { HoaDonFormatting.money($0.reduce(0) { $0 + $1.thanhTien }) },
                                  matches: { anyMatchesSearch($1, $0.ten, $0.ghiChu) }) { ChiTieuThangRowView(item: $0) }
                }
            }
            .navigationTitle("Báo cáo")
            .navigationBarTitleDisplayMode(.inline)
    }
}
