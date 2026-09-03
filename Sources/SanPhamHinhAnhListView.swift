import PhotosUI
import SwiftUI

/// Màn "Ảnh menu" — cho nhân viên đổi/thêm ảnh món ăn cho AppDatHangIOS (app khách đặt hàng), vì
/// menu chỉ tự khớp sẵn 92/233 món (tên trùng với ảnh có sẵn ở AppShippingBackend lúc seed), phần
/// còn lại + món đổi ảnh về sau phải cập nhật tay qua đây. Vào từ tab Menu > "Ảnh menu".
struct SanPhamHinhAnhListView: View {
    @State private var sanPhams: [SanPhamDto] = []
    @State private var loading = true
    @State private var query = ""
    @State private var uploadingId: String?
    @State private var errorMessage: String?

    private var filtered: [SanPhamDto] {
        sanPhams
            .filter { $0.ten.matchesSearch(query) }
            .sorted { $0.ten < $1.ten }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { sp in
                        SanPhamHinhAnhRow(
                            sanPham: sp,
                            uploading: uploadingId == sp.id,
                            onPicked: { data, mime in Task { await upload(id: sp.id, data: data, mime: mime) } }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "Tìm món...")
        .navigationTitle("Ảnh menu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Đổi ảnh thất bại", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        loading = true
        sanPhams = await APIClient.shared.getSanPhamList()
        loading = false
    }

    private func upload(id: String, data: Data, mime: String) async {
        uploadingId = id
        defer { uploadingId = nil }
        let (url, message) = await APIClient.shared.uploadSanPhamHinhAnh(id: id, imageData: data, mimeType: mime)
        if let url {
            if let idx = sanPhams.firstIndex(where: { $0.id == id }) {
                let old = sanPhams[idx]
                // Backend giữ nguyên tên file (id.ext) mỗi lần đổi ảnh nên URL không đổi —
                // gắn query cache-bust để AsyncImage tải lại ngay, không phải thoát vào lại màn hình.
                let bustedUrl = url + "?v=\(Int(Date().timeIntervalSince1970))"
                sanPhams[idx] = SanPhamDto(
                    id: old.id, ten: old.ten, ngungBan: old.ngungBan, tenNhomSanPham: old.tenNhomSanPham,
                    thuTu: old.thuTu, bienThe: old.bienThe, timKiem: old.timKiem, hinhAnh: bustedUrl)
            }
        } else {
            errorMessage = message ?? "Không cập nhật được ảnh."
        }
    }
}

private struct SanPhamHinhAnhRow: View {
    let sanPham: SanPhamDto
    let uploading: Bool
    let onPicked: (Data, String) -> Void

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            Text(sanPham.ten)
                .font(.subheadline)
            Spacer()
            PhotosPicker(selection: $pickerItem, matching: .images) {
                if uploading {
                    ProgressView().frame(width: 28, height: 28)
                } else {
                    Image(systemName: sanPham.hinhAnh == nil ? "plus.circle" : "arrow.triangle.2.circlepath.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.brandPrimary)
                }
            }
            .disabled(uploading)
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    defer { pickerItem = nil }
                    // Ảnh gốc từ thư viện có thể vài MB (HEIC/JPEG full-res) — resize + nén trước khi
                    // upload vì thumbnail chỉ hiển thị 48x48, tránh upload chậm và ảnh nặng làm cả
                    // danh sách tải lâu về sau.
                    guard let raw = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: raw),
                          let data = image.resizedForMenuUpload().jpegData(compressionQuality: 0.75) else { return }
                    onPicked(data, "image/jpeg")
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let hinhAnh = sanPham.hinhAnh, let url = URL(string: hinhAnh) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.textMuted.opacity(0.12)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.textMuted.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(sanPham.ten.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                        .font(.headline)
                        .foregroundColor(.brandPrimary)
                )
        }
    }
}

private extension UIImage {
    func resizedForMenuUpload(maxDimension: CGFloat = 800) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
