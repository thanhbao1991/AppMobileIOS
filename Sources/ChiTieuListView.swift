import SwiftUI

/// Chi tiêu hằng ngày — GET/PUT/DELETE /api/ChiTieuHangNgay. List theo ngày (DayNavBar) + search.
/// Bấm vào dòng mở sheet chi tiết (Sửa/Xoá qua ActionButtonView + confirmationDialog trước khi xoá)
/// — khớp phong cách HoaDonDetailView, thay cho swipeActions xoá thẳng không xác nhận trước đây. Nút
/// "+" thêm chi tiêu nằm ở footer, khớp bố cục HoaDonListView (nút tròn cạnh tổng tiền).
struct ChiTieuListView: View {
    @State private var currentDate = Date()
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var selectedItem: ChiTieuHangNgayDto?
    @State private var showAdd = false

    private var filteredItems: [ChiTieuHangNgayDto] {
        items.filter { anyMatchesSearch(searchText, $0.ten, $0.ghiChu) }
    }

    private var totalText: String {
        HoaDonFormatting.money(filteredItems.reduce(0) { $0 + $1.thanhTien })
    }

    private var totalNgayText: String {
        HoaDonFormatting.money(filteredItems.filter { !$0.billThang }.reduce(0) { $0 + $1.thanhTien })
    }

    private var totalThangText: String {
        HoaDonFormatting.money(filteredItems.filter { $0.billThang }.reduce(0) { $0 + $1.thanhTien })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DaySearchBar(
                    date: $currentDate, searchText: $searchText,
                    placeholder: "Tìm nguyên liệu, ghi chú..."
                ) { Task { await load() } }

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        if filteredItems.isEmpty {
                            Text("Chưa có chi tiêu nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredItems) { item in
                                ChiTieuRowView(item: item, onSelect: { selectedItem = item })
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
                HStack(spacing: 12) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.system(size: 34))
                    }
                    .foregroundColor(.brandPrimary)

                    // "Thêm từ ảnh" — chọn ảnh hoá đơn mua hàng, Gemini đọc + tự gợi ý map nguyên
                    // liệu, mở form duyệt trước khi lưu thật. Xem ReceiptImportView.swift.
                    ReceiptImportButton(date: currentDate) { Task { await load() } }

                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Ngày: \(totalNgayText)")
                                .font(.caption2).foregroundColor(.successColor)
                            Text("Tháng: \(totalThangText)")
                                .font(.caption2).foregroundColor(.brandPrimary)
                        }
                        Text(totalText).font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding()
            }
        }
        .task { await load() }
        .sheet(item: $selectedItem) { item in
            ChiTieuDetailSheet(item: item) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseSheet(date: currentDate) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getChiTieuByDay(DateNavFormat.queryDate.string(from: currentDate))
        loading = false
        hasLoaded = true
    }
}

private struct ChiTieuRowView: View {
    let item: ChiTieuHangNgayDto
    var onSelect: (() -> Void)? = nil

    private var borderColor: Color {
        item.billThang ? .brandPrimary : .successColor
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(borderColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.ten).font(.subheadline.bold())
                    if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                        Text(ghiChu).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                    }
                }
                Text("\(HoaDonFormatting.money(item.donGia)) × \(item.soLuong.formatted())")
                    .font(.footnote).foregroundColor(.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
                Text(item.billThang ? "#tháng" : "#ngày")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(borderColor.opacity(0.15))
                    .foregroundColor(borderColor)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(borderColor.pastelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
    }
}

