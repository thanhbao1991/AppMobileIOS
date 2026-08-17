import SwiftUI

/// Công việc nội bộ — GET/PUT /api/CongViecNoiBo. Chỉ tick hoàn thành, không thêm/xoá/cảnh báo
/// (NgayCanhBao, XNgayCanhBao) — đơn giản hoá cho bản mobile, footer chỉ hiện số việc còn lại.
struct CongViecListView: View {
    @State private var items: [CongViecNoiBoDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""

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
                    Text("Còn lại").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text("\(items.filter { !$0.daHoanThanh }.count) việc").font(.headline)
                }
                .padding()
            }
            .navigationTitle("Công việc")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
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
