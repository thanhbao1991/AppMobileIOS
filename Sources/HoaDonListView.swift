import Combine
import SwiftUI

struct HoaDonListView: View {
    @State private var currentDate = Date()
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var selectedId: String?
    @State private var searchText = ""
    @State private var showAddSheet = false
    /// Tick định kỳ để buộc SwiftUI vẽ lại badge "chờ" trên các card — nếu không có state nào đổi,
    /// waitingMinutes chỉ tính 1 lần lúc load rồi đứng yên mãi (không tự cập nhật theo thời gian thực).
    @State private var now = Date()
    private let clockTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

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

    /// Tổng tiền theo từng phân loại đơn, gộp trên 1 dòng gọn (vd "Ship 203k, T.chỗ 230k...").
    private var phanLoaiTotals: [(label: String, color: Color, text: String)] {
        let order = ["Ship", "Tại Chỗ", "Mv", "Mh", "App"]
        let shortLabel: [String: String] = ["Ship": "Ship", "Tại Chỗ": "T.chỗ", "Mv": "M.về", "Mh": "M.hộ", "App": "App"]
        return order.compactMap { phanLoai in
            let total = sortedItems.filter { $0.phanLoai == phanLoai }.reduce(0) { $0 + $1.thanhTien }
            guard total > 0 else { return nil }
            return (shortLabel[phanLoai] ?? phanLoai, HoaDonFormatting.phanLoaiColor(phanLoai), HoaDonFormatting.moneyShort(total))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DaySearchBar(
                    date: $currentDate, searchText: $searchText,
                    placeholder: "Tìm khách, món, ghi chú...",
                    leading: AnyView(
                        Button { showAddSheet = true } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .foregroundColor(.brandPrimary)
                    )
                ) { Task { await load() } }

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
                                HoaDonRowView(item: item, now: now)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedId = item.id }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                VStack(spacing: 2) {
                    if !phanLoaiTotals.isEmpty {
                        HStack(spacing: 8) {
                            Spacer()
                            ForEach(phanLoaiTotals, id: \.label) { item in
                                Text("\(item.label) \(item.text)")
                                    .font(.caption2).foregroundColor(item.color)
                            }
                        }
                    }
                    HStack {
                        Text("Tổng tiền").font(.subheadline).foregroundColor(.textMuted)
                        Spacer()
                        Text(totalText).font(.headline)
                    }
                }
                .padding()
            }
        }
        .task { await load() }
        .onReceive(clockTimer) { now = $0 }
        .onEntityChanged(["HoaDon"], tab: .hoaDon) { Task { await load() } }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiableId($0) } },
            set: { selectedId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddHoaDonSheet()
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
    let now: Date

    /// Chỉ 3 trạng thái đã-xử-lý — "Chưa thu" bị bỏ hẳn (không mang thông tin gì mới, phần lớn đơn
    /// đang ở trạng thái này nên hiện lên toàn màn hình đầy badge xám vô nghĩa).
    /// conLai<=0 phải check TRƯỚC ngayNo: khách ghi nợ rồi trả xong, ngayNo vẫn còn giá trị cũ
    /// (backend không xoá), nên nếu check ngayNo trước sẽ hiện "Ghi nợ" sai dù đã thu đủ.
    private var statusText: String? {
        if item.conLai <= 0.0 { return (item.isBank == true) ? "Chuyển khoản" : "Tiền mặt" }
        if !(item.ngayNo?.isEmpty ?? true) { return "Ghi nợ" }
        return nil
    }

    private var statusColor: Color {
        if item.conLai <= 0.0 { return (item.isBank == true) ? .brandPrimary : .successColor }
        return .dangerColor
    }

    /// Chỉ hiện "chờ" cho 2 trường hợp cần nhân viên xử lý sớm: Ship chưa gán shipper, hoặc Mua về
    /// chưa thanh toán — đơn khác đã có shipper/đã thu thì hiển thị thêm không có ý nghĩa gì.
    private var showWaiting: Bool {
        (item.phanLoai == "Ship" && (item.nguoiShip?.isEmpty ?? true))
            || (item.phanLoai == "Mv" && item.conLai > 0)
    }

    private var waitingMinutes: Int? {
        guard showWaiting else { return nil }
        return HoaDonFormatting.minutesSince(item.ngayGio, now: now)
    }

    private var waitingColor: Color {
        guard let waitingMinutes else { return .textMuted }
        if waitingMinutes >= 30 { return .dangerColor }
        if waitingMinutes >= 15 { return .warningColor }
        return .textMuted
    }

    /// Shipper đánh dấu "Tí nữa chuyển khoản" (GhiChuShipper == chuỗi cố định, xem
    /// ShipperActionService.TiNuaChuyenKhoanAsync) — cần nổi bật để nhân viên chủ động xử lý.
    private var isTiNuaChuyenKhoan: Bool {
        item.phanLoai == "Mv" && item.ghiChuShipper == "Tí nữa chuyển khoản"
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(isTiNuaChuyenKhoan ? Color.warningColor : HoaDonFormatting.phanLoaiColor(item.phanLoai))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                    Text(HoaDonFormatting.phanLoaiLabel(item.phanLoai))
                        .font(.caption.bold())
                        .foregroundColor(HoaDonFormatting.phanLoaiColor(item.phanLoai))
                    if item.phanLoai == "Ship", let nguoiShip = item.nguoiShip, !nguoiShip.isEmpty {
                        ShipperAvatarView(name: nguoiShip, size: 16)
                    }
                    Spacer()
                    if let waitingMinutes {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill").font(.caption2)
                            Text(HoaDonFormatting.waitingText(waitingMinutes)).font(.caption2.bold())
                        }
                        .foregroundColor(waitingColor)
                    }
                }
                Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                    .font(.subheadline.bold())
                if item.phanLoai == "Ship", let diaChi = item.diaChiText, !diaChi.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill").font(.caption2).foregroundColor(.textMuted)
                        Text(diaChi).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                    }
                }
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
                if isTiNuaChuyenKhoan {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill").font(.caption2)
                        Text("Tí nữa chuyển khoản").font(.caption.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.warningColor)
                    .clipShape(Capsule())
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
        .padding(12)
        .background(isTiNuaChuyenKhoan ? Color.warningColor.pastelBackground() : HoaDonFormatting.phanLoaiBgColor(item.phanLoai))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isTiNuaChuyenKhoan ? Color.warningColor : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Khung chọn phân loại đơn khi bấm "+" — CHỈ giao diện, chưa nối API tạo hoá đơn thật (theo yêu
/// cầu "làm khung trước", các Button đều rỗng action).
private struct AddHoaDonSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let categories: [(code: String, icon: String)] = [
        ("Ship", "bicycle"),
        ("Tại Chỗ", "cup.and.saucer.fill"),
        ("Mv", "bag.fill"),
        ("Mh", "hand.raised.fill"),
        ("App", "app.badge"),
    ]
    /// Gộp chung style + lưới với 5 phân loại đơn phía trên (trước tách riêng bằng Divider, giờ
    /// nhập chung 1 lưới cho đồng nhất).
    private let extras: [(label: String, icon: String, color: Color)] = [
        ("Đơn 7h", "clock.fill", .brandPrimary),
        ("Bắt đơn App", "app.badge.checkmark", .dangerColor),
    ]
    private let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: twoColumns, spacing: 12) {
                    ForEach(categories, id: \.code) { cat in
                        Button {} label: {
                            VStack(spacing: 6) {
                                Image(systemName: cat.icon).font(.title2)
                                Text(HoaDonFormatting.phanLoaiLabel(cat.code)).font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .tint(HoaDonFormatting.phanLoaiColor(cat.code))
                    }

                    ForEach(extras, id: \.label) { extra in
                        Button {} label: {
                            VStack(spacing: 6) {
                                Image(systemName: extra.icon).font(.title2)
                                Text(extra.label).font(.subheadline.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: 12))
                        .tint(extra.color)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
