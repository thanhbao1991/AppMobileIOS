import SwiftUI

/// Sửa hoá đơn đã có — tái dùng ProductPickerPanel/DraftChiTiet + toàn bộ luồng chọn/sửa/tạo khách
/// hàng từ HoaDonCreateFormView (copy có chủ đích, không tách chung — 2 form khác nhau đủ nhiều chỗ
/// nhỏ nhặt là dễ vỡ nếu ép dùng chung 1 component). Gửi PUT /api/HoaDon/{id} cùng shape body với
/// tạo mới (HoaDonCrudService.UpdateAsync xoá sạch ChiTietHoaDons/Toppings cũ rồi AddAsync lại từ
/// dto — khớp cách Desktop HoaDonEditWindow.Save ghi đè toàn bộ chứ không diff từng dòng).
struct HoaDonEditFormView: View {
    let hoaDonId: String
    let onUpdated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var loadError: String?
    @State private var originalGhiChu: String?

    @State private var phanLoai = ""
    @State private var tenBan = ""
    @State private var items: [DraftChiTiet] = []
    @State private var pickerTarget: PickerTarget? = PickerTarget(index: nil)
    @State private var sanPhamList: [SanPhamDto] = []
    @State private var toppingList: [ToppingDto] = []
    @State private var giaRiengList: [KhachHangGiaBanDto] = []
    @State private var unmatchedNames: [String] = []

    // Khách hàng — copy nguyên luồng từ HoaDonCreateFormView.
    @State private var selectedKhach: KhachHangDto?
    @State private var tenKhach = ""
    @State private var sdt = ""
    @State private var diaChi = ""
    @State private var khachSearchText = ""
    @FocusState private var khachSearchFocused: Bool
    @State private var khachSearchResults: [KhachHangDto] = []
    @State private var khachSearchTask: Task<Void, Never>?
    @State private var khachInfo: KhachHangInfoDto?
    @State private var giaRiengBanner: String?
    @State private var showEditKhachHang = false
    @State private var showNewKhachForm = false
    @State private var newKhachTen = ""
    @State private var newKhachSdt = ""
    @State private var newKhachDiaChi = ""
    @State private var newKhachVoucher = false
    @State private var newKhachSaving = false
    @State private var newKhachError: String?
    @State private var editTen = ""
    @State private var editPhoneRows: [EditContactRow] = []
    @State private var editAddressRows: [EditContactRow] = []
    @State private var editVoucher = false
    @State private var editSaving = false
    @State private var editError: String?

    @State private var giamGia: Double = 0

    @State private var saving = false
    @State private var errorMessage: String?

    private struct PickerTarget: Identifiable {
        let index: Int?
        var id: String { index.map(String.init) ?? "new" }
    }

    private struct EditContactRow: Identifiable {
        var id: String
        var value: String
    }

