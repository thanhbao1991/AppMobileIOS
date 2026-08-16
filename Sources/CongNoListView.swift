import SwiftUI

/// Danh sách hoá đơn còn ghi nợ, gọi GET /api/dashboard/cong-no-list (không có tham số ngày —
/// khác Hoá đơn/Thanh toán/Chi tiêu). Chỉ xem, bấm vào mở lại HoaDonDetailView để thu tiền/hoàn tác
/// nếu cần (tái dùng nguyên sheet của tab Hoá đơn).
struct CongNoListView: View {
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var selectedId: String?
    @State private var searchText = ""

    private var sortedItems: [HoaDonListDto] {
        items
            .filter { anyMatchesSearch(searchText, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.tenMonSummary) }
            .sorted { ($0.ngayNo ?? "") > ($1.ngayNo ?? "") }
    }

    private var totalText: String {
        HoaDonFormatting.money(sortedItems.reduce(0) { $0 + $1.conLai })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm khách, món, ghi chú...")

                if loading {
                    Spacer(); ProgressView(); Spacer()
                } else if sortedItems.isEmpty {
                    Spacer()
                    Text("Không có công nợ nào").foregroundColor(.textMuted)
                    Spacer()
                } else {
                    List(sortedItems) { item in
                        Button { selectedId = item.id } label: {
                            CongNoRowView(item: item)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                HStack {
                    Text("Tổng nợ").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text(totalText).font(.headline).foregroundColor(.dangerColor)
                }
                .padding()
            }
            .navigationTitle("Công nợ")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiableId($0) } },
            set: { selectedId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongNoList()
        loading = false
    }
}

private struct CongNoRowView: View {
    let item: HoaDonListDto

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.dangerColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                    .font(.subheadline.bold())
                Text("Ghi nợ: \(HoaDonFormatting.time(item.ngayNo))")
                    .font(.footnote).foregroundColor(.textMuted)
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(item.conLai)).font(.subheadline.bold()).foregroundColor(.dangerColor)
        }
    }
}
