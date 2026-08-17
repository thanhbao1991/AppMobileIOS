import SwiftUI
import UIKit

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
    @State private var copiedFeedback = false

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
            VStack(spacing: 14) {
                if let errorText {
                    Text(errorText).foregroundColor(.dangerColor).font(.footnote)
                }

                DetailCard {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.brandPrimary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.tenKhachHangText?.isEmpty == false ? d.tenKhachHangText! : (d.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                                .font(.title3.bold())
                            if let sdt = d.soDienThoaiText, !sdt.isEmpty { phoneRow(sdt) }
                        }
                        Spacer()
                    }
                    if let dc = d.diaChiText, !dc.isEmpty { iconRow("location.fill", dc) }
                    if let gc = d.ghiChu, !gc.isEmpty { iconRow("note.text", gc) }
                }

                if let chiTiet = d.chiTietHoaDons, !chiTiet.isEmpty {
                    DetailCard {
                        HStack {
                            Label("Món", systemImage: "cup.and.saucer.fill").font(.headline)
                            Spacer()
                            Text("\(chiTiet.reduce(0) { $0 + $1.soLuong }) ly")
                                .font(.caption.bold())
                                .foregroundColor(.brandPrimary)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.brandPrimary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        ForEach(Array(chiTiet.enumerated()), id: \.element.id) { index, ct in
                            if index > 0 { Divider() }
                            itemRow(ct)
                        }
                    }
                }

                DetailCard(tint: (d.tongNoKhachHang ?? 0) > 0 ? .dangerColor : nil) {
                    infoRow("Tổng tiền", HoaDonFormatting.money(d.tongTien))
                    if d.giamGia > 0 { infoRow("Giảm giá", HoaDonFormatting.money(d.giamGia)) }
                    infoRow("Thành tiền", HoaDonFormatting.money(d.thanhTien))
                    infoRow("Đã thu", HoaDonFormatting.money(d.daThu))
                    Divider()
                    HStack {
                        Text("CÒN LẠI").font(.caption.bold()).foregroundColor(.textMuted)
                        Spacer()
                        Text(HoaDonFormatting.money(d.conLai))
                            .font(.title3.bold())
                            .foregroundColor(d.conLai > 0 ? .dangerColor : .successColor)
                    }
                    // "Nợ đơn khác" (không phải "Tổng nợ khách") vì con số này CHỈ TÍNH các đơn khác
                    // của cùng khách — KHÔNG gồm "Còn lại" của chính đơn đang xem (xem
                    // HoaDonQueryService.GetByIdAsync, subquery loại trừ "AND h.Id != @id"). Nhãn cũ
                    // dễ hiểu lầm là đã gộp.
                    if let no = d.tongNoKhachHang, no != 0 { infoRow("Nợ đơn khác", HoaDonFormatting.money(no)) }
                    // Khách có nợ đơn khác > 0 → cộng sẵn "Tổng cộng" (Còn lại + Nợ đơn khác) để nhân
                    // viên khỏi cộng tay khi thu tiền khách tại quầy/ship.
                    if let no = d.tongNoKhachHang, no > 0 {
                        Divider()
                        HStack {
                            Text("TỔNG CỘNG").font(.caption.bold()).foregroundColor(.dangerColor)
                            Spacer()
                            Text(HoaDonFormatting.money(d.conLai + no))
                                .font(.title3.bold())
                                .foregroundColor(.dangerColor)
                        }
                    }
                }

                actionButtons(d)
            }
            .padding()
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
    }

    private func itemRow(_ ct: ChiTietHoaDonResponseDto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(ct.soLuong)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.brandPrimary))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ct.tenSanPham)\(bienTheSuffix(ct.tenBienThe))").font(.subheadline.bold())
                if let note = ct.noteText, !note.isEmpty {
                    Text(note).font(.caption).italic().foregroundColor(.warningColor)
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(ct.donGia * Double(ct.soLuong)))
                .font(.subheadline.bold())
        }
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
        let twoColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

        return VStack(spacing: 10) {
            ActionButtonView(
                icon: copiedFeedback ? "checkmark" : "doc.on.doc", code: nil,
                caption: copiedFeedback ? "Đã copy" : "Gửi Bill", color: .brandPrimary
            ) {
                copyBillImage(d)
            }

            if d.conLai > 0 {
                HStack(spacing: 10) {
                    ActionButtonView(icon: "banknote", code: "F1", caption: "Tiền mặt", color: .successColor, prominent: true) {
                        pendingAction = .tienMat
                    }
                    ActionButtonView(icon: "creditcard", code: "F4", caption: "Chuyển khoản", color: .brandPrimary, prominent: true) {
                        pendingAction = .chuyenKhoan
                    }
                }
            }

            LazyVGrid(columns: twoColumns, spacing: 10) {
                if d.conLai <= 0 {
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
        return Group {
            if let url = URL(string: "tel:\(digits)") {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill").font(.caption2)
                        Text(sdt)
                    }
                    .foregroundColor(.brandPrimary)
                }
            } else {
                Text(sdt).foregroundColor(.textMuted)
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

    /// Dòng phụ trong card khách hàng (địa chỉ/ghi chú) — icon nhỏ bên trái thay vì nhãn chữ, gọn hơn.
    private func iconRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundColor(.textMuted).frame(width: 14)
            Text(text).font(.subheadline).foregroundColor(.textMuted)
            Spacer()
        }
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

    /// Render chi tiết hoá đơn thành ảnh, copy vào clipboard để dán thẳng vào chat Zalo/Facebook —
    /// khớp cách "Gửi Bill Nợ" bên CongNoListView, dùng ImageRenderer để vẽ hết nội dung kể cả phần
    /// đang cuộn ngoài viewport.
    private func copyBillImage(_ d: HoaDonDetailDto) {
        let content = BillDetailSnapshotView(d: d)
            .frame(width: UIScreen.main.bounds.width)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        guard let uiImage = renderer.uiImage else { return }
        UIPasteboard.general.image = uiImage

        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedFeedback = false
        }
    }
}

