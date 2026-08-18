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
    @State private var creatingPending: PendingCreate?
    /// Tick định kỳ để buộc SwiftUI vẽ lại badge "chờ" trên các card — nếu không có state nào đổi,
    /// waitingMinutes chỉ tính 1 lần lúc load rồi đứng yên mãi (không tự cập nhật theo thời gian thực).
    @State private var now = Date()
    @State private var activeFilters: Set<HoaDonQuickFilter> = []
    private let clockTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    private var sortedItems: [HoaDonListDto] {
        items
            .filter { anyMatchesSearch(searchText, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.ghiChuShipper, $0.tenMonSummary, $0.nguoiShip) }
            .filter { item in activeFilters.isEmpty || activeFilters.contains { $0.matches(item) } }
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
                    trailing: AnyView(
                        Menu {
                            ForEach(HoaDonQuickFilter.allCases, id: \.self) { filter in
                                Toggle(filter.label, isOn: Binding(
                                    get: { activeFilters.contains(filter) },
                                    set: { isOn in
                                        if isOn { activeFilters.insert(filter) } else { activeFilters.remove(filter) }
                                    }
                                ))
                            }
                        } label: {
                            Image(systemName: activeFilters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .font(.title2)
                                .foregroundColor(activeFilters.isEmpty ? .textMuted : .brandPrimary)
                        }
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
                HStack(spacing: 12) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 34))
                    }
                    .foregroundColor(.brandPrimary)

                    VStack(alignment: .trailing, spacing: 2) {
                        if !phanLoaiTotals.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(phanLoaiTotals, id: \.label) { item in
                                    Text("\(item.label) \(item.text)")
                                        .font(.caption2).foregroundColor(item.color)
                                }
                            }
                        }
                        Text(totalText).font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
            AddHoaDonSheet(
                onPick: { code in
                    Task {
                        // Đợi sheet "+" đóng xong hẳn rồi mới mở form thêm hoá đơn — mở đồng thời 2
                        // sheet trên cùng view dễ bị SwiftUI bỏ qua sheet thứ hai (race giữa 2 lần
                        // dismiss/present).
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        creatingPending = PendingCreate(phanLoai: code)
                    }
                },
                onPickGoiSom: { khachHangId, tenSanPham, tenBienThe in
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        creatingPending = PendingCreate(
                            phanLoai: "Ship",
                            presetKhachHangId: khachHangId,
                            presetTenSanPham: tenSanPham,
                            presetTenBienThe: tenBienThe
                        )
                    }
                }
            )
        }
        .sheet(item: $creatingPending) { pending in
            HoaDonCreateFormView(
                phanLoai: pending.phanLoai,
                presetKhachHangId: pending.presetKhachHangId,
                presetTenSanPham: pending.presetTenSanPham,
                presetTenBienThe: pending.presetTenBienThe
            ) { newId in
                Task {
                    await load()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    selectedId = newId
                }
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

/// Lọc nhanh trên tab Hoá đơn — chọn được nhiều đồng thời (OR), rỗng = không lọc gì. Thứ tự khai
/// báo = thứ tự hiện trong menu (Tí nữa CK trước vì cần xử lý gấp nhất, rồi tới các mốc thu tiền).
enum HoaDonQuickFilter: CaseIterable, Hashable {
    case tiNuaChuyenKhoan, chuaThanhToan, ghiNo

    var label: String {
        switch self {
        case .tiNuaChuyenKhoan: return "Tí nữa chuyển khoản"
        case .chuaThanhToan: return "Chưa thanh toán"
        case .ghiNo: return "Đã ghi nợ"
        }
    }

    /// conLai<=0 loại trừ trước cho .ghiNo/.chuaThanhToan — khớp logic statusText ở HoaDonRowView
    /// (ngayNo cũ vẫn còn giá trị dù đã thu đủ, không tự xoá). .chuaThanhToan KHÔNG gồm đơn đã ghi
    /// nợ — ghi nợ là một trạng thái xử lý riêng, không phải "chưa thanh toán" còn treo.
    func matches(_ item: HoaDonListDto) -> Bool {
        let daGhiNo = !(item.ngayNo?.isEmpty ?? true)
        switch self {
        case .ghiNo: return item.conLai > 0 && daGhiNo
        case .chuaThanhToan: return item.conLai > 0 && !daGhiNo
        case .tiNuaChuyenKhoan: return item.conLai > 0 && item.ghiChuShipper == "Tí nữa chuyển khoản"
        }
    }
}

struct IdentifiableId: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

/// Tham số mở HoaDonCreateFormView — "Đơn 7h" chốt sẵn phanLoai=Ship + preset khách/món.
private struct PendingCreate: Identifiable {
    let phanLoai: String
    var presetKhachHangId: String? = nil
    var presetTenSanPham: String? = nil
    var presetTenBienThe: String? = nil
    var id: String { phanLoai + (presetKhachHangId ?? "") }
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
    /// ShipperActionService.TiNuaChuyenKhoanAsync) — chỉ set được cho đơn Ship (ShipperQueryService
    /// chỉ trả PhanLoai='Ship' cho app shipper), Mv không bao giờ có giá trị này.
    private var shipTiNuaChuyenKhoan: Bool {
        item.phanLoai == "Ship" && item.ghiChuShipper == "Tí nữa chuyển khoản" && item.conLai > 0
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(HoaDonFormatting.phanLoaiColor(item.phanLoai))
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
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if shipTiNuaChuyenKhoan {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill").font(.caption2)
                        Text("Tí nữa CK").font(.caption2.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.warningColor)
                    .clipShape(Capsule())
                }
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
        .background(HoaDonFormatting.phanLoaiBgColor(item.phanLoai))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Khung chọn phân loại đơn khi bấm "+" — chọn xong đóng sheet này và mở HoaDonCreateFormView
/// (form đầy đủ: món/khách/giảm giá, xem HoaDonCreateFormView.swift). Phân loại chốt tại đây,
/// không đổi được nữa trong form (khớp yêu cầu "không cần" phần đổi phân loại/bàn giữa chừng).
private struct AddHoaDonSheet: View {
    let onPick: (String) -> Void
    let onPickGoiSom: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showGoiSom = false

    private let categories: [(code: String, icon: String)] = [
        ("Ship", "bicycle"),
        ("Tại Chỗ", "cup.and.saucer.fill"),
        ("Mv", "bag.fill"),
        ("Mh", "hand.raised.fill"),
        ("App", "app.badge"),
    ]
    private let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: twoColumns, spacing: 12) {
                    ForEach(categories, id: \.code) { cat in
                        Button { dismiss(); onPick(cat.code) } label: {
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
                }

                Button { showGoiSom = true } label: {
                    HStack {
                        Image(systemName: "clock.fill")
                        Text("Đơn 7h — khách hay gọi sớm")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(.brandPrimary)

                // "Bắt đơn App" — chưa rõ nghiệp vụ cụ thể (không có tính năng tương ứng bên Desktop
                // để đối chiếu), để placeholder chờ xác nhận thay vì đoán rồi làm sai luồng tiền.
                HStack(spacing: 8) {
                    Image(systemName: "app.badge.checkmark")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bắt đơn App").font(.subheadline.bold())
                        Text("Sắp có").font(.caption2)
                    }
                    Spacer()
                }
                .foregroundColor(.textMuted)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(Color.textMuted.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
        .sheet(isPresented: $showGoiSom) {
            KhachGoiSomSheet { khachHangId, tenSanPham, tenBienThe in
                showGoiSom = false
                dismiss()
                onPickGoiSom(khachHangId, tenSanPham, tenBienThe)
            }
        }
        .presentationDetents([.medium])
    }
}

/// "Đơn 7h" — danh sách khách hay gọi trước 7h sáng, chọn 1 khách để mở form tạo đơn Ship đã
/// điền sẵn khách + món cuối họ từng gọi. Khớp KhachGoiSomAsync/OpenKhachGoiSom (Desktop,
/// HoaDonTabControl.Board.cs) — server đã gộp sẵn 70% khách quen/30% khách mới, sort theo SoLan.
private struct KhachGoiSomSheet: View {
    /// (khachHangId, tenSanPham, tenBienThe)
    let onPick: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [KhachHangGoiSomDto] = []
    @State private var loading = true

    private var regulars: [KhachHangGoiSomDto] { items.filter { !$0.laKhachMoi } }
    private var moi: [KhachHangGoiSomDto] { items.filter { $0.laKhachMoi } }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if items.isEmpty {
                    Text("Chưa có dữ liệu khách hay gọi trước 7h.")
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !regulars.isEmpty {
                            Section {
                                ForEach(regulars) { row($0) }
                            }
                        }
                        if !moi.isEmpty {
                            Section("Khách mới") {
                                ForEach(moi) { row($0) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Khách hay gọi trước 7h")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .task {
            items = await APIClient.shared.getKhachHangHayGoiSom()
            loading = false
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ item: KhachHangGoiSomDto) -> some View {
        Button {
            onPick(item.khachHangId, item.tenSanPham, item.tenBienThe)
        } label: {
            HStack {
                Text(item.ten).font(.subheadline.bold())
                Spacer()
                Text(monText(item)).font(.caption).foregroundColor(.textMuted).lineLimit(1)
            }
        }
    }

    private func monText(_ item: KhachHangGoiSomDto) -> String {
        guard !item.tenSanPham.isEmpty else { return "" }
        if item.tenBienThe.isEmpty || item.tenBienThe == "Mặc định" || item.tenBienThe == "Size Chuẩn" {
            return item.tenSanPham
        }
        return "\(item.tenSanPham) (\(item.tenBienThe))"
    }
}
