import SwiftUI

/// Sửa hoá đơn đã có — tái dùng ProductPickerPanel/DraftChiTiet từ HoaDonCreateFormView. Khác tạo
/// mới: KHÔNG cho đổi khách hàng đã gán (chỉ sửa món/giảm giá/ghi chú/bàn) — đổi khách hàng qua
/// form sửa dễ gây nhầm công nợ/điểm giữa 2 khách, không phải nhu cầu thực tế của "sửa lỗi nhập
/// nhầm tại chỗ" (khớp lý do PUT /api/HoaDon/{id} chỉ mở cho đơn hôm nay hoặc chưa thu tiền — xem
/// guard trong HoaDonCrudService.UpdateAsync).
struct HoaDonEditFormView: View {
    let hoaDonId: String
    let onUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var loadError: String?
    @State private var detail: HoaDonDetailDto?

    @State private var phanLoai = ""
    @State private var tenBan = ""
    @State private var items: [DraftChiTiet] = []
    @State private var pickerTarget: PickerTarget? = nil
    @State private var sanPhamList: [SanPhamDto] = []
    @State private var toppingList: [ToppingDto] = []
    @State private var giaRiengList: [KhachHangGiaBanDto] = []
    @State private var unmatchedNames: [String] = []

    @State private var giamGia: Double = 0
    @State private var giamGiaManual = true
    @State private var ghiChuDon = ""

    @State private var saving = false
    @State private var errorMessage: String?

    private struct PickerTarget: Identifiable {
        let index: Int?
        var id: String { index.map(String.init) ?? "new" }
    }