/// Layout riêng để render ảnh "Gửi Bill" — nền trắng cố định để ảnh dán vào chat luôn đọc được bất
/// kể theme máy, độc lập với ScrollView (không rasterize hết nội dung ngoài viewport).
private struct BillDetailSnapshotView: View {
    let d: HoaDonDetailDto

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(d.tenKhachHangText?.isEmpty == false ? d.tenKhachHangText! : (d.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                .font(.title3.bold())
            if let sdt = d.soDienThoaiText, !sdt.isEmpty {
                Text(sdt).font(.subheadline).foregroundColor(.textMuted)
            }
            if let dc = d.diaChiText, !dc.isEmpty {
                Text(dc).font(.subheadline).foregroundColor(.textMuted)
            }

            Divider()

            ForEach(d.chiTietHoaDons ?? [], id: \.id) { ct in
                HStack {
                    Text("\(ct.soLuong)x \(ct.tenSanPham)")
                    Spacer()
                    Text(HoaDonFormatting.money(ct.donGia * Double(ct.soLuong)))
                }
                .font(.subheadline)
            }

            Divider()

            HStack {
                Text("Thành tiền").foregroundColor(.textMuted)
                Spacer()
                Text(HoaDonFormatting.money(d.thanhTien)).font(.subheadline.bold())
            }
            HStack {
                Text("Còn lại").foregroundColor(.textMuted)
                Spacer()
                Text(HoaDonFormatting.money(d.conLai))
                    .font(.title3.bold())
                    .foregroundColor(d.conLai > 0 ? .dangerColor : .successColor)
            }
            if let no = d.tongNoKhachHang, no > 0 {
                HStack {
                    Text("Nợ đơn khác").foregroundColor(.textMuted)
                    Spacer()
                    Text(HoaDonFormatting.money(no))
                }
                HStack {
                    Text("TỔNG CỘNG").font(.subheadline.bold()).foregroundColor(.dangerColor)
                    Spacer()
                    Text(HoaDonFormatting.money(d.conLai + no))
                        .font(.title3.bold())
                        .foregroundColor(.dangerColor)
                }
            }
        }
        .padding(16)
        .background(Color.white)
    }
}

/// Khối card bo góc dùng cho từng nhóm thông tin trong các màn "chi tiết" (HoaDonDetailView,
/// ThanhToanDetailView) — thay cho danh sách phẳng ngăn cách bằng Divider trước đây, phân tách rõ
/// ràng hơn. Internal để dùng chung xuyên suốt app.
struct DetailCard<Content: View>: View {
    let content: Content
    /// Khi set (vd .dangerColor cho đơn có nợ), nền card đổi sang pastel màu này thay vì màu xám
    /// mặc định — nhấn mạnh trực quan ngay trên card, không cần đọc số.
    var tint: Color?

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .background(tint?.pastelBackground() ?? Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Dùng chung cho mọi màn "chi tiết" có action button (HoaDonDetailView, ThanhToanDetailView) —
/// khớp icon + mã tắt + caption 1 kiểu xuyên suốt app.
struct ActionButtonView: View {
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
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(color)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(color)
        }
    }
}
