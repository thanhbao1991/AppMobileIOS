import SwiftUI

/// Ô tìm kiếm client-side dùng chung cho mọi tab danh sách — khớp hành vi search trên
/// TraSuaApp.Mobile (web mobile cũ): lọc theo tên khách/ghi chú/tên món ngay trên dữ liệu đã tải,
/// không gọi API riêng.
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Tìm..."

    var body: some View {
        SearchFieldRow(text: $text, placeholder: placeholder)
            .padding(.horizontal)
            .padding(.bottom, 6)
    }
}

/// Phần lõi ô tìm kiếm (không padding ngoài) — dùng riêng khi cần đặt chung dòng với nút chọn
/// ngày/tháng (xem DaySearchBar/MonthSearchBar trong DateNav.swift).
struct SearchFieldRow: View {
    @Binding var text: String
    var placeholder: String = "Tìm..."

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.textMuted).font(.system(size: 14))
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.textMuted.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension String {
    /// So khớp không phân biệt hoa/thường, bỏ qua nil/rỗng — dùng cho mọi bộ lọc search client-side.
    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return localizedCaseInsensitiveContains(query)
    }
}

func anyMatchesSearch(_ query: String, _ fields: String?...) -> Bool {
    guard !query.isEmpty else { return true }
    return fields.contains { $0?.localizedCaseInsensitiveContains(query) == true }
}
