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
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 8) {
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

/// Chỉ chọn ngày, không search — dùng cho trang không có ô tìm kiếm (vd ThongKeView).
struct DayDateBar: View {
    @Binding var date: Date
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack {
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

/// Gộp chọn tháng + ô tìm kiếm chung 1 dòng, giống DaySearchBar. Dùng khi trang có search
/// (MonthListView truyền `matches`); trang không có search dùng MonthDateBar (chỉ chọn tháng).
struct MonthSearchBar: View {
    @Binding var year: Int
    @Binding var month: Int
    @Binding var searchText: String
    var placeholder: String = "Tìm..."
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MonthPickerButton(year: $year, month: $month, onChange: onChange)
            SearchFieldRow(text: $searchText, placeholder: placeholder)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Chỉ chọn tháng, không search — trang report nào không truyền `matches` cho MonthListView.
struct MonthDateBar: View {
    @Binding var year: Int
    @Binding var month: Int
    var onChange: () -> Void

    var body: some View {
        HStack {
            MonthPickerButton(year: $year, month: $month, onChange: onChange)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct MonthPickerButton: View {
    @Binding var year: Int
    @Binding var month: Int
    var onChange: () -> Void
    @State private var showPicker = false
    @State private var pickerDate = Date()

    private var titleText: String {
        String(format: "%02d/%d", month, year)
    }

    var body: some View {
        Button {
            var comps = DateComponents()
            comps.year = year; comps.month = month; comps.day = 1
            pickerDate = Calendar.current.date(from: comps) ?? Date()
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(titleText)
            }
            .font(.subheadline.bold())
            .foregroundColor(.brandPrimary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Chọn tháng", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Xong") {
                                let cal = Calendar.current
                                year = cal.component(.year, from: pickerDate)
                                month = cal.component(.month, from: pickerDate)
                                showPicker = false
                                onChange()
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }
}
