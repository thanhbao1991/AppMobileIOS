import SwiftUI

/// Form thêm hoá đơn mới — port HoaDonEditWindow (Desktop) trừ phần đổi phân loại/bàn giữa chừng
/// (phân loại đã chốt từ lúc bấm "+" trên danh sách, xem HoaDonListView.AddHoaDonSheet). Có đủ:
/// thêm/sửa/xoá món (size, topping, ghi chú + quick-note chips), giảm giá (preset + tự động theo
/// phân loại + tuỳ chỉnh), khách hàng (tìm/tạo mới, nhiều SĐT/địa chỉ, giá riêng tự áp, điểm/nợ/ví/
/// voucher/món yêu thích). Giao diện tự thiết kế lại cho hợp iOS, không rập khuôn theo layout panel
/// 2 cột của Desktop.
struct HoaDonCreateFormView: View {
    let phanLoai: String
    /// Preset từ "Đơn 7h" (xem HoaDonListView.KhachGoiSomSheet) — mở form đã chọn sẵn khách + món
    /// cuối họ từng gọi, khớp OpenKhachGoiSom (Desktop): SetPhanLoai(Ship) + PreFillKhachHang.
    var presetKhachHangId: String? = nil
    var presetTenSanPham: String? = nil
    var presetTenBienThe: String? = nil
    /// Preset từ "Bắt đơn App" (xem HoaDonListView.AppOrderPickerSheet) — món đã map sẵn
    /// SanPhamBienTheId thật từ server (AppOrderService.ParseHoaDon), khớp GetDonAsync (Desktop).
    var presetItems: [DraftChiTiet] = []
    var presetGhiChu: String? = nil
    var presetWarnings: [String] = []
    let onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    // Bàn (chỉ Tại Chỗ)
    @State private var tenBan = ""

    // Món
    @State private var items: [DraftChiTiet] = []
    @State private var pickerTarget: PickerTarget? = PickerTarget(index: nil)
    @State private var sanPhamList: [SanPhamDto] = []
    @State private var toppingList: [ToppingDto] = []
    @State private var giaRiengList: [KhachHangGiaBanDto] = []

    // Khách hàng
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
    @State private var presetWarningBanner: String?
    /// Sau khi chọn khách, ẩn bớt 3 ô tên/SĐT/địa chỉ (thông tin đã có sẵn trong "selectedKhachInfo")
    /// — chỉ hiện lại khi bấm "Sửa" để chỉnh SĐT/địa chỉ riêng cho đơn này.
    @State private var showEditKhachHang = false
    @State private var showNewKhachForm = false
    @State private var newKhachTen = ""
    @State private var newKhachSdt = ""
    @State private var newKhachDiaChi = ""
    @State private var newKhachVoucher = false
    @State private var newKhachSaving = false
    @State private var newKhachError: String?
    // Sửa hồ sơ khách đã chọn (nhiều SĐT/địa chỉ) — khớp EditKhachPanel (Desktop,
    // HoaDonEditWindow.KhachHang.cs)
    @State private var editTen = ""
    @State private var editPhoneRows: [EditContactRow] = []
    @State private var editAddressRows: [EditContactRow] = []
    @State private var editVoucher = false
    @State private var editSaving = false
    @State private var editError: String?

    // Giảm giá
    @State private var giamGia: Double = 0
    @State private var giamGiaManual = false

    // Ghi chú đơn + trạng thái lưu
    @State private var ghiChuDon = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private struct PickerTarget: Identifiable {
        let index: Int?  // nil = thêm mới, có giá trị = sửa items[index]
        var id: String { index.map(String.init) ?? "new" }
    }

