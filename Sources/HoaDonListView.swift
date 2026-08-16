import SwiftUI

struct HoaDonListView: View {
    @State private var currentDate = Date()
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var selectedId: String?
    @State private var searchText = ""

    private var sortedItems: [HoaDonListDto] {
        items
            .filter { anyMatchesSearch(searchText, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.ghiChuShipper, $0.tenMonSummary, $0.nguoiShip) }
            .sorted {
                let p0 = HoaDonFormatting.sortPriority($0)
                let p1 = HoaDonFormatting.sortPriority($1)
                if p0 != p1 { return p0 < p1 }
                return ($0.ngayGio ?? "") > ($1.ngayGio ?? "")
            }
    }

    private var totalText: String {
        HoaDonFormatting.money(sortedItems.reduce(0) { $0 + $1.thanhTien })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayNavBar(date: $currentDate) { Task { await load() } }
                SearchBar(text: $searchText, placeholder: "Tìm khách, món, ghi chú...")

                if loading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if sortedItems.isEmpty {
                    Spacer()
                    Text("Không có hoá đơn nào").foregroundColor(.textMuted)
                    Spacer()
                } else {
                    List(sortedItems) { item in
                        Button {
                            selectedId = item.id
                        } label: {
                            HoaDonRowView(item: item)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                HStack {
                    Text("Tổng").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text(totalText).font(.headline)
                }
                .padding()
            }
            .navigationTitle("Hoá đơn")
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
        let dateIso = DateNavFormat.queryDate.string(from: currentDate)
        items = await APIClient.shared.getHoaDonListByDay(dateIso)
        loading = false
    }
}

struct IdentifiableId: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

private struct HoaDonRowView: View {
    let item: HoaDonListDto

    private var statusText: String {
        if !(item.ngayNo?.isEmpty ?? true) { return "Ghi nợ" }
        if item.conLai <= 0.0 { return (item.isBank == true) ? "Chuyển khoản" : "Tiền mặt" }
        return "Chưa thu"
    }

    private var statusColor: Color {
        if !(item.ngayNo?.isEmpty ?? true) { return .dangerColor }
        if item.conLai <= 0.0 { return .successColor }
        return .textMuted
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(HoaDonFormatting.phanLoaiColor(item.phanLoai))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                    Text(HoaDonFormatting.phanLoaiLabel(item.phanLoai))
                        .font(.caption.bold())
                        .foregroundColor(HoaDonFormatting.phanLoaiColor(item.phanLoai))
                    Spacer()
                    Text(statusText)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())
                }
                Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                    .font(.subheadline.bold())
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
                if item.phanLoai == "Ship" {
                    if item.nguoiShip?.isEmpty ?? true {
                        Text("Chưa gán shipper").font(.footnote).foregroundColor(.dangerColor)
                    } else {
                        Text("Ship: \(item.nguoiShip!)").font(.footnote).foregroundColor(.textMuted)
                    }
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
        }
    }
}
