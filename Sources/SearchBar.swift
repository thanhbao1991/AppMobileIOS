import SwiftUI
import UIKit

/// Ô tìm kiếm client-side dùng chung cho mọi tab danh sách — khớp hành vi search trên
/// TraSuaApp.Mobile (web mobile cũ): lọc theo tên khách/ghi chú/tên món ngay trên dữ liệu đã tải,
/// không gọi API riêng.
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Tìm..."

    var body: some View {
        SearchFieldRow(text: $text, placeholder: placeholder)
            .padding(.horizontal)
            .padding(.vertical, 8)
    }
}

/// Phần lõi ô tìm kiếm (không padding ngoài) — dùng riêng khi cần đặt chung dòng với nút chọn
/// ngày (xem DaySearchBar trong DateNav.swift).
struct SearchFieldRow: View {
    @Binding var text: String
    var placeholder: String = "Tìm..."

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundColor(.textMuted).font(.system(size: 14))
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
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
    /// Mặc định KHÔNG phân biệt dấu tiếng Việt (gõ "ca phe" vẫn khớp "Cà Phê") — trừ tab Công nợ
    /// (truyền diacriticInsensitive: false), nơi cần gõ ĐÚNG dấu để tránh khớp nhầm 2 khách tên gần
    /// giống nhau (nợ là tiền thật, không muốn thu/gửi bill nhầm người).
    func matchesSearch(_ query: String, diacriticInsensitive: Bool = true) -> Bool {
        guard !query.isEmpty else { return true }
        var options: String.CompareOptions = [.caseInsensitive]
        if diacriticInsensitive { options.insert(.diacriticInsensitive) }
        return range(of: query, options: options) != nil
    }
}

func anyMatchesSearch(_ query: String, diacriticInsensitive: Bool = true, _ fields: String?...) -> Bool {
    guard !query.isEmpty else { return true }
    return fields.contains { $0?.matchesSearch(query, diacriticInsensitive: diacriticInsensitive) == true }
}
