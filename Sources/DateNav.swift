import SwiftUI

// Tách từ HoaDonListView để tái dùng cho các tab theo ngày/tháng khác (Thanh toán, Chi tiêu,
// 7 trang báo cáo) — khớp DateNavHelper.kt bên AppMobileAndroid.

enum DateNavFormat {
    static let queryDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Chỉ Ngày/Tháng, bỏ năm — theo yêu cầu rút gọn UI (năm không cần thiết cho việc chọn nhanh).
    static let dayTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()

    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()
}

/// Gộp chọn ngày + ô tìm kiếm chung 1 dòng — thay cho DayNavBar+SearchBar 2 dòng riêng, bỏ hẳn 2 nút
/// chevron điều hướng (chỉ còn bấm vào ngày để mở DatePicker).
struct DaySearchBar: View {
    @Binding var date: Date
    @Binding var searchText: String
    var placeholder: String = "Tìm..."
    /// Nút phụ (vd "+") đặt bên trái cùng, trước nút ngày — tìm kiếm vẫn luôn ở giữa.
    var leading: AnyView? = nil
    /// Nút phụ (vd icon lọc nhanh) đặt bên phải cùng, sau ô tìm kiếm.
    var trailing: AnyView? = nil
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 8) {
            if let leading { leading }

            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(DateNavFormat.dayTitle.string(from: date))
                }
                .font(.subheadline.bold())
                .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.plain)
            .fixedSize()

            SearchFieldRow(text: $searchText, placeholder: placeholder)

            if let trailing { trailing }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Chọn ngày", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Xong") {
                                showPicker = false
                                onChange()
                            }
                        }
                    }
                Spacer()
            }
            .presentationDetents([.medium])
        }
    }
}

/// Chỉ chọn ngày, không search — dùng cho trang không có ô tìm kiếm (vd ThongKeView). Canh giữa
/// (không Spacer 1 bên) vì trang này không có phần tử nào khác cùng hàng cần cân bằng.
struct DayDateBar: View {
    @Binding var date: Date
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack {
            Spacer()
            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(DateNavFormat.dayTitle.string(from: date))
                }
                .font(.subheadline.bold())
                .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Chọn ngày", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Xong") {
                                showPicker = false
                                onChange()
                            }
                        }
                    }
                Spacer()
            }
            .presentationDetents([.medium])
        }
    }
}

