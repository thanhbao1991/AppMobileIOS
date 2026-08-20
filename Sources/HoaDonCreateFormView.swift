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
    @State private var pickerTarget: PickerTarget?
    @State private var sanPhamList: [SanPhamDto] = []
    @State private var toppingList: [ToppingDto] = []
    @State private var giaRiengList: [KhachHangGiaBanDto] = []

    // Khách hàng
    @State private var selectedKhach: KhachHangDto?
    @State private var tenKhach = ""
    @State private var sdt = ""
    @State private var diaChi = ""
    @State private var khachSearchText = ""
    @State private var khachSearchResults: [KhachHangDto] = []
    @State private var khachSearchTask: Task<Void, Never>?
    @State private var khachInfo: KhachHangInfoDto?
    @State private var giaRiengBanner: String?
    @State private var presetWarningBanner: String?
    @State private var showNewKhachForm = false
    @State private var newKhachTen = ""
    @State private var newKhachSdt = ""
    @State private var newKhachDiaChi = ""
    @State private var newKhachVoucher = false
    @State private var newKhachSaving = false
    @State private var newKhachError: String?

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
                    ghiChuCard
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
        }
        .sheet(item: $pickerTarget) { target in
            ProductPickerSheet(
                sanPhamList: sanPhamList,
                toppingList: toppingList,
                giaRiengMap: giaRiengMap,
                editingItem: target.index.map { items[$0] },
                onAdd: { draft in
                    items.append(draft)
                    recalcGiamGia()
                },
                onSaveEdit: target.index.map { idx -> (DraftChiTiet) -> Void in
                    { draft in
                        items[idx] = draft
                        recalcGiamGia()
                    }
                }
            )
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
                Label("Khách hàng", systemImage: "person.crop.circle").font(.headline)
                Spacer()
                if selectedKhach != nil {
                    Button("Bỏ chọn") { clearKhach() }.font(.caption)
                }
            }

            if selectedKhach == nil {
                TextField("Tìm khách theo tên/SĐT...", text: $khachSearchText)
                    .textFieldStyle(.roundedBorder)
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

                if showNewKhachForm {
                    newKhachForm
                } else {
                    Button { showNewKhachForm = true } label: {
                        Label("Khách mới", systemImage: "person.badge.plus")
                    }
                    .font(.subheadline)
                }
            } else {
                selectedKhachInfo(selectedKhach!)
            }

            // SĐT/địa chỉ luôn hiển thị + sửa được, kể cả khi đã chọn khách (khớp Desktop: gán trực
            // tiếp trên đơn, không bắt buộc trùng 100% dữ liệu lưu sẵn của khách).
            if HoaDonFormatting.needKhachHang(phanLoai) || selectedKhach != nil || !sdt.isEmpty || !diaChi.isEmpty {
                Divider()
                TextField("Tên khách (không bắt buộc)", text: $tenKhach)
                    .textFieldStyle(.roundedBorder)
                TextField("Số điện thoại", text: $sdt)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
                TextField("Địa chỉ", text: $diaChi)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private func selectedKhachInfo(_ kh: KhachHangDto) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kh.ten).font(.subheadline.bold())

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
            if !info.duocNhanVoucher {
                infoBadge("Không tích điểm", color: .textMuted)
            } else if info.daNhanVoucher {
                infoBadge("Đã nhận voucher tháng này", color: .successColor)
            } else if info.diemThangTruoc >= 3000 {
                let soVoucher = info.diemThangTruoc / 3000
                infoBadge("Đủ điều kiện voucher \(HoaDonFormatting.money(Double(soVoucher) * 10000))", color: .pinkColor)
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
            Text("Món hay mua — bấm để thêm nhanh").font(.caption).foregroundColor(.textMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(all) { fav in
                        Button {
                            quickAddFavorite(fav)
                        } label: {
                            Text(fav.tenBienThe.isEmpty ? fav.tenSanPham : "\(fav.tenSanPham) (\(fav.tenBienThe))")
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

            Button { pickerTarget = PickerTarget(index: nil) } label: {
                Label("Thêm món", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    private func draftItemRow(_ item: DraftChiTiet, index: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(item.soLuong)")
                .font(.caption.bold()).foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.brandPrimary))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.tenBienThe.isEmpty || item.tenBienThe == "Mặc định"
                     ? item.tenSanPham : "\(item.tenSanPham) (\(item.tenBienThe))")
                    .font(.subheadline.bold())
                if !item.toppingText.isEmpty {
                    Text(item.toppingText).font(.caption).foregroundColor(.brandPrimary)
                }
                if !item.noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(item.noteText).font(.caption).italic().foregroundColor(.warningColor)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
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

    private var ghiChuCard: some View {
        DetailCard {
            Text("Ghi chú đơn").font(.headline)
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
        khachInfo = nil
        tenKhach = ""
        sdt = ""
        diaChi = ""
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

// ══════════════════════════════════════════════
// Sheet chọn/sửa món — chọn sản phẩm → size/topping/số lượng/ghi chú → thêm hoặc lưu.
// ══════════════════════════════════════════════

private struct ProductPickerSheet: View {
    let sanPhamList: [SanPhamDto]
    let toppingList: [ToppingDto]
    let giaRiengMap: [String: Double]
    let editingItem: DraftChiTiet?
    let onAdd: (DraftChiTiet) -> Void
    let onSaveEdit: ((DraftChiTiet) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var picking: SanPhamBienTheDto?
    @State private var pickingSanPham: SanPhamDto?
    @State private var soLuong = 1
    @State private var donGia: Double = 0
    @State private var noteText = ""
    @State private var toppingQty: [String: Int] = [:]

    private let quickNoteGroups: [(title: String, notes: [String])] = [
        ("Đường", ["Không đường", "Ít ngọt", "Ngọt", "Nhiều ngọt", "Đường riêng", "Đắng"]),
        ("Đá", ["Không đá", "Ít đá", "Vừa đá", "Nhiều đá", "Đá riêng", "Chua"]),
        ("Trà", ["Không trà", "Trà nóng", "Trà đá", "Chỉ TCĐĐ"]),
        ("Khác", ["Size L", "Sài gòn", "Chỉ TCOL", "Chỉ TCT"]),
    ]

    private var filteredProducts: [SanPhamDto] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return sanPhamList }
        return sanPhamList.filter { $0.ten.localizedCaseInsensitiveContains(searchText) }
    }

    private var activeNotes: Set<String> {
        Set(noteText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let pickingSanPham, let picking {
                    detailStep(pickingSanPham, picking)
                } else {
                    listStep
                }
            }
            .navigationTitle(pickingSanPham?.ten ?? "Chọn món")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if pickingSanPham != nil && editingItem == nil {
                        Button("Quay lại") { pickingSanPham = nil; picking = nil }
                    } else {
                        Button("Đóng") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { preloadEditing() }
    }

    private var listStep: some View {
        VStack(spacing: 0) {
            TextField("Tìm món...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
            List(filteredProducts) { sp in
                Button {
                    pickingSanPham = sp
                    let bt = sp.bienThe.first(where: { $0.macDinh }) ?? sp.bienThe.first
                    picking = bt
                    resetDetailState(bt)
                } label: {
                    HStack {
                        Text(sp.ten)
                        Spacer()
                        Text(sp.bienThe.map { HoaDonFormatting.money($0.giaBan) }.first ?? "")
                            .font(.caption).foregroundColor(.textMuted)
                    }
                }
                .disabled(sp.bienThe.isEmpty)
            }
            .listStyle(.plain)
        }
    }

    private func detailStep(_ sp: SanPhamDto, _ bt: SanPhamBienTheDto) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sp.bienThe.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Size").font(.caption).foregroundColor(.textMuted)
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
                                    .background(active ? Color.brandPrimary : Color.textMuted.opacity(0.12))
                                    .foregroundColor(active ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text("Đơn giá")
                    Spacer()
                    TextField("0", value: $donGia, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                    Text("đ")
                }

                HStack {
                    Text("Số lượng")
                    Spacer()
                    Stepper("\(soLuong)", value: $soLuong, in: 1...50)
                        .fixedSize()
                }

                if !toppingList.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Topping").font(.subheadline.bold())
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ghi chú").font(.subheadline.bold())
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

                Button(editingItem != nil ? "Lưu" : "Thêm vào đơn") {
                    confirmAdd(sp, picking ?? bt)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
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
            dismiss()
        } else {
            onAdd(draft)
            // Quay lại danh sách để chọn thêm món tiếp — khớp Desktop (SanPhamSearch.Clear+Focus
            // sau AddChiTiet), không đóng sheet để nhân viên lên đơn nhiều món liên tiếp không cần
            // mở lại "Thêm món" mỗi lần.
            pickingSanPham = nil
            picking = nil
            searchText = ""
        }
    }
}
