import PhotosUI
import SwiftUI

/// 2 nút "Thêm từ ảnh" cạnh nút "+" thường trong tab Chi tiêu — chọn ảnh hoá đơn mua hàng (thư viện
/// hoặc chụp thẳng bằng camera), gửi lên Backend (Gemini Vision) đọc từng dòng + tự gợi ý map
/// NguyenLieu, rồi mở form duyệt/sửa trước khi lưu thật. Xem ReceiptParseService (Backend) cho phần
/// đọc ảnh + học mapping. Dùng chung 1 state (loading/lỗi/kết quả) vì chỉ 1 luồng chạy tại 1 thời điểm.
struct ReceiptImportButton: View {
    let date: Date
    let onSaved: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var parseResult: ReceiptParseResultDto?

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                iconOrSpinner("photo.on.rectangle")
            }
            .disabled(loading)
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task { await handlePickedFromLibrary(item) }
            }

            Button {
                showCamera = true
            } label: {
                iconOrSpinner("camera.fill")
            }
            .disabled(loading)
        }
        .foregroundColor(.brandPrimary)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
                Task { await handleImageData(data) }
            }
            .ignoresSafeArea()
        }
        .alert("Đọc ảnh thất bại", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(loadError ?? "")
        }
        .sheet(item: $parseResult) { result in
            ReceiptReviewSheet(date: date, result: result) {
                onSaved()
            }
        }
    }

    @ViewBuilder
    private func iconOrSpinner(_ systemName: String) -> some View {
        if loading {
            ProgressView().frame(width: 30, height: 30)
        } else {
            Image(systemName: systemName).font(.system(size: 28))
        }
    }

    private func handlePickedFromLibrary(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            loadError = "Không đọc được ảnh đã chọn."
            return
        }
        await handleImageData(data)
    }

    private func handleImageData(_ data: Data) async {
        loading = true
        defer { loading = false }
        let (result, message) = await APIClient.shared.parseReceipt(imageData: data)
        if let result, !result.lines.isEmpty {
            parseResult = result
        } else {
            loadError = message ?? "Không đọc được dòng nào từ ảnh."
        }
    }
}

/// Bọc UIImagePickerController(sourceType: .camera) — PhotosPicker (SwiftUI) không hỗ trợ chụp
/// camera trực tiếp trước iOS 17, deployment target app đang là iOS 16.
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

extension ReceiptParseResultDto: Identifiable {
    var id: Int { lines.count }
}

private struct ReceiptDraftLine: Identifiable {
    let id = UUID()
    let rawText: String
    var nguyenLieuId: String?
    var nguyenLieuTen: String?
    var fromLearnedAlias: Bool
    var soLuong: Double
    var donGia: Double
    var searchText: String = ""
    var included: Bool = true

    var thanhTien: Double { soLuong * donGia }
}

/// Form duyệt/sửa các dòng Gemini đọc được trước khi lưu thật — mỗi dòng bắt buộc chọn NguyenLieu
/// (kể cả khi Gemini đã gợi ý sẵn, người dùng vẫn đổi được), có thể bỏ dòng không muốn lưu. Lưu qua
/// POST /api/ChiTieuHangNgay/bulk kèm rawText từng dòng để Backend tự học mapping cho lần đọc ảnh sau.
private struct ReceiptReviewSheet: View {
    let date: Date
    let result: ReceiptParseResultDto
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [ReceiptDraftLine]
    @State private var nguyenLieuList: [NguyenLieuDto] = []
    @State private var billThang = false
    @State private var saving = false
    @State private var errorMessage: String?

    init(date: Date, result: ReceiptParseResultDto, onSaved: @escaping () -> Void) {
        self.date = date
        self.result = result
        self.onSaved = onSaved
        _lines = State(initialValue: result.lines.map { l in
            ReceiptDraftLine(
                rawText: l.rawText,
                nguyenLieuId: l.suggestedNguyenLieuId,
                nguyenLieuTen: l.suggestedNguyenLieuTen,
                fromLearnedAlias: l.suggestedFromLearnedAlias,
                soLuong: l.soLuong,
                donGia: l.donGia
            )
        })
    }

