import SwiftUI

/// Công việc nội bộ — GET/PUT /api/CongViecNoiBo. Chỉ tick hoàn thành, không thêm/xoá/cảnh báo
/// (NgayCanhBao, XNgayCanhBao) — đơn giản hoá cho bản mobile, footer chỉ hiện số việc còn lại.
struct CongViecListView: View {
    @State private var items: [CongViecNoiBoDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showAdd = false

    private var sortedItems: [CongViecNoiBoDto] {
        items
            .filter { $0.ten.matchesSearch(searchText) }
            .sorted { !$0.daHoanThanh && $1.daHoanThanh }
    }

    var body: some View {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm việc...")

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        if sortedItems.isEmpty {
                            Text("Chưa có việc nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(sortedItems) { item in
                                CongViecRowView(item: item) { toggled in
                                    Task { await toggle(item, done: toggled) }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                HStack {
                    Text("Chưa làm").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text("\(items.filter { !$0.daHoanThanh }.count) việc").font(.headline)
                }
                .padding()
            }
            .navigationTitle("Công việc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showAdd) {
                AddCongViecSheet {
                    Task { await load() }
                }
            }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongViecList()
        loading = false
        hasLoaded = true
    }

    private func toggle(_ item: CongViecNoiBoDto, done: Bool) async {
        _ = await APIClient.shared.updateCongViec(id: item.id, ten: item.ten, daHoanThanh: done, ngayGio: item.ngayGio)
        await load()
    }

}

private struct AddCongViecSheet: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten = ""
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Việc cần làm") {
                    TextField("Nội dung...", text: $ten)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle("Thêm công việc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Đang lưu..." : "Lưu") {
                        Task { await save() }
                    }
                    .disabled(ten.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let result = await APIClient.shared.createCongViec(ten: ten.trimmingCharacters(in: .whitespaces))
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không thêm được công việc."
        }
    }
}

private struct CongViecRowView: View {
    let item: CongViecNoiBoDto
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!item.daHoanThanh)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.daHoanThanh ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.daHoanThanh ? .successColor : .textMuted)
                    .font(.title3)
                Text(item.ten)
                    .strikethrough(item.daHoanThanh)
                    .foregroundColor(item.daHoanThanh ? .textMuted : .primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
