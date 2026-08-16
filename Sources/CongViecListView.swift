import SwiftUI

/// Công việc nội bộ — GET/POST/PUT /api/CongViecNoiBo. Có API thật (khác Android hiện vẫn sample),
/// nên làm đủ: tick hoàn thành (PUT) + thêm việc mới (POST). Không làm cảnh báo/xoá (NgayCanhBao,
/// XNgayCanhBao) — đơn giản hoá cho bản mobile.
struct CongViecListView: View {
    @State private var items: [CongViecNoiBoDto] = []
    @State private var loading = false
    @State private var newTen = ""
    @State private var adding = false
    @State private var searchText = ""

    private var sortedItems: [CongViecNoiBoDto] {
        items
            .filter { $0.ten.matchesSearch(searchText) }
            .sorted { !$0.daHoanThanh && $1.daHoanThanh }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm việc...")

                if loading {
                    Spacer(); ProgressView(); Spacer()
                } else if sortedItems.isEmpty {
                    Spacer()
                    Text("Chưa có việc nào").foregroundColor(.textMuted)
                    Spacer()
                } else {
                    List(sortedItems) { item in
                        CongViecRowView(item: item) { toggled in
                            Task { await toggle(item, done: toggled) }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                HStack {
                    TextField("Thêm việc mới...", text: $newTen)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await addNew() }
                    } label: {
                        if adding { ProgressView() } else { Image(systemName: "plus.circle.fill").font(.title2) }
                    }
                    .disabled(newTen.trimmingCharacters(in: .whitespaces).isEmpty || adding)
                }
                .padding()
            }
            .navigationTitle("Công việc")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongViecList()
        loading = false
    }

    private func toggle(_ item: CongViecNoiBoDto, done: Bool) async {
        _ = await APIClient.shared.updateCongViec(id: item.id, ten: item.ten, daHoanThanh: done, ngayGio: item.ngayGio)
        await load()
    }

    private func addNew() async {
        let ten = newTen.trimmingCharacters(in: .whitespaces)
        guard !ten.isEmpty else { return }
        adding = true
        _ = await APIClient.shared.createCongViec(ten: ten)
        newTen = ""
        await load()
        adding = false
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
