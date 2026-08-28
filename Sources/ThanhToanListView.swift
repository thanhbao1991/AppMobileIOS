import SwiftUI
import UIKit

/// Danh sách chi tiết thanh toán theo ngày, GET /api/ChiTietHoaDonThanhToan?ngay=. Nhấp vào dòng để
/// mở sheet chi tiết (giống HoaDonDetailView) thay vì vuốt trái để xoá — vuốt dễ bấm nhầm với data
/// đụng tiền thật, xem ThanhToanDetailView.
struct ThanhToanListView: View {
    @State private var currentDate = Date()
    @State private var items: [ChiTietHoaDonThanhToanDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var selectedId: String?
    @State private var activeFilter: ThanhToanQuickFilter?

    /// Đã áp search nhưng CHƯA áp activeFilter — dùng để đếm số dòng theo từng filter trong menu,
    /// khớp cơ chế searchFilteredItems bên HoaDonListView.
    private var searchFilteredItems: [ChiTietHoaDonThanhToanDto] {
        items.filter { anyMatchesSearch(searchText, $0.ten, $0.ghiChu, $0.tenMonSummary, $0.loaiThanhToan) }
    }

    private var filteredItems: [ChiTietHoaDonThanhToanDto] {
        searchFilteredItems.filter { activeFilter?.matches($0) ?? true }
    }

    private func coloredMenuIcon(_ systemName: String, _ color: Color) -> Image {
        guard let uiImage = UIImage(systemName: systemName)?
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal) else {
            return Image(systemName: systemName)
        }
        return Image(uiImage: uiImage)
    }

    private var totalText: String {
        HoaDonFormatting.money(filteredItems.reduce(0) { $0 + $1.soTien })
    }

    private var totalTienMat: Double {
        filteredItems.filter { $0.phuongThucThanhToanId?.lowercased() == PaymentMethod.tienMatId }
            .reduce(0) { $0 + $1.soTien }
    }

    private var totalChuyenKhoan: Double {
        filteredItems.filter { $0.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId }
            .reduce(0) { $0 + $1.soTien }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DaySearchBar(
                    date: $currentDate, searchText: $searchText,
                    placeholder: "Tìm khách, món, ghi chú...",
                    trailing: AnyView(
                        Menu {
                            // Chỉ lọc 1 loại tại 1 thời điểm — khớp cơ chế HoaDonQuickFilter bên tab
                            // Hoá đơn. 2 filter đầu (avatar Khánh) đọc GhiChu=="Shipper" — đúng cờ
                            // "Duy Khánh" mà ThongKeService dùng để tách "Tiền mặt/Trả nợ Khánh" khỏi
                            // phần thu tại quán (xem ThongKeService.GetThanhToanAsync, Backend).
                            ForEach(ThanhToanQuickFilter.allCases, id: \.self) { filter in
                                let count = searchFilteredItems.filter { filter.matches($0) }.count
                                if filter.isFirstInGroup { Divider() }
                                Button {
                                    activeFilter = (activeFilter == filter) ? nil : filter
                                } label: {
                                    Label {
                                        if let avatarName = filter.avatarName {
                                            ShipperAvatarView(name: avatarName, size: 20)
                                        } else if let systemIcon = filter.systemIcon {
                                            coloredMenuIcon(systemIcon, filter.iconColor)
                                        }
                                    } icon: {
                                        Text(activeFilter == filter ? "✓ \(count) \(filter.label)" : "\(count) \(filter.label)")
                                    }
                                }
                            }
                            if activeFilter != nil {
                                Divider()
                                Button("Bỏ lọc", role: .destructive) { activeFilter = nil }
                            }
                        } label: {
                            Image(systemName: activeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .font(.title2)
                                .foregroundColor(activeFilter == nil ? .textMuted : .brandPrimary)
                                .overlay(alignment: .topTrailing) {
                                    if activeFilter != nil {
                                        Text("\(filteredItems.count)")
                                            .font(.caption2.bold())
                                            .foregroundColor(.white)
                                            .padding(4)
                                            .frame(minWidth: 18, minHeight: 18)
                                            .background(Color.brandPrimary)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -8)
                                    }
                                }
                        }
                    )
                ) { Task { await load() } }

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
                                ThanhToanRowView(item: item)
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
                    HStack {
                        Spacer()
                        Text("Tiền mặt: \(HoaDonFormatting.money(totalTienMat))")
                            .font(.caption2).foregroundColor(.successColor)
                        Text("Chuyển khoản: \(HoaDonFormatting.money(totalChuyenKhoan))")
                            .font(.caption2).foregroundColor(.brandPrimary)
                    }
                    HStack {
                        Text("Tổng thu").font(.subheadline).foregroundColor(.textMuted)
                        Spacer()
                        Text(totalText).font(.headline)
                    }
                }
                .padding()
            }
        }
        .task { await load() }
        .onEntityChanged(["HoaDon", "ChiTietHoaDonThanhToan"], tab: .thanhToan) { Task { await load() } }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiableId($0) } },
            set: { selectedId = $0?.value }
        )) { wrapped in
            if let item = items.first(where: { $0.id == wrapped.value }) {
                ThanhToanDetailView(item: item) {
                    Task { await load() }
                }
            }
        }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getThanhToanByDay(DateNavFormat.queryDate.string(from: currentDate))
        loading = false
        hasLoaded = true
    }
}

private struct ThanhToanRowView: View {
    let item: ChiTietHoaDonThanhToanDto