/// Mở khi bấm vào 1 dòng chi tiêu — khớp phong cách HoaDonDetailView: xem thông tin trước, Sửa/Xoá
/// là 2 nút ActionButtonView riêng bên dưới (không còn swipeActions xoá thẳng không xác nhận), Xoá
/// bắt buộc qua confirmationDialog trước khi gọi API (khớp nguyên tắc "mọi thao tác đụng tiền/dữ
/// liệu thật đều phải qua bước Xác nhận" — xem HoaDonDetailView.PendingAction).
private struct ChiTieuDetailSheet: View {
    let item: ChiTieuHangNgayDto
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.ten).font(.title3.bold())
                    if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                        Text(ghiChu).font(.subheadline).foregroundColor(.textMuted)
                    }
                }

                VStack(spacing: 10) {
                    infoRow("Số lượng", item.soLuong.formatted())
                    infoRow("Đơn giá", HoaDonFormatting.money(item.donGia))
                    infoRow("Thành tiền", HoaDonFormatting.money(item.thanhTien))
                    infoRow("Loại", item.billThang ? "Bill tháng" : "Chi ngày")
                    if let tk = item.tenTaiKhoan, !tk.isEmpty {
                        infoRow("Người thêm", tk)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundColor(.dangerColor)
                }

                Spacer()

                HStack(spacing: 12) {
                    ActionButtonView(icon: "pencil", code: nil, caption: "Sửa", color: .warningColor) {
                        showEditForm = true
                    }
                    ActionButtonView(icon: "trash", code: nil, caption: "Xoá", color: .dangerColor) {
                        showDeleteConfirm = true
                    }
                }
            }
            .padding()
            .navigationTitle("Chi tiết chi tiêu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .overlay { if deleting { ProgressView() } }
        }
        .sheet(isPresented: $showEditForm) {
            EditExpenseSheet(item: item) {
                onChanged()
                dismiss()
            }
        }
        .confirmationDialog("Xoá chi tiêu", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) { Task { await delete() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Xoá \"\(item.ten)\"? Không thể hoàn tác.")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.textMuted)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func delete() async {
        deleting = true
        errorMessage = nil
        let result = await APIClient.shared.deleteChiTieu(id: item.id)
        deleting = false
        if result.success {
            onChanged()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không xoá được."
        }
    }
}

/// Sửa 1 dòng chi tiêu — số lượng/đơn giá/ghi chú/loại đều sửa được, khớp bố cục "Thêm chi tiêu"
/// (AddExpenseSheet) thay vì trước đây chỉ cho đổi Ghi chú (quá hẹp so với form Thêm). Tên nguyên
/// liệu giữ cố định — đổi nguyên liệu thực chất là 1 dòng chi tiêu khác, không phải "sửa".
private struct EditExpenseSheet: View {
    let item: ChiTieuHangNgayDto
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var soLuong: Double
    @State private var donGia: Double
    @State private var ghiChu: String
    @State private var billThang: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    private var thanhTien: Double { soLuong * donGia }

    init(item: ChiTieuHangNgayDto, onSaved: @escaping () -> Void) {
        self.item = item
        self.onSaved = onSaved
        _soLuong = State(initialValue: item.soLuong)
        _donGia = State(initialValue: item.donGia)
        _ghiChu = State(initialValue: item.ghiChu ?? "")
        _billThang = State(initialValue: item.billThang)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Số lượng & đơn giá") {
                    QuantityPriceRow(soLuong: $soLuong, donGia: $donGia, thanhTien: thanhTien)
                }

