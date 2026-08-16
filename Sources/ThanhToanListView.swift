import SwiftUI

/// Danh sách chi tiết thanh toán theo ngày, GET /api/ChiTietHoaDonThanhToan?ngay=. Vuốt trái để
/// xoá 1 dòng (DELETE) — khớp web mobile (TraSuaApp.Mobile/Pages/ChiTietHoaDonThanhToanTab), trước
/// tưởng chỉ Desktop mới có nên đã bỏ, hoá ra web mobile có sẵn.
struct ThanhToanListView: View {
    @State private var currentDate = Date()
    @State private var items: [ChiTietHoaDonThanhToanDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var deletingId: String?

    private var filteredItems: [ChiTietHoaDonThanhToanDto] {
        items.filter { anyMatchesSearch(searchText, $0.ten, $0.ghiChu, $0.tenMonSummary, $0.loaiThanhToan) }
    }

    private var totalText: String {
        HoaDonFormatting.money(filteredItems.reduce(0) { $0 + $1.soTien })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayNavBar(date: $currentDate) { Task { await load() } }
                SearchBar(text: $searchText, placeholder: "Tìm khách, món, ghi chú...")

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        if filteredItems.isEmpty {
                            Text("Không có thanh toán nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredItems) { item in
                                ThanhToanRowView(item: item, deleting: deletingId == item.id)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            Task { await delete(item) }
                                        } label: {
                                            Label("Xoá", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                HStack {
                    Text("Tổng thu").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text(totalText).font(.headline)
                }
                .padding()
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getThanhToanByDay(DateNavFormat.queryDate.string(from: currentDate))
        loading = false
        hasLoaded = true
    }

    private func delete(_ item: ChiTietHoaDonThanhToanDto) async {
        deletingId = item.id
        let result = await APIClient.shared.deleteThanhToan(id: item.id)
        deletingId = nil
        if result.success {
            items.removeAll { $0.id == item.id }
        }
    }
}

private struct ThanhToanRowView: View {
    let item: ChiTietHoaDonThanhToanDto
    let deleting: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                    Text(item.loaiThanhToan ?? "").font(.caption.bold()).foregroundColor(.brandPrimary)
                }
                Text(item.ten).font(.subheadline.bold())
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
                if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                    Text(ghiChu).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            if deleting {
                ProgressView()
            } else {
                Text(HoaDonFormatting.money(item.soTien)).font(.subheadline.bold()).foregroundColor(.successColor)
            }
        }
    }
}