    private let banSlots = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "13", "Sân 1", "Sân 2"]
    private let discountPresets: [Double] = [0, 10_000, 20_000, 30_000, 40_000, 50_000, 60_000, 70_000, 80_000, 90_000, 100_000]

    private var tongTien: Double { items.reduce(0) { $0 + $1.thanhTien } }
    private var thanhTien: Double { max(0, tongTien - giamGia) }
    private var tongLy: Int { items.reduce(0) { $0 + $1.soLuong } }

    private var giaRiengMap: [String: Double] {
        guard let kh = selectedKhach else { return [:] }
        var map: [String: Double] = [:]
        for g in giaRiengList where g.khachHangId == kh.id { map[g.sanPhamBienTheId] = g.giaBan }
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
                            if let giaRiengBanner {
                                Text("Đã áp giá riêng:\n\(giaRiengBanner)")
                                    .font(.footnote).foregroundColor(.brandPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.brandPrimary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            if !unmatchedNames.isEmpty {
                                Text("Không khớp được món trong catalog hiện tại, giữ nguyên không sửa được:\n\(unmatchedNames.joined(separator: ", "))")
                                    .font(.footnote).foregroundColor(.warningColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color.warningColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            if phanLoai == "Tại Chỗ" { tenBanCard }
                            khachHangCard
                            monCard
                            summaryCard
                            discountCard
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu") { Task { await save() } }
                        .disabled(saving || items.isEmpty || loading || loadError != nil)
                }
            }
        }
        .task { await load() }
    }

    // ══════════════════════════════════════════════
    // Bàn
    // ══════════════════════════════════════════════

    private var tenBanCard: some View {
        DetailCard {
            Text("Số bàn").font(.headline)
            chipsRow(banSlots, active: tenBan) { tenBan = $0 }
        }
    }

    // ══════════════════════════════════════════════
    // Khách hàng (copy 1:1 từ HoaDonCreateFormView)
    // ══════════════════════════════════════════════

    private var khachHangCard: some View {
        DetailCard {
            HStack {
                Label("Khách hàng", systemImage: "person.fill").font(.headline)
                Spacer()
                if selectedKhach != nil && !showEditKhachHang {
                    Button("Sửa") { beginEditKhach() }.font(.caption)
                    Spacer().frame(width: 20)
                    Button("Bỏ chọn") { clearKhach() }.font(.caption)
                }
            }

            if selectedKhach == nil {
                if showNewKhachForm {
                    newKhachForm
                } else {
                    TextField("Tìm khách theo tên/SĐT...", text: $khachSearchText)
                        .textFieldStyle(.roundedBorder)
                        .focused($khachSearchFocused)
                        .onChange(of: khachSearchText) { q in scheduleKhachSearch(q) }

                    if !khachSearchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(khachSearchResults) { kh in
                                Button { selectKhach(kh) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(kh.ten).font(.subheadline.bold())
                                            if let dt = kh.phones.first?.soDienThoai {
                                                Text(dt).font(.caption).foregroundColor(.textMuted)
                                            }
                                            if let dc = kh.addresses.first?.diaChi, !dc.isEmpty {
                                                Text(dc).font(.caption).foregroundColor(.textMuted)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }

                    Button { showNewKhachForm = true } label: {
                        Label("Khách mới", systemImage: "person.badge.plus")
                    }
                    .font(.subheadline)
                }
            } else if !showEditKhachHang {
                selectedKhachInfo(selectedKhach!)
            }

            if selectedKhach != nil && showEditKhachHang {
                editKhachForm
            }
        }
    }

    private func fieldLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .foregroundColor(.textMuted)
    }

    private var editKhachForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Tên khách", icon: "person")
            TextField("Tên khách", text: $editTen)
                .textFieldStyle(.roundedBorder)

            fieldLabel("Số điện thoại", icon: "phone")
            contactRowsEditor($editPhoneRows, placeholder: "Số điện thoại", keyboard: .phonePad)
            Button {
                editPhoneRows.append(EditContactRow(id: UUID().uuidString, value: ""))
            } label: {
                Label("Thêm SĐT", systemImage: "plus")
            }.font(.caption)

            fieldLabel("Địa chỉ", icon: "location")
            contactRowsEditor($editAddressRows, placeholder: "Địa chỉ", keyboard: .default)
            Button {
                editAddressRows.append(EditContactRow(id: UUID().uuidString, value: ""))
            } label: {
                Label("Thêm địa chỉ", systemImage: "plus")
            }.font(.caption)

            Toggle("Được nhận voucher", isOn: $editVoucher)
                .font(.subheadline)

            if let editError {
                Text(editError).font(.caption).foregroundColor(.dangerColor)
            }

            HStack(spacing: 16) {
                Button(editSaving ? "Đang lưu..." : "Lưu") { Task { await saveEditKhach() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(editSaving)
                Button("Huỷ") { showEditKhachHang = false }
                    .foregroundColor(.textMuted)
                    .disabled(editSaving)
            }
            .font(.subheadline.bold())
        }
    }

    private func contactRowsEditor(_ rows: Binding<[EditContactRow]>, placeholder: String, keyboard: UIKeyboardType) -> some View {
        VStack(spacing: 6) {
            ForEach(rows.wrappedValue.indices, id: \.self) { i in
                HStack {
                    TextField(placeholder, text: rows[i].value)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(keyboard)
                    Button { rows.wrappedValue.remove(at: i) } label: {
                        Image(systemName: "trash").foregroundColor(.dangerColor)
                    }
                }
            }
        }
    }

    private func selectedKhachInfo(_ kh: KhachHangDto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kh.ten).font(.subheadline.bold())
                if let info = khachInfo, info.tongNo > 0 {
                    infoBadge("Nợ \(HoaDonFormatting.money(info.tongNo))", color: .dangerColor)
                }
                Spacer()
                if let info = khachInfo, !info.duocNhanVoucher {
                    infoBadge("Không tích điểm", color: .textMuted)
                }
            }

            if kh.phones.count > 1 {
                chipsRow(kh.phones.map(\.soDienThoai), active: sdt) { sdt = $0 }
            }
            if kh.addresses.count > 1 {
                chipsRow(kh.addresses.map(\.diaChi), active: diaChi) { diaChi = $0 }
            }

            if let info = khachInfo {
                khachInfoBadges(info)
                if !info.monGanDay.isEmpty || !info.monHayMua.isEmpty {
                    favoriteChips(info)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chipsRow(_ values: [String], active: String, onSelect: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { v in
                    Button(v) { onSelect(v) }
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(v == active ? Color.brandPrimary : Color.textMuted.opacity(0.12))
                        .foregroundColor(v == active ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func khachInfoBadges(_ info: KhachHangInfoDto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if info.soDu > 0 {
                infoBadge("Ví \(HoaDonFormatting.money(info.soDu))", color: .brandPrimary)
            }
            if info.donKhac > 0 {
                infoBadge("Đơn khác chưa trả \(HoaDonFormatting.money(info.donKhac))", color: .warningColor)
            }
            HStack(spacing: 8) {
                if info.duocNhanVoucher {
                    if info.daNhanVoucher {
                        infoBadge("Đã nhận voucher", color: .successColor)
                    } else if info.diemThangTruoc >= 3000 {
                        let soVoucher = info.diemThangTruoc / 3000
                        infoBadge("Voucher \(HoaDonFormatting.money(Double(soVoucher) * 10000))", color: .pinkColor)
                    }
                }
                if info.diemThangNay > 0 || info.diemThangTruoc > 0 {
                    Text("\(HoaDonFormatting.diemDisplay(info.diemThangNay)) th.này · \(HoaDonFormatting.diemDisplay(info.diemThangTruoc)) th.trước")
                        .font(.caption2).foregroundColor(.textMuted)
                }
            }
        }
    }

    private func infoBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func favoriteChips(_ info: KhachHangInfoDto) -> some View {
        let all = (info.monGanDay + info.monHayMua).reduce(into: [KhachHangFavoriteItemDto]()) { acc, item in
            if !acc.contains(where: { $0.id == item.id }) { acc.append(item) }
        }
        return VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(all) { fav in
                        Button {
                            quickAddFavorite(fav)
                        } label: {
                            Text(["", "Mặc định", "Size Chuẩn", "Chuẩn"].contains(fav.tenBienThe) ? fav.tenSanPham : "\(fav.tenSanPham) (\(fav.tenBienThe))")
                                .font(.caption.bold())
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.successColor.opacity(0.12))
                                .foregroundColor(.successColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var newKhachForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Tên khách", text: $newKhachTen).textFieldStyle(.roundedBorder)
            TextField("Số điện thoại (không bắt buộc)", text: $newKhachSdt).textFieldStyle(.roundedBorder).keyboardType(.phonePad)
            TextField("Địa chỉ", text: $newKhachDiaChi).textFieldStyle(.roundedBorder)
            Toggle("Được tích điểm/voucher", isOn: $newKhachVoucher).font(.caption)
            if let newKhachError {
                Text(newKhachError).foregroundColor(.dangerColor).font(.caption)
            }
            HStack {
                Button("Huỷ") {
                    showNewKhachForm = false
                    newKhachTen = ""; newKhachSdt = ""; newKhachDiaChi = ""; newKhachVoucher = false
                    newKhachError = nil
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(newKhachSaving ? "Đang tạo..." : "Tạo khách") { Task { await createNewKhach() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newKhachSaving)
            }
        }
    }

    // ══════════════════════════════════════════════
    // Món
    // ══════════════════════════════════════════════

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

            // Ô tìm món luôn hiện sẵn (không ẩn sau nút "Thêm món") — khớp form Tạo đơn.
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
                    onClose: { self.pickerTarget = PickerTarget(index: nil) }
                )
                .id(pickerTarget.id)
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
                if giaRiengMap[item.sanPhamBienTheId] == item.donGia {
                    Text("Giá riêng").font(.caption2.bold()).foregroundColor(.pinkColor)
                }
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

    // ══════════════════════════════════════════════
    // Giảm giá + tổng kết
    // ══════════════════════════════════════════════

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
        sanPhamList = spResult
        toppingList = tpResult
        giaRiengList = grResult

        phanLoai = detailResult.phanLoai ?? ""
        tenBan = detailResult.tenBan ?? ""
        giamGia = detailResult.giamGia
        originalGhiChu = detailResult.ghiChu
        tenKhach = detailResult.tenKhachHangText ?? ""
        sdt = detailResult.soDienThoaiText ?? ""
        diaChi = detailResult.diaChiText ?? ""

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

        if let khId = detailResult.khachHangId, let kh = await APIClient.shared.getKhachHangById(khId) {
            selectKhach(kh)
        }

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

    private func scheduleKhachSearch(_ q: String) {
        khachSearchTask?.cancel()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            khachSearchResults = []
            return
        }
        khachSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let result = await APIClient.shared.searchKhachHang(q)
            guard !Task.isCancelled else { return }
            khachSearchResults = result
        }
    }

    private func selectKhach(_ kh: KhachHangDto) {
        selectedKhach = kh
        showEditKhachHang = false
        tenKhach = kh.ten
        sdt = kh.phones.first(where: { $0.isDefault })?.soDienThoai ?? kh.phones.first?.soDienThoai ?? sdt
        diaChi = kh.addresses.first(where: { $0.isDefault })?.diaChi ?? kh.addresses.first?.diaChi ?? diaChi
        khachSearchText = ""
        khachSearchResults = []
        khachInfo = nil
        applyGiaRiengToExistingItems()
        Task { khachInfo = await APIClient.shared.getKhachHangInfo(khachHangId: kh.id) }
    }

    private func clearKhach() {
        selectedKhach = nil
        showEditKhachHang = false
        khachInfo = nil
        tenKhach = ""
        sdt = ""
        diaChi = ""
    }

    private func beginEditKhach() {
        guard let kh = selectedKhach else { return }
        editTen = kh.ten
        editVoucher = kh.duocNhanVoucher
        editPhoneRows = kh.phones.map { EditContactRow(id: $0.id, value: $0.soDienThoai) }
        editAddressRows = kh.addresses.map { EditContactRow(id: $0.id, value: $0.diaChi) }
        editError = nil
        showEditKhachHang = true
    }

    private func saveEditKhach() async {
        guard let kh = selectedKhach else { return }
        let tenMoi = editTen.trimmingCharacters(in: .whitespaces)
        guard !tenMoi.isEmpty else { editError = "Tên khách không được để trống."; return }

        editSaving = true
        editError = nil

        let phones = editPhoneRows.enumerated().compactMap { i, row -> KhachHangPhoneDto? in
            let v = row.value.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty else { return nil }
            return KhachHangPhoneDto(id: row.id, soDienThoai: v, isDefault: i == 0)
        }
        let addresses = editAddressRows.enumerated().compactMap { i, row -> KhachHangAddressDto? in
            let v = row.value.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty else { return nil }
            return KhachHangAddressDto(id: row.id, diaChi: v, isDefault: i == 0)
        }

        let previousPhoneId = kh.phones.first(where: { $0.soDienThoai == sdt })?.id
        let previousAddrId  = kh.addresses.first(where: { $0.diaChi == diaChi })?.id

        let payload = KhachHangDto(
            id: kh.id, ten: tenMoi, soDu: kh.soDu, duocNhanVoucher: editVoucher,
            phones: phones, addresses: addresses, facebookThreadId: kh.facebookThreadId
        )
        let result = await APIClient.shared.updateKhachHang(payload)
        editSaving = false
        if result.success, let updated = result.khach {
            selectedKhach = updated
            tenKhach = updated.ten
            sdt = updated.phones.first(where: { $0.id == previousPhoneId })?.soDienThoai
                ?? updated.phones.first?.soDienThoai ?? ""
            diaChi = updated.addresses.first(where: { $0.id == previousAddrId })?.diaChi
                ?? updated.addresses.first?.diaChi ?? ""
            showEditKhachHang = false
            applyGiaRiengToExistingItems()
        } else {
            editError = result.message ?? "Lưu thất bại."
        }
    }

    private func applyGiaRiengToExistingItems() {
        let map = giaRiengMap
        guard !map.isEmpty else { return }
        var changed: [String] = []
        for i in items.indices {
            if let gia = map[items[i].sanPhamBienTheId], gia != items[i].donGia {
                changed.append("\(items[i].tenSanPham): \(HoaDonFormatting.money(items[i].donGia)) → \(HoaDonFormatting.money(gia))")
                items[i].donGia = gia
            }
        }
        guard !changed.isEmpty else { return }
        giaRiengBanner = changed.joined(separator: "\n")
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            giaRiengBanner = nil
        }
    }

    private func quickAddFavorite(_ fav: KhachHangFavoriteItemDto) {
        guard let sp = sanPhamList.first(where: { $0.ten == fav.tenSanPham }) else { return }
        let bt = sp.bienThe.first(where: { $0.tenBienThe == fav.tenBienThe })
            ?? sp.bienThe.first(where: { $0.macDinh })
            ?? sp.bienThe.first
        guard let bt else { return }
        var draft = DraftChiTiet(sanPhamBienTheId: bt.id, tenSanPham: sp.ten, tenBienThe: bt.tenBienThe, soLuong: 1, donGia: bt.giaBan)
        if let gia = giaRiengMap[bt.id], gia != bt.giaBan { draft.donGia = gia }
        items.append(draft)
    }

    private func createNewKhach() async {
        let ten = newKhachTen.trimmingCharacters(in: .whitespaces)
        let sdtVal = newKhachSdt.trimmingCharacters(in: .whitespaces)
        let diaChiVal = newKhachDiaChi.trimmingCharacters(in: .whitespaces)
        guard !ten.isEmpty else { newKhachError = "Vui lòng nhập tên khách."; return }
        guard !diaChiVal.isEmpty else { newKhachError = "Vui lòng nhập địa chỉ."; return }

        newKhachSaving = true
        newKhachError = nil
        let body = KhachHangCreateRequest(
            ten: ten, duocNhanVoucher: newKhachVoucher,
            phones: sdtVal.isEmpty ? [] : [KhachHangPhoneDto(soDienThoai: sdtVal, isDefault: true)],
            addresses: [KhachHangAddressDto(diaChi: diaChiVal, isDefault: true)]
        )
        let result = await APIClient.shared.createKhachHang(body)
        newKhachSaving = false
        if result.success, let khach = result.khach {
            selectKhach(khach)
            showNewKhachForm = false
            newKhachTen = ""; newKhachSdt = ""; newKhachDiaChi = ""; newKhachVoucher = false
        } else {
            newKhachError = result.message ?? "Tạo khách thất bại."
        }
    }

    private func save() async {
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
            khachHangId: selectedKhach?.id,
            tenKhachHangText: tenKhach.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tenKhach,
            soDienThoaiText: sdt.trimmingCharacters(in: .whitespaces).isEmpty ? nil : sdt,
            diaChiText: diaChi.trimmingCharacters(in: .whitespaces).isEmpty ? nil : diaChi,
            ghiChu: originalGhiChu,
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
