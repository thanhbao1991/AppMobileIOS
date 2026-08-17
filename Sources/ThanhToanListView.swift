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
                                ThanhToanRowView(item: item, deleting: deletingId == item.id)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
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
            if deleting {
                ProgressView()
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(HoaDonFormatting.money(item.soTien)).font(.subheadline.bold())
                    Text(isBank ? "Chuyển khoản" : "Tiền mặt")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background((isBank ? Color.brandPrimary : Color.successColor).opacity(0.15))
                        .foregroundColor(isBank ? .brandPrimary : .successColor)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(isBank ? HoaDonFormatting.cardGradientBlue : HoaDonFormatting.cardGradientGreen)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
