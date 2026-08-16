import SwiftUI

/// Danh sách chi tiết thanh toán theo ngày, GET /api/ChiTietHoaDonThanhToan?ngay=. Chỉ xem — xoá
/// dòng thanh toán ảnh hưởng công nợ/tồn quỹ nên không đưa vào bản mobile này (Desktop mới có).
struct ThanhToanListView: View {
    @State private var currentDate = Date()
    @State private var items: [ChiTietHoaDonThanhToanDto] = []
    @State private var loading = false

    private var totalText: String {
        HoaDonFormatting.money(items.reduce(0) { $0 + $1.soTien })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayNavBar(date: $currentDate) { Task { await load() } }

                if loading {
                    Spacer(); ProgressView(); Spacer()
                } else if items.isEmpty {
                    Spacer()
                    Text("Không có thanh toán nào").foregroundColor(.textMuted)
                    Spacer()
                } else {
                    List(items) { item in
                        ThanhToanRowView(item: item)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
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
            .navigationTitle("Thanh toán")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getThanhToanByDay(DateNavFormat.queryDate.string(from: currentDate))
        loading = false
    }
}

private struct ThanhToanRowView: View {
    let item: ChiTietHoaDonThanhToanDto

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
            Text(HoaDonFormatting.money(item.soTien)).font(.subheadline.bold()).foregroundColor(.successColor)
        }
    }
}
