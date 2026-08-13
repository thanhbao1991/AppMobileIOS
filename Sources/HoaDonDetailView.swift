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
                    if let sdt = d.soDienThoaiText, !sdt.isEmpty { infoRow("SĐT", sdt) }
                    if let dc = d.diaChiText, !dc.isEmpty { infoRow("Địa chỉ", dc) }
                    infoRow("Phân loại", HoaDonFormatting.phanLoaiLabel(d.phanLoai))
                    if d.phanLoai == "Ship" {
                        infoRow("Shipper", d.nguoiShip?.isEmpty == false ? d.nguoiShip! : "Chưa gán")
                    }
                    if let gc = d.ghiChu, !gc.isEmpty { infoRow("Ghi chú", gc) }
                }

                Divider()

                if let chiTiet = d.chiTietHoaDons, !chiTiet.isEmpty {
                    Text("Món").font(.headline)
                    ForEach(chiTiet) { ct in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(ct.tenSanPham)\(ct.tenBienThe.map { " (\($0))" } ?? "")")
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
                infoRow("Còn lại", HoaDonFormatting.money(d.conLai))
                if let no = d.tongNoKhachHang, no != 0 { infoRow("Tổng nợ khách", HoaDonFormatting.money(no)) }

                Divider()
                actionButtons(d)
            }
            .padding()
        }
        .disabled(busy)
        .overlay { if busy { ProgressView() } }
    }

    private func actionButtons(_ d: HoaDonDetailDto) -> some View {
        VStack(spacing: 10) {
            if d.conLai > 0 {
                HStack(spacing: 10) {
                    Button("Thu tiền mặt") { Task { await thuTien(isCash: true, d: d) } }
                        .buttonStyle(.borderedProminent)
                    Button("Thu chuyển khoản") { Task { await thuTien(isCash: false, d: d) } }
                        .buttonStyle(.bordered)
                }
                Button("Ghi nợ") { Task { await run { await APIClient.shared.ghiNo(hoaDonId: hoaDonId) } } }
                    .buttonStyle(.bordered)
                    .tint(.dangerColor)
            } else {
                Button("Hoàn tác (chưa thu)") { Task { await run { await APIClient.shared.rollback(hoaDonId: hoaDonId) } } }
                    .buttonStyle(.bordered)
            }

            if d.phanLoai == "Ship" {
                Button("Gán shipper") {
                    shipperName = d.nguoiShip ?? ""
                    showGanShipperSheet = true
                }
                .buttonStyle(.bordered)
            }

            Button("Xoá hoá đơn", role: .destructive) {
                Task { await run { await APIClient.shared.delete(hoaDonId: hoaDonId) } }
            }
        }
        .frame(maxWidth: .infinity)
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