    private var includedLines: [ReceiptDraftLine] { lines.filter(\.included) }
    private var totalText: String {
        HoaDonFormatting.money(includedLines.reduce(0) { $0 + $1.thanhTien })
    }
    private var canSave: Bool {
        !includedLines.isEmpty && includedLines.allSatisfy { $0.nguyenLieuId != nil && $0.donGia > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Bill tháng (nhà cung cấp)", isOn: $billThang)
                } footer: {
                    Text("Áp dụng chung cho tất cả dòng bên dưới.")
                }

                ForEach($lines) { $line in
                    Section {
                        lineRow($line)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle("Duyệt hoá đơn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu (\(totalText))") { Task { await save() } }
                        .disabled(!canSave || saving)
                }
            }
        }
        .task { nguyenLieuList = await APIClient.shared.getNguyenLieu() }
    }

    @ViewBuilder
    private func lineRow(_ line: Binding<ReceiptDraftLine>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.wrappedValue.rawText).font(.subheadline.bold())
                if line.wrappedValue.nguyenLieuId == nil {
                    Text("Chưa khớp — chọn nguyên liệu").font(.caption).foregroundColor(.warningColor)
                } else if line.wrappedValue.fromLearnedAlias {
                    Text("Khớp từ lần trước").font(.caption).foregroundColor(.successColor)
                }
            }
            Spacer()
            Button {
                line.wrappedValue.included.toggle()
            } label: {
                Image(systemName: line.wrappedValue.included ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(line.wrappedValue.included ? .brandPrimary : .textMuted)
            }
        }

        if line.wrappedValue.included {
            nguyenLieuPicker(line)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Số lượng").font(.caption2).foregroundColor(.textMuted)
                    Stepper("\(line.wrappedValue.soLuong.formatted())", value: line.soLuong, in: 0.1...9999, step: 1)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Đơn giá").font(.caption2).foregroundColor(.textMuted)
                    TextField("0", value: line.donGia, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 84)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Thành tiền").font(.caption2).foregroundColor(.textMuted)
                    Text(HoaDonFormatting.money(line.wrappedValue.thanhTien))
                        .font(.subheadline.bold())
                        .foregroundColor(.brandPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func nguyenLieuPicker(_ line: Binding<ReceiptDraftLine>) -> some View {
        if let ten = line.wrappedValue.nguyenLieuTen {
            HStack {
                Text(ten).bold()
                Spacer()
                Button("Đổi") {
                    line.wrappedValue.nguyenLieuId = nil
                    line.wrappedValue.nguyenLieuTen = nil
                }.font(.footnote)
            }
        } else {
            TextField("Tìm nguyên liệu...", text: line.searchText)
            if !line.wrappedValue.searchText.isEmpty {
                let matches = nguyenLieuList.filter { $0.ten.matchesSearch(line.wrappedValue.searchText) }.prefix(20)
                ForEach(matches) { nl in
                    Button {
                        line.wrappedValue.nguyenLieuId = nl.id
                        line.wrappedValue.nguyenLieuTen = nl.ten
                        line.wrappedValue.searchText = ""
                        if nl.giaNhap > 0 && line.wrappedValue.donGia <= 0 {
                            line.wrappedValue.donGia = nl.giaNhap
                        }
                    } label: {
                        Text(nl.ten)
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let dateIso = DateNavFormat.queryDate.string(from: date) + "T00:00:00"
        let items = includedLines.compactMap { line -> ChiTieuHangNgayBulkItemRequest? in
            guard let nguyenLieuId = line.nguyenLieuId else { return nil }
            return ChiTieuHangNgayBulkItemRequest(
                nguyenLieuId: nguyenLieuId,
                ten: line.nguyenLieuTen,
                soLuong: line.soLuong,
                donGia: line.donGia,
                thanhTien: line.thanhTien,
                ghiChu: nil,
                billThang: billThang,
                rawText: line.rawText
            )
        }
        let body = ChiTieuHangNgayBulkCreateRequest(ngay: dateIso, ngayGio: dateIso, billThang: billThang, items: items)
        let result = await APIClient.shared.bulkCreateChiTieu(body)
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}
