import SwiftUI

/// Quản trị tin khuyến mãi hiện cho app khách (AppDatHangIOS, tab "Thông báo") — GET/POST/PUT/DELETE
/// /api/ThongBaoQuan. Toggle "Đang hoạt động" ẩn/hiện tin khỏi app khách mà không cần xoá.
struct ThongBaoQuanListView: View {
    @State private var items: [ThongBaoQuanDto] = []
    @State private var hasLoaded = false
    @State private var showAdd = false
    @State private var editing: ThongBaoQuanDto?

    var body: some View {
        Group {
            if !hasLoaded {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else {
                List {
                    if items.isEmpty {
                        Text("Chưa có thông báo/khuyến mãi nào")
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(items) { item in
                            ThongBaoQuanRowView(item: item) {
                                Task { await toggle(item) }
                            } onEdit: {
                                editing = item
                            } onDelete: {
                                Task { await delete(item) }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Thông báo/Khuyến mãi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            ThongBaoQuanEditSheet(existing: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            ThongBaoQuanEditSheet(existing: item) { Task { await load() } }
        }
    }

    private func load() async {
        items = await APIClient.shared.getThongBaoQuanList()
        hasLoaded = true
    }

    private func toggle(_ item: ThongBaoQuanDto) async {
        _ = await APIClient.shared.updateThongBaoQuan(
            id: item.id, tieude: item.tieude, noiDung: item.noiDung, dangHoatDong: !item.dangHoatDong)
        await load()
    }

    private func delete(_ item: ThongBaoQuanDto) async {
        _ = await APIClient.shared.deleteThongBaoQuan(id: item.id)
        await load()
    }
}

private struct ThongBaoQuanRowView: View {
    let item: ThongBaoQuanDto
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.tieude)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(item.dangHoatDong ? "Đang hiện" : "Đã ẩn")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(item.dangHoatDong ? Color.successColor : Color.textMuted)
                        .clipShape(Capsule())
                }
                Text(item.noiDung)
                    .font(.caption)
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
                if let ngayTao = item.ngayTao {
                    Text(HoaDonFormatting.congNoTime(ngayTao))
                        .font(.caption2)
                        .foregroundColor(.textMuted)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brandPrimary.pastelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Xoá", systemImage: "trash")
            }
            Button(action: onToggle) {
                Label(item.dangHoatDong ? "Ẩn" : "Hiện", systemImage: item.dangHoatDong ? "eye.slash" : "eye")
            }
            .tint(.brandPrimary)
        }
    }
}

private struct ThongBaoQuanEditSheet: View {
    let existing: ThongBaoQuanDto?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tieude: String
    @State private var noiDung: String
    @State private var dangHoatDong: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: ThongBaoQuanDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _tieude = State(initialValue: existing?.tieude ?? "")
        _noiDung = State(initialValue: existing?.noiDung ?? "")
        _dangHoatDong = State(initialValue: existing?.dangHoatDong ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tiêu đề") {
                    TextField("Vd: Flash Sale cuối tuần", text: $tieude)
                }
                Section("Nội dung") {
                    TextField("Nội dung hiện cho khách...", text: $noiDung, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Đang hoạt động (hiện cho khách)", isOn: $dangHoatDong)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm thông báo" : "Sửa thông báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu") {
                        Task { await save() }
                    }
                    .disabled(tieude.trimmingCharacters(in: .whitespaces).isEmpty
                        || noiDung.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let t = tieude.trimmingCharacters(in: .whitespaces)
        let n = noiDung.trimmingCharacters(in: .whitespaces)
        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateThongBaoQuan(id: existing.id, tieude: t, noiDung: n, dangHoatDong: dangHoatDong)
        } else {
            result = await APIClient.shared.createThongBaoQuan(tieude: t, noiDung: n, dangHoatDong: dangHoatDong)
        }
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}
