import SwiftUI

/// Chi tiêu hằng ngày — GET/PUT/DELETE /api/ChiTieuHangNgay. List theo ngày (DayNavBar) + search.
/// Vuốt trái để sửa ghi chú / xoá — khớp web mobile (OnPostEditAsync/OnPostDeleteAsync). Nút "+" thêm
/// chi tiêu nằm ở footer, khớp bố cục HoaDonListView (nút tròn cạnh tổng tiền, không còn label "Tổng chi").
struct ChiTieuListView: View {
    @State private var currentDate = Date()
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var editingItem: ChiTieuHangNgayDto?
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
                                ChiTieuRowView(item: item)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            Task { await delete(item) }
                                        } label: {
                                            Label("Xoá", systemImage: "trash")
                                        }
                                        Button {
                                            editingItem = item
                                        } label: {
                                            Label("Sửa", systemImage: "pencil")
                                        }
                                        .tint(.brandPrimary)
                                    }
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
        .sheet(item: $editingItem) { item in
            EditExpenseGhiChuSheet(item: item) {
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

    private func delete(_ item: ChiTieuHangNgayDto) async {
        let result = await APIClient.shared.deleteChiTieu(id: item.id)
        if result.success {
            items.removeAll { $0.id == item.id }
        }
    }
}

private struct ChiTieuRowView: View {
    let item: ChiTieuHangNgayDto

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
    }
}

/// Sửa ghi chú 1 dòng chi tiêu — khớp phạm vi web mobile (OnPostEditAsync chỉ đổi GhiChu, các field
/// khác giữ nguyên nhưng vẫn gửi đủ trong body PUT vì backend UpdateAsync ghi đè toàn bộ).
private struct EditExpenseGhiChuSheet: View {
    let item: ChiTieuHangNgayDto
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ghiChu: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(item: ChiTieuHangNgayDto, onSaved: @escaping () -> Void) {
        self.item = item
        self.onSaved = onSaved
        _ghiChu = State(initialValue: item.ghiChu ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(item.ten) {
                    TextField("Ghi chú", text: $ghiChu)
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
                    .disabled(saving)
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
            ten: item.ten, soLuong: item.soLuong, donGia: item.donGia, thanhTien: item.thanhTien,
            ghiChu: ghiChu.isEmpty ? nil : ghiChu, ngay: ngayIso, ngayGio: ngayGioIso,
            nguyenLieuId: item.nguyenLieuId, billThang: item.billThang
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
                    }
                }

                // Số lượng/đơn giá/thành tiền chung 1 hàng thay vì xếp chồng — khớp cách gộp bên
                // "Thêm món" (HoaDonCreateFormView.ProductPickerSheet.configSection).
                Section("Số lượng & đơn giá") {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Số lượng").font(.caption2).foregroundColor(.textMuted)
                            Stepper("\(soLuong.formatted())", value: $soLuong, in: 1...9999).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Đơn giá").font(.caption2).foregroundColor(.textMuted)
                            TextField("0", value: $donGia, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 84)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Thành tiền").font(.caption2).foregroundColor(.textMuted)
                            Text(HoaDonFormatting.money(thanhTien))
                                .font(.subheadline.bold())
                                .foregroundColor(.brandPrimary)
                        }
                    }
                }

                Section {
                    TextField("Ghi chú", text: $ghiChu)
                    Toggle("Bill tháng (nhà cung cấp)", isOn: $billThang)
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
