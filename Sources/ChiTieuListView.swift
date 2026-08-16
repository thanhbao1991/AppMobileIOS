import SwiftUI

/// Chi tiêu hằng ngày — GET/POST /api/ChiTieuHangNgay (khác Android hiện vẫn sample). List theo
/// ngày (DayNavBar) + nút "+" mở AddExpenseSheet chọn nguyên liệu thật từ /api/NguyenLieuBanHang.
struct ChiTieuListView: View {
    @State private var currentDate = Date()
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = false
    @State private var showAddSheet = false

    private var totalText: String {
        HoaDonFormatting.money(items.reduce(0) { $0 + $1.thanhTien })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayNavBar(date: $currentDate) { Task { await load() } }

                if loading {
                    Spacer(); ProgressView(); Spacer()
                } else if items.isEmpty {
                    Spacer()
                    Text("Chưa có chi tiêu nào").foregroundColor(.textMuted)
                    Spacer()
                } else {
                    List(items) { item in
                        ChiTieuRowView(item: item)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                Button {
                    showAddSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Thêm chi tiêu · \(totalText)")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Chi tiêu")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
        .sheet(isPresented: $showAddSheet) {
            AddExpenseSheet(date: currentDate) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getChiTieuByDay(DateNavFormat.queryDate.string(from: currentDate))
        loading = false
    }
}

private struct ChiTieuRowView: View {
    let item: ChiTieuHangNgayDto

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.ten).font(.subheadline.bold())
                    if item.billThang {
                        Text("#tháng").font(.caption2.bold()).foregroundColor(.brandPrimary)
                    } else {
                        Text("#ngày").font(.caption2.bold()).foregroundColor(.textMuted)
                    }
                }
                Text("\(HoaDonFormatting.money(item.donGia)) × \(item.soLuong.formatted())")
                    .font(.footnote).foregroundColor(.textMuted)
                if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                    Text(ghiChu).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
        }
    }
}

struct AddExpenseSheet: View {
    let date: Date
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nguyenLieuList: [NguyenLieuBanHangDto] = []
    @State private var searchText = ""
    @State private var selected: NguyenLieuBanHangDto?
    @State private var soLuong: Double = 1
    @State private var donGia: Double = 0
    @State private var ghiChu = ""
    @State private var billThang = false
    @State private var saving = false
    @State private var errorMessage: String?

    private var filteredList: [NguyenLieuBanHangDto] {
        guard !searchText.isEmpty else { return nguyenLieuList }
        return nguyenLieuList.filter { $0.ten.localizedCaseInsensitiveContains(searchText) }
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
                            } label: {
                                Text(nl.ten)
                            }
                        }
                    }
                }

                Section("Số lượng & đơn giá") {
                    Stepper("Số lượng: \(soLuong.formatted())", value: $soLuong, in: 1...9999)
                    HStack {
                        Text("Đơn giá")
                        Spacer()
                        TextField("0", value: $donGia, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Thành tiền")
                        Spacer()
                        Text(HoaDonFormatting.money(thanhTien)).bold()
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
        .task { nguyenLieuList = await APIClient.shared.getNguyenLieuBanHang() }
    }

    private func save() async {
        guard let selected else { return }
        saving = true
        errorMessage = nil
        let dateIso = DateNavFormat.queryDate.string(from: date) + "T00:00:00"
        let body = ChiTieuHangNgayCreateRequest(
            soLuong: soLuong, donGia: donGia, thanhTien: thanhTien, ghiChu: ghiChu.isEmpty ? nil : ghiChu,
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