    private let banSlots = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "13", "Sân 1", "Sân 2"]
    private let discountPresets: [Double] = [0, 10_000, 20_000, 30_000, 40_000, 50_000, 60_000, 70_000, 80_000, 90_000, 100_000]

    private var tongTien: Double { items.reduce(0) { $0 + $1.thanhTien } }
    private var thanhTien: Double { max(0, tongTien - giamGia) }
    private var tongLy: Int { items.reduce(0) { $0 + $1.soLuong } }

    private var giaRiengMap: [String: Double] {
        guard let khId = detail?.khachHangId else { return [:] }
        var map: [String: Double] = [:]
        for g in giaRiengList where g.khachHangId == khId { map[g.sanPhamBienTheId] = g.giaBan }
        return map
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if let loadError {
                    Text(loadError).foregroundColor(.dangerColor)
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            if let errorMessage {
                                Text(errorMessage).foregroundColor(.dangerColor).font(.footnote)
                            }
                            if !unmatchedNames.isEmpty {
                                Text("Không khớp được món trong catalog hiện tại, giữ nguyên không sửa được:\n\(unmatchedNames.joined(separator: ", "))")
                                    .font(.footnote).foregroundColor(.warningColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.warningColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            khachHangReadonlyCard
                            if phanLoai == "Tại Chỗ" { tenBanCard }
                            monCard
                            summaryCard
                            discountCard
                            ghiChuCard
                        }
                        .padding()
                    }
                    .disabled(saving)
                    .overlay { if saving { ProgressView() } }
                }
            }
            .navigationTitle("Sửa hoá đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.disabled(saving)
                }
                if detail != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Đang lưu..." : "Lưu") { Task { await save() } }
                            .disabled(saving || items.isEmpty)
                    }
                }
            }
        }
        .task { await load() }
    }

    // ══════════════════════════════════════════════

    private var khachHangReadonlyCard: some View {
        DetailCard {
            Label("Khách hàng", systemImage: "person.fill").font(.headline)
            if let d = detail {
                Text(d.tenKhachHangText?.isEmpty == false ? d.tenKhachHangText! : (d.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                    .font(.subheadline.bold())
                if let sdt = d.soDienThoaiText, !sdt.isEmpty {
                    Text(sdt).font(.caption).foregroundColor(.textMuted)
                }
            }
            Text("Không đổi được khách hàng khi sửa đơn — xoá đơn và tạo lại nếu gán nhầm khách.")
                .font(.caption2).foregroundColor(.textMuted)
        }
    }

    private var tenBanCard: some View {
        DetailCard {
            Text("Số bàn").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(banSlots, id: \.self) { v in
                        Button(v) { tenBan = v }
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(v == tenBan ? Color.brandPrimary : Color.textMuted.opacity(0.12))
                            .foregroundColor(v == tenBan ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var monCard: some View {
        DetailCard {
            HStack {
                Label("Món", systemImage: "cup.and.saucer.fill").font(.headline)
                Spacer()
                if tongLy > 0 {
                    Text("\(tongLy) ly")
                        .font(.caption.bold()).foregroundColor(.brandPrimary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.brandPrimary.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if items.isEmpty {
                Text("Chưa có món nào").foregroundColor(.textMuted).font(.subheadline)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    draftItemRow(item, index: index)
                }
            }

            if let pickerTarget {
                Divider()
                ProductPickerPanel(
                    sanPhamList: sanPhamList,
                    toppingList: toppingList,
                    giaRiengMap: giaRiengMap,
                    editingItem: pickerTarget.index.map { items[$0] },
                    autoFocusSearchOnAppear: false,
                    onAdd: { draft in
                        items.append(draft)
                    },
                    onSaveEdit: pickerTarget.index.map { idx -> (DraftChiTiet) -> Void in
                        { draft in items[idx] = draft }
                    },
                    onClose: { self.pickerTarget = nil }
                )
                .id(pickerTarget.id)
            } else {
                Button {
                    pickerTarget = PickerTarget(index: nil)
                } label: {
                    Label("Thêm món", systemImage: "plus.circle")
                }
                .font(.subheadline)
            }
        }
    }

    private func draftItemRow(_ item: DraftChiTiet, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(item.soLuong)")
                .font(.caption.bold()).foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.brandPrimary))
            VStack(alignment: .leading, spacing: 2) {
                Text(["", "Mặc định", "Size Chuẩn", "Chuẩn"].contains(item.tenBienThe)
                     ? item.tenSanPham : "\(item.tenSanPham) (\(item.tenBienThe))")
                    .font(.subheadline.bold())
                if !item.toppingText.isEmpty {
                    Text(item.toppingText).font(.caption).foregroundColor(.brandPrimary)
                }
                if !item.noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(item.noteText).font(.caption).italic().foregroundColor(.orange)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(HoaDonFormatting.money(item.thanhTien))
                    .font(.subheadline.bold())
                Button {
                    items.remove(at: index)
                } label: {
                    Image(systemName: "trash").foregroundColor(.dangerColor).font(.caption)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pickerTarget = PickerTarget(index: index) }
    }

    private var discountCard: some View {
        DetailCard {
            Label("Giảm giá", systemImage: "tag.fill").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(discountPresets, id: \.self) { v in
                        let active = giamGia == v
                        Button(v == 0 ? "Không" : HoaDonFormatting.moneyShort(v)) {
                            giamGia = min(v, tongTien)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(active ? Color.brandPrimary : Color.textMuted.opacity(0.12))
                        .foregroundColor(active ? .white : .primary)
                        .clipShape(Capsule())
                    }
                }
            }
            HStack {
                Text("Tuỳ chỉnh").font(.subheadline)
                Spacer()
                TextField("0", value: $giamGia, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                Text("đ")
            }
        }
    }

    private var ghiChuCard: some View {
        DetailCard {
            Label("Ghi chú đơn", systemImage: "note.text").font(.headline)
            TextField("Ghi chú...", text: $ghiChuDon)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var summaryCard: some View {
        DetailCard {
            HStack {
                Text("Tổng tiền").foregroundColor(.textMuted)
                Spacer()
                Text(HoaDonFormatting.money(tongTien))
            }
            .font(.subheadline)
            if giamGia > 0 {
                HStack {
                    Text("Giảm giá").foregroundColor(.textMuted)
                    Spacer()
                    Text("-\(HoaDonFormatting.money(giamGia))")
                }
                .font(.subheadline)
            }
            Divider()
            HStack {
                Text("THÀNH TIỀN").font(.caption.bold()).foregroundColor(.textMuted)
                Spacer()
                Text(HoaDonFormatting.money(thanhTien)).font(.title3.bold())
            }
        }
    }

    // ══════════════════════════════════════════════
    // Logic
    // ══════════════════════════════════════════════

    private func load() async {
        async let d = APIClient.shared.getHoaDonDetail(hoaDonId)
        async let sp = APIClient.shared.getSanPhamList()
        async let tp = APIClient.shared.getToppingList()
        async let gr = APIClient.shared.getKhachHangGiaBanList()
        let (detailResult, spResult, tpResult, grResult) = await (d, sp, tp, gr)

        guard let detailResult else {
            loadError = "Không tải được hoá đơn."
            loading = false
            return
        }
        detail = detailResult
        sanPhamList = spResult
        toppingList = tpResult
        giaRiengList = grResult

        phanLoai = detailResult.phanLoai ?? ""
        tenBan = detailResult.tenBan ?? ""
        giamGia = detailResult.giamGia
        ghiChuDon = detailResult.ghiChu ?? ""

        var unmatched: [String] = []
        items = (detailResult.chiTietHoaDons ?? []).compactMap { ct -> DraftChiTiet? in
            guard let sp = spResult.first(where: { $0.ten == ct.tenSanPham }) else {
                unmatched.append(ct.tenSanPham)
                return nil
            }
            let bt = sp.bienThe.first(where: { $0.tenBienThe == ct.tenBienThe }) ?? sp.bienThe.first(where: { $0.macDinh }) ?? sp.bienThe.first
            guard let bt else {
                unmatched.append(ct.tenSanPham)
                return nil
            }
            let toppings = parseToppingText(ct.toppingText, catalog: tpResult)
            return DraftChiTiet(
                sanPhamBienTheId: bt.id, tenSanPham: sp.ten, tenBienThe: bt.tenBienThe,
                soLuong: ct.soLuong, donGia: ct.donGia, noteText: ct.noteText ?? "", toppings: toppings
            )
        }
        unmatchedNames = unmatched
        loading = false
    }

    /// toppingText dạng "Trân châu, Thạch x2" (BuildToppingText Desktop) — parse lại theo tên để
    /// khớp toppingId trong catalog hiện tại, vì HoaDonDetailDto không trả thẳng toppingId từng dòng.
    private func parseToppingText(_ text: String?, catalog: [ToppingDto]) -> [DraftTopping] {
        guard let text, !text.isEmpty else { return [] }
        return text.split(separator: ",").compactMap { part -> DraftTopping? in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            var name = trimmed
            var qty = 1
            if let range = trimmed.range(of: #"\s+x(\d+)$"#, options: .regularExpression) {
                name = String(trimmed[trimmed.startIndex..<range.lowerBound])
                qty = Int(trimmed[range].trimmingCharacters(in: CharacterSet(charactersIn: " x"))) ?? 1
            }
            guard let top = catalog.first(where: { $0.ten == name }) else { return nil }
            return DraftTopping(toppingId: top.id, ten: top.ten, gia: top.gia, soLuong: qty)
        }
    }

    private func save() async {
        guard let detail else { return }
        guard !items.isEmpty else { errorMessage = "Chưa có món nào."; return }
        if phanLoai == "Tại Chỗ" && tenBan.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Đơn tại chỗ phải chọn bàn trước khi lưu."
            return
        }
        saving = true
        errorMessage = nil

        let chiTietDtos = items.map { item in
            ChiTietHoaDonCreateDto(
                id: item.id,
                sanPhamBienTheId: item.sanPhamBienTheId,
                soLuong: item.soLuong,
                donGia: item.donGia,
                tenSanPham: item.tenSanPham,
                tenBienThe: item.tenBienThe,
                toppingText: item.toppingText.isEmpty ? nil : item.toppingText,
                noteText: item.noteText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : item.noteText
            )
        }
        let toppingDtos = items.flatMap { item in
            item.toppings.filter { $0.soLuong > 0 }.map { t in
                ChiTietHoaDonToppingCreateDto(chiTietHoaDonId: item.id, toppingId: t.toppingId, ten: t.ten, soLuong: t.soLuong, gia: t.gia)
            }
        }
        let body = HoaDonFullCreateRequest(
            phanLoai: phanLoai,
            tenBan: phanLoai == "Tại Chỗ" ? tenBan.trimmingCharacters(in: .whitespaces) : nil,
            khachHangId: detail.khachHangId,
            tenKhachHangText: detail.tenKhachHangText,
            soDienThoaiText: detail.soDienThoaiText,
            diaChiText: detail.diaChiText,
            ghiChu: ghiChuDon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ghiChuDon,
            giamGia: giamGia,
            chiTietHoaDons: chiTietDtos,
            chiTietHoaDonToppings: toppingDtos
        )

        let result = await APIClient.shared.updateHoaDonFull(id: hoaDonId, body)
        saving = false
        if result.success {
            dismiss()
            onUpdated()
        } else {
            errorMessage = result.message ?? "Sửa hoá đơn thất bại."
        }
    }
}
