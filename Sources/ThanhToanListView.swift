import SwiftUI

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

    private var filteredItems: [ChiTietHoaDonThanhToanDto] {
        items.filter { anyMatchesSearch(searchText, $0.ten, $0.ghiChu, $0.tenMonSummary, $0.loaiThanhToan) }
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
                DaySearchBar(date: $currentDate, searchText: $searchText, placeholder: "Tìm khách, món, ghi chú...") { Task { await load() } }

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
                        Image(systemName: "gearshape.2.fill").font(.caption2)
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