    /// "Thanh toán" (mặc định) và "Trong ngày" (đa số đơn không nợ) không mang thông tin gì mới nên
    /// ẩn, chỉ hiện 2 loại liên quan nợ (Trả nợ qua ngày/Trả nợ trong ngày).
    private var loaiThanhToanText: String? {
        guard let loai = item.loaiThanhToan, !loai.isEmpty, loai != "Thanh toán", loai != "Trong ngày" else { return nil }
        return loai
    }

    /// "Thanh toán đủ" chỉ là ghi chú mặc định khi thu đủ tiền — ẩn cho gọn (khớp web mobile,
    /// xem PaymentLabels.ThanhToanDu bên Backend).
    private var ghiChuDisplay: String? {
        guard let ghiChu = item.ghiChu, !ghiChu.isEmpty, ghiChu != "Thanh toán đủ", ghiChu != "Shipper" else { return nil }
        return ghiChu
    }

    private var isShipperNote: Bool {
        item.ghiChu == "Shipper"
    }

    private var isBank: Bool {
        item.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId
    }

    /// SePay webhook tự thu (TuDongLuc có giá trị) vs thu tay (nil) — chỉ có ý nghĩa khi isBank.
    private var isAutoBank: Bool {
        isBank && item.tuDongLuc != nil
    }

    /// Chỉ 2 màu theo phương thức thanh toán (tiền mặt/chuyển khoản) — không còn phân biệt theo
    /// loaiThanhToan (Trả nợ qua ngày/trong ngày) như trước.
    private var borderColor: Color {
        isBank ? .brandPrimary : .successColor
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(borderColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                    if let loaiThanhToanText {
                        Text(loaiThanhToanText).font(.caption.bold()).foregroundColor(borderColor)
                    }
                    if isShipperNote {
                        ShipperAvatarView(name: "Khánh", size: 16)
                    } else if let ghiChuDisplay {
                        Text(ghiChuDisplay).font(.caption).foregroundColor(.textMuted).lineLimit(1)
                    }
                }
                Text(item.ten).font(.subheadline.bold())
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(HoaDonFormatting.money(item.soTien)).font(.subheadline.bold())
                HStack(spacing: 3) {
                    if isAutoBank {
                        Text("🤖").font(.caption2)
                    }
                    Text(isBank ? "Chuyển khoản" : "Tiền mặt").font(.caption2.bold())
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background((isBank ? Color.brandPrimary : Color.successColor).opacity(0.15))
                .foregroundColor(isBank ? .brandPrimary : .successColor)
                .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(borderColor.pastelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Lọc nhanh trên tab Thanh toán — chỉ chọn được 1 filter tại 1 thời điểm, nil = không lọc gì.
/// Khớp đúng cách "Thống kê" tách bạch tiền mặt (xem ThongKeService.GetThanhToanAsync, Backend):
/// GhiChu=="Shipper" là cờ đánh dấu khoản Duy Khánh thu hộ qua app riêng của shipper, LoaiThanhToan
/// text lấy thẳng từ bảng lookup LoaiThanhToans (1=Trong ngày, 2=Thanh toán, 3=Trả nợ qua ngày,
/// 4=Trả nợ trong ngày — xem AppDbContext, Share).
enum ThanhToanQuickFilter: CaseIterable, Hashable {
    case tienMatDuyKhanh, traNoDuyKhanh
    case tienMat, chuyenKhoan

    /// Nhóm để chèn Divider giữa 2 cụm: theo Duy Khánh (avatar) / theo phương thức thanh toán (icon).
    var group: Int {
        switch self {
        case .tienMatDuyKhanh, .traNoDuyKhanh: return 0
        case .tienMat, .chuyenKhoan: return 1
        }
    }

    var isFirstInGroup: Bool {
        guard group > 0 else { return false }
        let index = Self.allCases.firstIndex(of: self)!
        return Self.allCases[Self.allCases.index(before: index)].group != group
    }

    var label: String {
        switch self {
        case .tienMatDuyKhanh: return "Tiền mặt Duy Khánh"
        case .traNoDuyKhanh: return "Trả nợ Duy Khánh"
        case .tienMat: return "Tiền mặt"
        case .chuyenKhoan: return "Chuyển khoản"
        }
    }

    var avatarName: String? {
        switch self {
        case .tienMatDuyKhanh, .traNoDuyKhanh: return "Khánh"
        case .tienMat, .chuyenKhoan: return nil
        }
    }

    var systemIcon: String? {
        switch self {
        case .tienMat: return "banknote.fill"
        case .chuyenKhoan: return "creditcard.fill"
        default: return nil
        }
    }

    var iconColor: Color {
        switch self {
        case .tienMat: return .successColor
        case .chuyenKhoan: return .brandPrimary
        default: return .textMuted
        }
    }

    func matches(_ item: ChiTietHoaDonThanhToanDto) -> Bool {
        let isTienMat = item.phuongThucThanhToanId?.lowercased() == PaymentMethod.tienMatId
        let isBank = item.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId
        let isDuyKhanh = item.ghiChu == "Shipper"
        switch self {
        case .tienMatDuyKhanh:
            return isTienMat && isDuyKhanh && item.loaiThanhToan == "Trong ngày"
        case .traNoDuyKhanh:
            return isTienMat && isDuyKhanh
                && (item.loaiThanhToan == "Trả nợ qua ngày" || item.loaiThanhToan == "Trả nợ trong ngày")
        case .tienMat:
            return isTienMat
        case .chuyenKhoan:
            return isBank
        }
    }
}