    /// Dòng SĐT/địa chỉ đang sửa trong editKhachForm — id giữ nguyên của KhachHangPhone/AddressDto
    /// gốc để server nhận diện sửa-tại-chỗ; dòng vừa "Thêm" có id mới nên server sẽ INSERT
    /// (khớp KhachHangCrudService.UpdateAsync: so Id trùng thì sửa, không có thì thêm mới).
    private struct EditContactRow: Identifiable {
        var id: String
        var value: String
    }

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
                    if let presetWarningBanner {
                        Text("Lưu ý khi bắt đơn:\n\(presetWarningBanner)")
                            .font(.footnote).foregroundColor(.warningColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.warningColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if phanLoai == "Tại Chỗ" { tenBanCard }
                    khachHangCard
                    monCard
                    discountCard
                    summaryCard
                }
                .padding()
            }
            .navigationTitle(HoaDonFormatting.phanLoaiLabel(phanLoai))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang tạo..." : "Tạo đơn") { Task { await save() } }
                        .disabled(saving || items.isEmpty)
                }
            }
        }
        .task {
            await loadCatalog()
            await applyPresets()
            if selectedKhach == nil && (phanLoai == "Mh" || phanLoai == "Ship") {
                khachSearchFocused = true
            }
        }
    }

    // ══════════════════════════════════════════════
    // Bàn
    // ══════════════════════════════════════════════

    private var tenBanCard: some View {
        DetailCard {
            Text("Số bàn").font(.headline)
            TextField("Vd: 12", text: $tenBan)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
        }
    }

    // ══════════════════════════════════════════════
    // Khách hàng
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
            } else {
                selectedKhachInfo(selectedKhach!)
            }

            // Chưa chọn khách: KHÔNG hiện ô gõ tay tên/SĐT/địa chỉ nữa — khớp Desktop
            // (PhanLoai.NeedKhachHang chỉ dùng để ép focus ô tìm kiếm, không có đường nhập tay song
            // song; đơn Ship/Mh/App bắt buộc tìm/chọn khách có sẵn hoặc bấm "Khách mới"). Đã chọn
            // khách: ẩn (thông tin hiện gọn trong selectedKhachInfo), bấm "Sửa" mở editKhachForm —
            // sửa thẳng hồ sơ khách, đủ nhiều SĐT/địa chỉ như Desktop.
            if selectedKhach != nil && showEditKhachHang {
                Divider()
                editKhachForm
            }
        }
    }

    private func fieldLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.bold())
            .foregroundColor(.textMuted)
    }

    /// Form sửa hồ sơ khách — khớp EditKhachPanel (Desktop): tên + nhiều SĐT/địa chỉ (thêm/xoá dòng),
    /// voucher, Lưu (PUT /api/KhachHang/{id}) / Huỷ. Dòng đầu mỗi danh sách tự thành mặc định
    /// (IsDefault = i == 0), khớp SaveKhachContactBtn_Click.
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

            HStack(spacing: 24) {
                Button(editSaving ? "Đang lưu..." : "Lưu") { Task { await saveEditKhach() } }
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
            if info.tongNo > 0 {
                infoBadge("Nợ \(HoaDonFormatting.money(info.tongNo))", color: .dangerColor)
            }
            if info.soDu > 0 {
                infoBadge("Ví \(HoaDonFormatting.money(info.soDu))", color: .brandPrimary)
            }
            if info.donKhac > 0 {
                infoBadge("Đơn khác chưa trả \(HoaDonFormatting.money(info.donKhac))", color: .warningColor)
            }
            if info.duocNhanVoucher {
                if info.daNhanVoucher {
                    infoBadge("Đã nhận voucher tháng này", color: .successColor)
                } else if info.diemThangTruoc >= 3000 {
                    let soVoucher = info.diemThangTruoc / 3000
                    infoBadge("Đủ điều kiện voucher \(HoaDonFormatting.money(Double(soVoucher) * 10000))", color: .pinkColor)
                }
            }
            if info.diemThangNay > 0 || info.diemThangTruoc > 0 {
                Text("Điểm: \(HoaDonFormatting.diemDisplay(info.diemThangNay)) tháng này · \(HoaDonFormatting.diemDisplay(info.diemThangTruoc)) tháng trước")
                    .font(.caption2).foregroundColor(.textMuted)
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

            // Panel chọn/sửa món nằm NGAY TRONG monCard — không mở sheet riêng nữa (2 sheet chồng
            // nhau: sheet "Tạo đơn" + sheet "Chọn món" vẫn tạo cảm giác 2 màn hình dù bên trong đã
            // gộp list+cấu hình). Ô tìm món luôn hiện sẵn (không cần bấm "Thêm món" mở ra), chạm 1
            // dòng món chỉ mở rộng panel tại chỗ sang chế độ sửa, cùng cuộn chung với phần còn lại
            // của form.
            if let pickerTarget {
                Divider()
                ProductPickerPanel(
                    sanPhamList: sanPhamList,
                    toppingList: toppingList,
                    giaRiengMap: giaRiengMap,
                    editingItem: pickerTarget.index.map { items[$0] },
                    autoFocusSearchOnAppear: !(phanLoai == "Mh" || phanLoai == "Ship"),
                    onAdd: { draft in
                        items.append(draft)
                        recalcGiamGia()
                    },
                    onSaveEdit: pickerTarget.index.map { idx -> (DraftChiTiet) -> Void in
                        { draft in
                            items[idx] = draft
                            recalcGiamGia()
                        }
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
                if !item.toppingText.isEmpty {
                    Text(item.toppingText).font(.caption).foregroundColor(.brandPrimary)
                }
                if !item.noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(item.noteText).font(.caption).italic().foregroundColor(.orange)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(HoaDonFormatting.moneyFormatter.string(from: NSNumber(value: item.thanhTien)) ?? "\(Int(item.thanhTien))")
                    .font(.subheadline.bold())
                Button {
                    items.remove(at: index)
                    recalcGiamGia()
                } label: {
                    Image(systemName: "trash").foregroundColor(.dangerColor).font(.caption)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { pickerTarget = PickerTarget(index: index) }
    }

    // ══════════════════════════════════════════════
    // Giảm giá
    // ══════════════════════════════════════════════

    private let discountPresets: [Double] = [0, 10_000, 20_000, 30_000, 40_000, 50_000, 60_000, 70_000, 80_000, 90_000, 100_000]

    private var discountCard: some View {
        DetailCard {
            HStack {
                Label("Giảm giá", systemImage: "tag.fill").font(.headline)
                Spacer()
                if giamGiaManual {
                    Button("Tự động") { giamGiaManual = false; recalcGiamGia() }.font(.caption)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(discountPresets, id: \.self) { v in
                        let active = giamGiaManual && giamGia == v
                        Button(v == 0 ? "Không" : HoaDonFormatting.moneyShort(v)) {
                            giamGiaManual = true
                            giamGia = v
                            recalcGiamGia()
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
                TextField("0", value: Binding(
                    get: { giamGia },
                    set: { giamGiaManual = true; giamGia = $0; recalcGiamGia() }
                ), format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                Text("đ")
            }
        }
    }

    // ══════════════════════════════════════════════
    // Ghi chú + tổng kết
    // ══════════════════════════════════════════════

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

    private func loadCatalog() async {
        async let sp = APIClient.shared.getSanPhamList()
        async let tp = APIClient.shared.getToppingList()
        async let gr = APIClient.shared.getKhachHangGiaBanList()
        sanPhamList = await sp
        toppingList = await tp
        giaRiengList = await gr
    }

    private func applyPresets() async {
        if let presetKhachHangId, let kh = await APIClient.shared.getKhachHangById(presetKhachHangId) {
            selectKhach(kh)
        }
        if let presetTenSanPham, !presetTenSanPham.isEmpty {
            quickAddFavorite(KhachHangFavoriteItemDto(tenSanPham: presetTenSanPham, tenBienThe: presetTenBienThe ?? ""))
        }
        if !presetItems.isEmpty {
            items = presetItems
            recalcGiamGia()
        }
        if let presetGhiChu, !presetGhiChu.isEmpty {
            ghiChuDon = presetGhiChu
        }
        if !presetWarnings.isEmpty {
            presetWarningBanner = presetWarnings.joined(separator: "\n")
        }
    }

    private func recalcGiamGia() {
        if let auto = HoaDonFormatting.autoGiamGia(phanLoai: phanLoai, tongTien: tongTien, manual: giamGiaManual) {
            giamGia = auto
        }
        giamGia = min(giamGia, tongTien)
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
        sdt = kh.phones.first(where: { $0.isDefault })?.soDienThoai ?? kh.phones.first?.soDienThoai ?? ""
        diaChi = kh.addresses.first(where: { $0.isDefault })?.diaChi ?? kh.addresses.first?.diaChi ?? ""
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

        // Giữ nguyên SĐT/địa chỉ đang gán cho đơn nếu dòng đó (theo Id) vẫn còn sau khi sửa — khớp
        // SaveKhachContactBtn_Click (Desktop): so previousPhoneId/previousAddrId theo Id, không theo text.
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
        recalcGiamGia()
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
        recalcGiamGia()
    }

    private func createNewKhach() async {
        let ten = newKhachTen.trimmingCharacters(in: .whitespaces)
        let sdtVal = newKhachSdt.trimmingCharacters(in: .whitespaces)
        let diaChiVal = newKhachDiaChi.trimmingCharacters(in: .whitespaces)
        guard !ten.isEmpty else { newKhachError = "Vui lòng nhập tên khách."; return }
        guard !diaChiVal.isEmpty else { newKhachError = "Vui lòng nhập địa chỉ."; return }

        newKhachSaving = true
        newKhachError = nil
        // Khách không cho SĐT thì để trống hẳn (server chấp nhận Phones rỗng) — không ép nhập
        // đại số giả để qua validate. Nếu CÓ nhập, server sẽ tự chặn nếu sai định dạng.
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
            errorMessage = "Đơn tại chỗ phải nhập số bàn."
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
            ghiChu: ghiChuDon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : ghiChuDon,
            giamGia: giamGia,
            chiTietHoaDons: chiTietDtos,
            chiTietHoaDonToppings: toppingDtos
        )

        let result = await APIClient.shared.createHoaDonFull(body)
        saving = false
        if result.success, let id = result.id {
            dismiss()
            onCreated(id)
        } else {
            errorMessage = result.message ?? "Tạo hoá đơn thất bại."
        }
    }
}

// ══════════════════════════════════════════════
// Model nháp cho món đang thêm/sửa trong form
// ══════════════════════════════════════════════

struct DraftTopping: Identifiable, Hashable {
    let toppingId: String
    let ten: String
    let gia: Double
    var soLuong: Int
    var id: String { toppingId }
}

struct DraftChiTiet: Identifiable {
    let id: String = UUID().uuidString
    var sanPhamBienTheId: String
    var tenSanPham: String
    var tenBienThe: String
    var soLuong: Int
    var donGia: Double
    var noteText: String = ""
    var toppings: [DraftTopping] = []

    var toppingTien: Double { toppings.reduce(0) { $0 + $1.gia * Double($1.soLuong) } }
    var thanhTien: Double { donGia * Double(soLuong) + toppingTien }
    var toppingText: String {
        toppings.filter { $0.soLuong > 0 }
            .map { $0.soLuong > 1 ? "\($0.ten) x\($0.soLuong)" : $0.ten }
            .joined(separator: ", ")
    }
}

/// Chuẩn hoá chuỗi tìm món — khớp StringHelper.MyNormalizeText (Desktop/Backend): hạ chữ thường,
/// bỏ dấu (đ/Đ → d/D riêng vì không tách được qua NFD), bỏ ký tự không phải chữ/số/khoảng trắng,
/// gộp nhiều khoảng trắng liên tiếp. Dùng chung với TimKiem (SanPhamMatchHelper.Search: Contains
/// đơn giản trên TimKiem) để "cfk" khớp được "Cà Phê Kem" nếu sản phẩm có VietTat="cfk".
private enum SanPhamSearch {
    static func normalize(_ s: String) -> String {
        let ascii = BillTextBuilder.toAsciiNoDiacritics(s, upper: false)
        let filtered = ascii.filter { $0.isLetter || $0.isNumber || $0 == " " }
        return filtered
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

// ══════════════════════════════════════════════
// Panel chọn/sửa món — chọn sản phẩm → size/topping/số lượng/ghi chú → thêm hoặc lưu. Nhúng THẲNG
// vào monCard (KHÔNG mở sheet riêng) — mở sheet lồng trên sheet "Tạo đơn" vẫn tạo cảm giác 2 màn
// hình dù nội dung bên trong đã gộp list+cấu hình vào 1 khối.
// ══════════════════════════════════════════════

private struct ProductPickerPanel: View {
    let sanPhamList: [SanPhamDto]
    let toppingList: [ToppingDto]
    let giaRiengMap: [String: Double]
    let editingItem: DraftChiTiet?
    var autoFocusSearchOnAppear: Bool = true
    let onAdd: (DraftChiTiet) -> Void
    let onSaveEdit: ((DraftChiTiet) -> Void)?
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var picking: SanPhamBienTheDto?
    @State private var pickingSanPham: SanPhamDto?
    @State private var soLuong = 1
    @State private var donGia: Double = 0
    @State private var noteText = ""
    @State private var toppingQty: [String: Int] = [:]
    /// 0 = tab Ghi chú, 1 = tab Topping.
    @State private var detailTab = 0
    @FocusState private var searchFocused: Bool

    private let quickNoteGroups: [(title: String, notes: [String])] = [
        ("Đường", ["Không đường", "Ít ngọt", "Ngọt", "Nhiều ngọt", "Đường riêng", "Đắng"]),
        ("Đá", ["Không đá", "Ít đá", "Vừa đá", "Nhiều đá", "Đá riêng", "Chua"]),
        ("Trà", ["Không trà", "Trà nóng", "Trà đá", "Chỉ TCĐĐ"]),
        ("Khác", ["Size L", "Sài gòn", "Chỉ TCOL", "Chỉ TCT"]),
    ]

    /// Khớp SanPhamMatchHelper.Search (Desktop): Contains đơn giản trên TimKiem (đã token hoá sẵn ở
    /// server — tên không dấu, tên liền không cách, viết tắt tự nhận diện, VietTat tự đặt tay), KHÔNG
    /// so trực tiếp `ten` có dấu (bỏ sót các kiểu gõ tắt như "cfk" cho "Cà Phê Kem" nếu chỉ so `ten`).
    private var filteredProducts: [SanPhamDto] {
        let keyword = SanPhamSearch.normalize(searchText)
        guard !keyword.isEmpty else { return sanPhamList }
        return sanPhamList.filter { ($0.timKiem ?? "").contains(keyword) }
    }

    private var activeNotes: Set<String> {
        Set(noteText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    private var toppingCount: Int { toppingQty.values.reduce(0) { $0 + $1 } }

    /// Thành tiền tạm tính của dòng đang cấu hình (chưa thêm vào đơn) — khớp DraftChiTiet.thanhTien.
    private var thanhTienDraft: Double {
        let toppingTien = toppingQty.reduce(0.0) { sum, kv in
            guard let top = toppingList.first(where: { $0.id == kv.key }) else { return sum }
            return sum + top.gia * Double(kv.value)
        }
        return donGia * Double(soLuong) + toppingTien
    }

    /// Nhúng trực tiếp trong monCard, KHÔNG NavigationStack/sheet riêng — cùng cuộn với phần còn lại
    /// của form "Tạo đơn" nên chỉ còn đúng 1 sheet duy nhất. Ô tìm luôn hiện (kể cả sau khi đã chọn
    /// món, để đổi món không cần nút riêng), gõ tìm hiện dropdown kết quả bên dưới (KHÔNG liệt kê cả
    /// catalog — danh sách món quá dài để cuộn hết), chọn 1 món thì dropdown ẩn đi còn phần cấu hình
    /// số lượng/đơn giá/ghi chú/topping hiện ngay bên dưới.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if editingItem != nil {
                HStack {
                    Text("ĐANG SỬA MÓN").font(.subheadline.bold())
                    Spacer()
                    Button("Đóng") { onClose() }.font(.caption)
                }
            }

            if editingItem == nil && pickingSanPham == nil {
                TextField("Tìm món để thêm...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = filteredProducts.first(where: { !$0.bienThe.isEmpty }) {
                            selectProduct(first)
                        }
                    }
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    productListSection
                }
            }

            if let pickingSanPham, let picking {
                configSection(pickingSanPham, picking)
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            preloadEditing()
            if editingItem == nil && autoFocusSearchOnAppear { searchFocused = true }
        }
    }

    private var productListSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredProducts.prefix(30)) { sp in
                Button { selectProduct(sp) } label: {
                    HStack {
                        Text(sp.ten)
                        Spacer()
                        Text(sp.bienThe.map { HoaDonFormatting.money($0.giaBan) }.first ?? "")
                            .font(.caption).foregroundColor(.textMuted)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sp.bienThe.isEmpty)
                Divider()
            }
        }
    }

    private func selectProduct(_ sp: SanPhamDto) {
        pickingSanPham = sp
        let bt = sp.bienThe.first(where: { $0.macDinh }) ?? sp.bienThe.first
        picking = bt
        resetDetailState(bt)
    }

    private func configSection(_ sp: SanPhamDto, _ bt: SanPhamBienTheDto) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(sp.ten).font(.headline)
                Spacer()
                if editingItem == nil {
                    Button("Đổi món") {
                        pickingSanPham = nil
                        picking = nil
                        searchText = ""
                        searchFocused = true
                    }
                    .font(.caption)
                    Spacer().frame(width: 20)
                    Button("Xong") {
                        confirmAdd(sp, picking ?? bt)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Lưu") {
                        confirmAdd(sp, picking ?? bt)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if sp.bienThe.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sp.bienThe.sorted(by: { $0.giaBan < $1.giaBan })) { variant in
                            let active = variant.id == bt.id
                            Button("\(variant.tenBienThe) \(HoaDonFormatting.moneyShort(variant.giaBan))") {
                                picking = variant
                                donGia = variant.giaBan
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(active ? Color.brandPrimary.opacity(0.15) : Color.clear)
                            .foregroundColor(active ? .brandPrimary : .textMuted)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(active ? Color.brandPrimary : Color.textMuted.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            // Số lượng/đơn giá/thành tiền chung 1 hàng thay vì xếp chồng — nhìn thấy ngay thành tiền
            // của dòng đang cấu hình mà không cần thêm vào đơn rồi mới biết.
            GeometryReader { geo in
                let spacing: CGFloat = 8
                let unit = (geo.size.width - spacing * 2) / 3.1
                HStack(spacing: spacing) {
                    HStack(spacing: 4) {
                        Button {
                            if soLuong > 1 { soLuong -= 1 }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .disabled(soLuong <= 1)
                        Text("\(soLuong)").font(.subheadline.bold()).frame(minWidth: 16)
                        Button {
                            if soLuong < 50 { soLuong += 1 }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(soLuong >= 50)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.brandPrimary)
                    .frame(width: unit, alignment: .leading)

                    HStack(spacing: 4) {
                        Button {
                            donGia = max(0, donGia - 5000)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .disabled(donGia <= 0)
                        TextField("0", value: $donGia, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            donGia += 5000
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.brandPrimary)
                    .frame(width: unit * 1.1, alignment: .center)

                    Text(HoaDonFormatting.money(thanhTienDraft))
                        .font(.subheadline.bold())
                        .foregroundColor(.brandPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: unit, alignment: .trailing)
                }
            }
            .frame(height: 34)

            // Ghi chú/Topping đặt ngang hàng qua tab thay vì xếp chồng — đỡ cuộn dài khi có nhiều
            // topping. Tab "Ghi chú" trước vì hầu như món nào cũng cần chỉnh đường/đá, topping
            // chỉ áp dụng một số món.
            if !toppingList.isEmpty {
                Picker("", selection: $detailTab) {
                    Text("Ghi chú").tag(0)
                    Text("Topping\(toppingCount > 0 ? " (\(toppingCount))" : "")").tag(1)
                }
                .pickerStyle(.segmented)
            }

            if detailTab == 1 && !toppingList.isEmpty {
                toppingSection
            } else {
                noteSection
            }
        }
    }

    private var toppingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toppingList) { top in
                HStack {
                    Text(top.ten)
                    Spacer()
                    Text(HoaDonFormatting.money(top.gia)).font(.caption).foregroundColor(.textMuted)
                    Stepper("\(toppingQty[top.id] ?? 0)", value: Binding(
                        get: { toppingQty[top.id] ?? 0 },
                        set: { toppingQty[top.id] = $0 }
                    ), in: 0...20)
                    .fixedSize()
                }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ghi chú món...", text: $noteText)
                .textFieldStyle(.roundedBorder)
            ForEach(quickNoteGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.caption2).foregroundColor(.textMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(group.notes, id: \.self) { note in
                                let active = activeNotes.contains(note)
                                Button(note) { toggleNote(note) }
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(active ? Color.brandPrimary : Color.textMuted.opacity(0.1))
                                    .foregroundColor(active ? .white : .textMuted)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleNote(_ note: String) {
        var notes = noteText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let idx = notes.firstIndex(of: note) { notes.remove(at: idx) } else { notes.append(note) }
        noteText = notes.joined(separator: ", ")
    }

    private func resetDetailState(_ bt: SanPhamBienTheDto?) {
        guard let bt else { return }
        soLuong = 1
        donGia = giaRiengMap[bt.id] ?? bt.giaBan
        noteText = ""
        toppingQty = [:]
        detailTab = 0
    }

    private func preloadEditing() {
        guard let editingItem else { return }
        guard let sp = sanPhamList.first(where: { $0.bienThe.contains { $0.id == editingItem.sanPhamBienTheId } }) else { return }
        pickingSanPham = sp
        picking = sp.bienThe.first { $0.id == editingItem.sanPhamBienTheId }
        soLuong = editingItem.soLuong
        donGia = editingItem.donGia
        noteText = editingItem.noteText
        toppingQty = Dictionary(uniqueKeysWithValues: editingItem.toppings.map { ($0.toppingId, $0.soLuong) })
        detailTab = toppingQty.values.contains(where: { $0 > 0 }) ? 1 : 0
    }

    private func confirmAdd(_ sp: SanPhamDto, _ bt: SanPhamBienTheDto) {
        let toppings = toppingList.compactMap { top -> DraftTopping? in
            let qty = toppingQty[top.id] ?? 0
            guard qty > 0 else { return nil }
            return DraftTopping(toppingId: top.id, ten: top.ten, gia: top.gia, soLuong: qty)
        }
        let draft = DraftChiTiet(
            sanPhamBienTheId: bt.id, tenSanPham: sp.ten, tenBienThe: bt.tenBienThe,
            soLuong: soLuong, donGia: donGia, noteText: noteText, toppings: toppings
        )

        if let onSaveEdit {
            onSaveEdit(draft)
            onClose()
        } else {
            onAdd(draft)
            // Quay lại danh sách để chọn thêm món tiếp — khớp Desktop (SanPhamSearch.Clear+Focus
            // sau AddChiTiet), không đóng panel để nhân viên lên đơn nhiều món liên tiếp không cần
            // mở lại "Thêm món" mỗi lần.
            pickingSanPham = nil
            picking = nil
            searchText = ""
            searchFocused = true
        }
    }
}
