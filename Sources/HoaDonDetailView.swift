import SwiftUI

struct HoaDonDetailView: View {
    let hoaDonId: String
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: HoaDonDetailDto?
    @State private var loading = true
    @State private var busy = false
    @State private var errorText: String?
    @State private var showGanShipperSheet = false
    @State private var shipperName = ""

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
        .sheet(isPresented: $showGanShipperSheet) {
            ganShipperSheet
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
                    Text("Món").font(.headline)
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
                if let no = d.tongNoKhachHang, no != 0 { infoRow("Tổng nợ khách", HoaDonFormatting.money(no)) }

                Divider()
                actionButtons(d)
            }
            .padding()
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
    }

    /// Thứ tự và label khớp WrapPanel "Action buttons" trong HoaDonTabControl.xaml (Desktop):
    /// F1 Tiền mặt, F4 Chuyển khoản, Esc Ship/Hoàn tất (gán shipper), F12 Ghi nợ, Del Xoá đơn.
    /// (F2/F3/F9 in/copy ảnh không áp dụng cho mobile.) Ghi nợ chỉ hiện khi CHƯA ghi nợ — khớp
    /// guard "Hoá đơn đã ghi nợ rồi!" trong GhiNoAsync (Desktop Actions.cs); thiếu check này khiến
    /// đơn mở từ tab Công nợ (đã có NgayNo) vẫn hiện nút Ghi nợ vô nghĩa.
    private func actionButtons(_ d: HoaDonDetailDto) -> some View {
        let chuaGhiNo = d.ngayNo?.isEmpty ?? true
        return VStack(spacing: 10) {
            if d.conLai > 0 {
                HStack(spacing: 10) {
                    Button("Tiền mặt") { Task { await thuTien(isCash: true, d: d) } }
                        .buttonStyle(.borderedProminent)
                    Button("Chuyển khoản") { Task { await thuTien(isCash: false, d: d) } }
                        .buttonStyle(.bordered)
                }
            } else {
                Button("Hoàn tác thanh toán") { Task { await run { await APIClient.shared.rollback(hoaDonId: hoaDonId) } } }
                    .buttonStyle(.bordered)
            }

            if d.phanLoai == "Ship" {
                Button("Ship / Hoàn tất") {
                    shipperName = d.nguoiShip ?? ""
                    showGanShipperSheet = true
                }
                .buttonStyle(.bordered)
            }

            if d.conLai > 0 && chuaGhiNo {
                Button("Ghi nợ") { Task { await run { await APIClient.shared.ghiNo(hoaDonId: hoaDonId) } } }
                    .buttonStyle(.bordered)
                    .tint(.dangerColor)
            }

            Button("Xoá đơn", role: .destructive) {
                Task { await run { await APIClient.shared.delete(hoaDonId: hoaDonId) } }
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

    private var ganShipperSheet: some View {
        NavigationStack {
            Form {
                TextField("Tên shipper", text: $shipperName)
            }
            .navigationTitle("Gán shipper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { showGanShipperSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        showGanShipperSheet = false
                        Task { await run { await APIClient.shared.ganShipper(hoaDonId: hoaDonId, nguoiShip: shipperName) } } }
                    .disabled(shipperName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(180)])
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

    private func thuTien(isCash: Bool, d: HoaDonDetailDto) async {
        await run {
            await APIClient.shared.thuTien(
                hoaDonId: hoaDonId, isCash: isCash, soTien: d.conLai,
                ten: d.tenKhachHangText ?? "Khách lẻ", khachHangId: d.khachHangId
            )
        }
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