                Section(item.ten) {
                    TextField("Ghi chú", text: $ghiChu)
                    Toggle("Bill tháng", isOn: $billThang)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle("Sửa chi tiêu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu") {
                        Task { await save() }
                    }
                    .disabled(donGia <= 0 || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let ngayIso = (item.ngay ?? item.ngayGio) ?? ""
        let ngayGioIso = item.ngayGio ?? ngayIso
        let body = ChiTieuHangNgayCreateRequest(
            ten: item.ten, soLuong: soLuong, donGia: donGia, thanhTien: thanhTien,
            ghiChu: ghiChu.isEmpty ? nil : ghiChu, ngay: ngayIso, ngayGio: ngayGioIso,
            nguyenLieuId: item.nguyenLieuId, billThang: billThang
        )
        let result = await APIClient.shared.updateChiTieu(id: item.id, body)
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}

/// Hàng Số lượng/Đơn giá/Thành tiền — khớp `configSection` bên HoaDonCreateFormView.ProductPickerSheet
/// (nút tròn -/+ cho số lượng, -/+5000 quanh ô nhập đơn giá) thay cho Stepper mặc định trước đây, dùng
/// chung cho cả AddExpenseSheet lẫn EditExpenseSheet để 2 form luôn khớp nhau.
private struct QuantityPriceRow: View {
    @Binding var soLuong: Double
    @Binding var donGia: Double
    var thanhTien: Double

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 8
            let unit = (geo.size.width - spacing * 2) / 3.3
            HStack(spacing: spacing) {
                HStack(spacing: 4) {
                    Button {
                        if soLuong > 1 { soLuong -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .disabled(soLuong <= 1)
                    Text(soLuong.formatted()).font(.subheadline.bold()).frame(minWidth: 16)
                    Button {
                        soLuong += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
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
                .frame(width: unit * 1.3, alignment: .center)

                Text(HoaDonFormatting.money(thanhTien))
                    .font(.subheadline.bold())
                    .foregroundColor(.brandPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: unit, alignment: .trailing)
            }
        }
        .frame(height: 34)
    }
}

struct AddExpenseSheet: View {
    let date: Date
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nguyenLieuList: [NguyenLieuDto] = []
    @State private var searchText = ""
    @State private var selected: NguyenLieuDto?
    @State private var soLuong: Double = 1
    @State private var donGia: Double = 0
    @State private var ghiChu = ""
    @State private var billThang = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var addingNguyenLieu = false

    /// Rỗng khi chưa gõ gì — danh sách nguyên liệu quá dài để liệt kê hết như dropdown, phải gõ
    /// tìm mới hiện kết quả (khớp cách sửa "Thêm món" bên HoaDonCreateFormView.ProductPickerSheet).
    private var filteredList: [NguyenLieuDto] {
        guard !searchText.isEmpty else { return [] }
        return nguyenLieuList.filter { $0.ten.matchesSearch(searchText) }
    }

    private var thanhTien: Double { soLuong * donGia }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nguyên liệu") {
                    TextField("Tìm nguyên liệu...", text: $searchText)
                    if let selected {
                        HStack {
                            Text(selected.ten).bold()
                            Spacer()
                            Button("Đổi") { self.selected = nil }.font(.footnote)
                        }
                    } else {
                        ForEach(filteredList.prefix(30)) { nl in
                            Button {
                                selected = nl
                                searchText = ""
                                if nl.giaNhap > 0 { donGia = nl.giaNhap }
                            } label: {
                                Text(nl.ten)
                            }
                        }

                        // Gõ tên không khớp nguyên liệu nào có sẵn (VD "Dao Thái Lan" lần đầu mua) —
                        // cho thêm mới ngay tại đây thay vì phải mở Desktop/web quản lý danh mục.
                        if !searchText.isEmpty && filteredList.isEmpty {
                            Button {
                                Task { await addNewNguyenLieu() }
                            } label: {
                                if addingNguyenLieu {
                                    ProgressView()
                                } else {
                                    Label("Thêm nguyên liệu mới \"\(searchText)\"", systemImage: "plus.circle")
                                }
                            }
                            .disabled(addingNguyenLieu)
                        }
                    }
                }

                // Khớp hàng Số lượng/Đơn giá/Thành tiền bên "Thêm món"
                // (HoaDonCreateFormView.ProductPickerSheet.configSection) qua QuantityPriceRow dùng chung.
                Section("Số lượng & đơn giá") {
                    QuantityPriceRow(soLuong: $soLuong, donGia: $donGia, thanhTien: thanhTien)
                }

                Section {
                    TextField("Ghi chú", text: $ghiChu)
                    Toggle("Bill tháng", isOn: $billThang)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle("Thêm chi tiêu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu") {
                        Task { await save() }
                    }
                    .disabled(selected == nil || donGia <= 0 || saving)
                }
            }
        }
        .task { nguyenLieuList = await APIClient.shared.getNguyenLieu() }
    }

    private func addNewNguyenLieu() async {
        let ten = searchText.trimmingCharacters(in: .whitespaces)
        guard !ten.isEmpty else { return }
        addingNguyenLieu = true
        errorMessage = nil
        let result = await APIClient.shared.createNguyenLieu(ten: ten)
        addingNguyenLieu = false
        if result.success, let nl = result.nguyenLieu {
            nguyenLieuList.append(nl)
            selected = nl
            searchText = ""
        } else {
            errorMessage = result.message ?? "Không thêm được nguyên liệu."
        }
    }

    private func save() async {
        guard let selected else { return }
        saving = true
        errorMessage = nil
        let dateIso = DateNavFormat.queryDate.string(from: date) + "T00:00:00"
        let body = ChiTieuHangNgayCreateRequest(
            ten: selected.ten, soLuong: soLuong, donGia: donGia, thanhTien: thanhTien,
            ghiChu: ghiChu.isEmpty ? nil : ghiChu,
            // NgayGio do server quyết định (VietnamTime.Now) — giá trị gửi đây không được server dùng.
            ngay: dateIso, ngayGio: dateIso, nguyenLieuId: selected.id, billThang: billThang
        )
        let result = await APIClient.shared.createChiTieu(body)
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không thêm được chi tiêu."
        }
    }
}
