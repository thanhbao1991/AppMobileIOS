import SwiftUI

struct HoaDonListView: View {
    @State private var currentDate = Date()
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
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

                if !hasLoaded {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    List {
                        if sortedItems.isEmpty {
                            Text("Không có hoá đơn nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(sortedItems) { item in
                                HoaDonRowView(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedId = item.id }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            }
                        }
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
        hasLoaded = true
    }
}

/// Avatar tròn khớp HoaDonTabControl.xaml bên Desktop (2 shipper cố định Khánh/Nhã có ảnh thật,
/// tên khác dùng ảnh "ship" chung — Desktop chỉ có 2 DataTrigger này, chưa có shipper thứ 3 nào).
struct ShipperAvatarView: View {
    let name: String
    var size: CGFloat = 36

    private var assetName: String {
        switch name {
        case "Khánh": return "shipper_khanh"
        case "Nhã": return "shipper_nha"
        default: return "shipper_generic"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

struct IdentifiableId: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

private struct HoaDonRowView: View {
    let item: HoaDonListDto

    /// Chỉ 3 trạng thái đã-xử-lý — "Chưa thu" bị bỏ hẳn (không mang thông tin gì mới, phần lớn đơn
    /// đang ở trạng thái này nên hiện lên toàn màn hình đầy badge xám vô nghĩa).
    private var statusText: String? {
        if !(item.ngayNo?.isEmpty ?? true) { return "Ghi nợ" }
        if item.conLai <= 0.0 { return (item.isBank == true) ? "Chuyển khoản" : "Tiền mặt" }
        return nil
    }

    private var statusColor: Color {
        if !(item.ngayNo?.isEmpty ?? true) { return .dangerColor }
        return (item.isBank == true) ? .brandPrimary : .successColor
    }

    private var phoneDigits: String? {
        guard let sdt = item.soDienThoaiText, !sdt.isEmpty else { return nil }
        return sdt.filter { $0.isNumber || $0 == "+" }
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
                        HStack(spacing: 4) {
                            ShipperAvatarView(name: item.nguoiShip!, size: 18)
                            Text(item.nguoiShip!).font(.footnote).foregroundColor(.textMuted)
                        }
                    }
                    if let diaChi = item.diaChiText, !diaChi.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill").font(.caption2).foregroundColor(.textMuted)
                            Text(diaChi).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                        }
                    }
                    if let phoneDigits, let sdt = item.soDienThoaiText, let url = URL(string: "tel:\(phoneDigits)") {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "phone.fill").font(.caption2)
                                Text(sdt).font(.footnote)
                            }
                            .foregroundColor(.brandPrimary)
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
                if let statusText {
                    Text(statusText)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
