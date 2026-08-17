import SwiftUI

struct HoaDonDetailView: View {
    let hoaDonId: String
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: HoaDonDetailDto?
    @State private var loading = true
    @State private var busy = false
    @State private var errorText: String?
    @State private var showShipperPicker = false
    @State private var pendingAction: PendingAction?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if let detail {
                    content(detail)
                } else {
                    Text("Không tải được hoá đơn").foregroundColor(.textMuted)
                }
            }
            .navigationTitle("Chi tiết hoá đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                if let detail {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 6) {
                            Text(HoaDonFormatting.phanLoaiLabel(detail.phanLoai))
                                .font(.caption.bold())
                                .foregroundColor(HoaDonFormatting.phanLoaiColor(detail.phanLoai))
                            if detail.phanLoai == "Ship", let nguoiShip = detail.nguoiShip, !nguoiShip.isEmpty {
                                ShipperAvatarView(name: nguoiShip, size: 20)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showShipperPicker) {
            shipperPickerSheet
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.confirmLabel, role: pendingAction.destructive ? .destructive : nil) {
                    Task { await execute(pendingAction) }
                }
                Button("Huỷ", role: .cancel) {}
            }
        }
    }

    /// Mọi thao tác đụng tiền/dữ liệu thật đều phải qua bước "Xác nhận" — khớp ConfirmDialog.Show
    /// bên Desktop (DeleteAsync/RollbackAsync/GhiNoAsync đều mở dialog trước khi gọi API).
    private enum PendingAction: Identifiable {
        case tienMat, chuyenKhoan, rollback, ghiNo, xoa, doiPhuongThuc
        case ship(String)

        var id: String {
            switch self {
            case .tienMat: return "tienMat"
            case .chuyenKhoan: return "chuyenKhoan"
            case .rollback: return "rollback"
            case .ghiNo: return "ghiNo"
            case .xoa: return "xoa"
            case .doiPhuongThuc: return "doiPhuongThuc"
            case .ship(let name): return "ship-\(name)"
            }
        }

        var title: String {
            switch self {
            case .tienMat: return "Thu tiền mặt?"
            case .chuyenKhoan: return "Thu chuyển khoản?"
            case .rollback: return "Hoàn tác thanh toán?"
            case .ghiNo: return "Ghi nợ hoá đơn này?"
            case .xoa: return "Xoá hoá đơn này?"
            case .doiPhuongThuc: return "Đổi phương thức thanh toán?"
            case .ship(let name): return "Gán shipper \(name)?"
            }
        }

        var confirmLabel: String {
            switch self {
            case .xoa: return "Xoá"
            case .ghiNo: return "Ghi nợ"
            case .rollback: return "Hoàn tác"
            case .ship: return "Xác nhận"
            default: return "Xác nhận"
            }
        }

        var destructive: Bool {
            if case .xoa = self { return true }
            return false
        }
    }

    private func content(_ d: HoaDonDetailDto) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorText {
                    Text(errorText).foregroundColor(.dangerColor).font(.footnote)
                }

                Group {
                    infoRow("Khách hàng", d.tenKhachHangText?.isEmpty == false ? d.tenKhachHangText! : (d.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                    if let sdt = d.soDienThoaiText, !sdt.isEmpty { phoneRow(sdt) }
                    if let dc = d.diaChiText, !dc.isEmpty { infoRow("Địa chỉ", dc) }
                    if let gc = d.ghiChu, !gc.isEmpty { infoRow("Ghi chú", gc) }
                }

                Divider()

                if let chiTiet = d.chiTietHoaDons, !chiTiet.isEmpty {
                    HStack {
                        Text("Món").font(.headline)
                        Spacer()
                        Text("\(chiTiet.reduce(0) { $0 + $1.soLuong }) ly").font(.subheadline).foregroundColor(.textMuted)
                    }
                    ForEach(chiTiet) { ct in
                        HStack {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.caption)
                                .foregroundColor(.brandPrimary)
                            VStack(alignment: .leading) {
                                Text("\(ct.tenSanPham)\(bienTheSuffix(ct.tenBienThe))")
                                if let note = ct.noteText, !note.isEmpty {
                                    Text(note).font(.caption).foregroundColor(.textMuted)
                                }
                            }
                            Spacer()
                            Text("x\(ct.soLuong)").foregroundColor(.textMuted)
                            Text(HoaDonFormatting.money(ct.donGia * Double(ct.soLuong))).frame(width: 100, alignment: .trailing)
                        }
                    }
                    Divider()
                }

                infoRow("Tổng tiền", HoaDonFormatting.money(d.tongTien))
                if d.giamGia > 0 { infoRow("Giảm giá", HoaDonFormatting.money(d.giamGia)) }
                infoRow("Thành tiền", HoaDonFormatting.money(d.thanhTien))
                infoRow("Đã thu", HoaDonFormatting.money(d.daThu))
                HStack {
                    Text("Còn lại").foregroundColor(.textMuted)
                    Spacer()
                    Text(HoaDonFormatting.money(d.conLai))
                        .fontWeight(.bold)
                        .foregroundColor(d.conLai > 0 ? .dangerColor : .successColor)
                }
                .font(.subheadline)
                // "Nợ đơn khác" (không phải "Tổng nợ khách") vì con số này CHỈ TÍNH các đơn khác của
                // cùng khách — KHÔNG gồm "Còn lại" của chính đơn đang xem (xem HoaDonQueryService.
                // GetByIdAsync, subquery loại trừ "AND h.Id != @id"). Nhãn cũ dễ hiểu lầm là đã gộp.
                if let no = d.tongNoKhachHang, no != 0 { infoRow("Nợ đơn khác", HoaDonFormatting.money(no)) }

                Divider()
                actionButtons(d)
            }
            .padding()
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
    }

    /// Icon + mã phím tắt (F1/F4/Esc/F12/Del) khớp WrapPanel "Action buttons" trong
    /// HoaDonTabControl.xaml (Desktop) — nhân viên đã quen dùng phím tắt này hàng ngày trên máy tính
    /// quán, mã tắt "quen mặt" với họ hơn là chữ đầy đủ; caption nhỏ bên dưới giữ lại chữ đầy đủ cho
    /// người mới. (F2/F3/F9 in/copy ảnh không áp dụng cho mobile.)
    private func actionButtons(_ d: HoaDonDetailDto) -> some View {
        // Ghi nợ bắt buộc phải có khách hàng — khớp guard "Hoá đơn chưa có thông tin khách hàng!"
        // trong GhiNoAsync (Desktop Actions.cs). Không có KhachHangId thì không có ai để ghi nợ.
        let chuaGhiNo = d.ngayNo?.isEmpty ?? true
        let payments = d.payments ?? []
        let singlePaymentBank = payments.count == 1 ? payments[0].phuongThucThanhToanId.lowercased() == PaymentMethod.chuyenKhoanId : nil

        return VStack(spacing: 10) {
            if d.conLai > 0 {
                HStack(spacing: 10) {
                    ActionButtonView(icon: "banknote", code: "F1", caption: "Tiền mặt", color: .successColor, prominent: true) {
                        pendingAction = .tienMat
                    }
                    ActionButtonView(icon: "creditcard", code: "F4", caption: "Chuyển khoản", color: .brandPrimary, prominent: true) {
                        pendingAction = .chuyenKhoan
                    }
                }
            } else {
                ActionButtonView(icon: "arrow.uturn.backward.circle", code: nil, caption: "Hoàn tác thanh toán", color: .warningColor) {
                    pendingAction = .rollback
                }

                if let singlePaymentBank {
                    ActionButtonView(
                        icon: "arrow.left.arrow.right", code: nil,
                        caption: singlePaymentBank ? "Đổi sang Tiền mặt" : "Đổi sang Chuyển khoản",
                        color: singlePaymentBank ? .successColor : .brandPrimary
                    ) {
                        pendingAction = .doiPhuongThuc
                    }
                }
            }

            if d.phanLoai == "Ship" {
                ActionButtonView(icon: "bicycle", code: "Esc", caption: "Đi Ship", color: .pinkColor) {
                    showShipperPicker = true
                }
            }

            if d.conLai > 0 && chuaGhiNo && d.khachHangId != nil {
                ActionButtonView(icon: "exclamationmark.circle", code: "F12", caption: "Ghi nợ", color: .dangerColor) {
                    pendingAction = .ghiNo
                }
            }

            ActionButtonView(icon: "trash", code: "Del", caption: "Xoá đơn", color: .dangerColor) {
                pendingAction = .xoa
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "Mặc định"/"Size Chuẩn"/"Chuẩn" là biến thể mặc định — khớp HoaDonTabControl.Board.cs
    /// và SanPhamSearchBox.xaml.cs (Desktop), không cần hiển thị vì không mang thêm thông tin.
    private func bienTheSuffix(_ tenBienThe: String?) -> String {
        guard let tenBienThe, !tenBienThe.isEmpty,
              !["Mặc định", "Size Chuẩn", "Chuẩn"].contains(tenBienThe) else { return "" }
        return " (\(tenBienThe))"
    }

    /// Chọn shipper bằng thẻ bấm (khớp ShipperDialog bên Desktop — 2 shipper cố định Khánh/Nhã,
    /// KHÔNG cho gõ tay tên tuỳ ý) thay vì TextField tự do như trước.
    private var shipperPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Chọn shipper").font(.headline)
                HStack(spacing: 20) {
                    ForEach(["Khánh", "Nhã"], id: \.self) { name in
                        Button {
                            showShipperPicker = false
                            pendingAction = .ship(name)
                        } label: {
                            VStack(spacing: 8) {
                                ShipperAvatarView(name: name, size: 68)
                                Text(name).font(.subheadline.bold())
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(.top, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { showShipperPicker = false }
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    /// SĐT dưới tên khách hàng — nhấp để gọi (thay cho icon SĐT trên card danh sách đã bỏ).
    private func phoneRow(_ sdt: String) -> some View {
        let digits = sdt.filter { $0.isNumber || $0 == "+" }
        return HStack {
            Text("SĐT").foregroundColor(.textMuted)
            Spacer()
            if let url = URL(string: "tel:\(digits)") {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill").font(.caption2)
                        Text(sdt)
                    }
                    .foregroundColor(.brandPrimary)
                }
            } else {
                Text(sdt)
            }
        }
        .font(.subheadline)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.textMuted)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func execute(_ action: PendingAction) async {
        guard let d = detail else { return }
        switch action {
        case .tienMat:
            await run { await thuTien(isCash: true, d: d) }
        case .chuyenKhoan:
            await run { await thuTien(isCash: false, d: d) }
        case .rollback:
            await run { await APIClient.shared.rollback(hoaDonId: hoaDonId) }
        case .ghiNo:
            await run { await APIClient.shared.ghiNo(hoaDonId: hoaDonId) }
        case .xoa:
            await run { await APIClient.shared.delete(hoaDonId: hoaDonId) }
        case .doiPhuongThuc:
            guard let paymentId = d.payments?.first?.id else { return }
            await run { await APIClient.shared.doiPhuongThucThanhToan(id: paymentId) }
        case .ship(let name):
            await run { await APIClient.shared.ganShipper(hoaDonId: hoaDonId, nguoiShip: name) }
        }
    }

    private func thuTien(isCash: Bool, d: HoaDonDetailDto) async -> ActionResult {
        await APIClient.shared.thuTien(
            hoaDonId: hoaDonId, isCash: isCash, soTien: d.conLai,
            ten: d.tenKhachHangText ?? "Khách lẻ", khachHangId: d.khachHangId
        )
    }

    private func run(_ action: () async -> ActionResult) async {
        busy = true
        let result = await action()
        busy = false
        if result.success {
            onChanged()
            await load()
        } else {
            errorText = result.message ?? "Thao tác thất bại."
        }
    }

    private func load() async {
        loading = true
        detail = await APIClient.shared.getHoaDonDetail(hoaDonId)
        loading = false
    }
}

private struct ActionButtonView: View {
    let icon: String
    let code: String?
    let caption: String
    let color: Color
    var prominent: Bool = false
    let action: () -> Void

    init(icon: String, code: String?, caption: String, color: Color, prominent: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.code = code
        self.caption = caption
        self.color = color
        self.prominent = prominent
        self.action = action
    }

    private var label: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                if let code {
                    Text(code).fontWeight(.bold)
                }
            }
            Text(caption).font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    var body: some View {
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .tint(color)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .tint(color)
        }
    }
}
