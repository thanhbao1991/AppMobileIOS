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
            .filter { !$0.ngungBan }
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
                sanPhams[idx] = SanPhamDto(id: sanPhams[idx].id, ten: sanPhams[idx].ten, ngungBan: sanPhams[idx].ngungBan, hinhAnh: url)
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
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
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
