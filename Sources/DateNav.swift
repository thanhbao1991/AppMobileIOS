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

    static let dayTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
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

struct DayNavBar: View {
    @Binding var date: Date
    var onChange: () -> Void

    var body: some View {
        HStack {
            Button { change(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(DateNavFormat.dayTitle.string(from: date)).font(.headline)
            Spacer()
            Button { change(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func change(_ delta: Int) {
        date = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date
        onChange()
    }
}

struct MonthNavBar: View {
    @Binding var year: Int
    @Binding var month: Int
    var onChange: () -> Void

    private var titleText: String {
        String(format: "%02d/%d", month, year)
    }

    var body: some View {
        HStack {
            Button { change(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(titleText).font(.headline)
            Spacer()
            Button { change(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func change(_ delta: Int) {
        month += delta
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
        onChange()
    }
}
