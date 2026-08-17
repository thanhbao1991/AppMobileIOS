import SwiftUI

// Màu khớp AppMobileAndroid/res/values/colors.xml (Bootstrap-style) — giữ đồng bộ hình ảnh 2 nền tảng.
extension Color {
    static let brandPrimary = Color(red: 0x0D / 255, green: 0x6E / 255, blue: 0xFD / 255)
    static let textMuted = Color(red: 0x6C / 255, green: 0x75 / 255, blue: 0x7D / 255)
    static let successColor = Color(red: 0x19 / 255, green: 0x87 / 255, blue: 0x54 / 255)
    static let dangerColor = Color(red: 0xDC / 255, green: 0x35 / 255, blue: 0x45 / 255)
    static let warningColor = Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255)
    static let pinkColor = Color(red: 0xD6 / 255, green: 0x33 / 255, blue: 0x84 / 255)
}

enum HoaDonFormatting {
    static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.locale = Locale(identifier: "vi_VN")
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ value: Double) -> String {
        (moneyFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + " đ"
    }

    /// Viết tắt cho footer (vd "1807k") — không cần rõ số, chỉ cần ước lượng nhanh.
    static func moneyShort(_ value: Double) -> String {
        "\(Int((value / 1000).rounded()))k"
    }

    private static let isoInFormats: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"].map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    static func time(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "--:--" }
        for f in isoInFormats {
            if let date = f.date(from: iso) {
                let hm = DateFormatter()
                hm.dateFormat = "HH:mm"
                return hm.string(from: date)
            }
        }
        guard iso.count >= 16 else { return "--:--" }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(start, offsetBy: 5)
        return String(iso[start..<end])
    }

    /// Dùng cho dòng "Ghi nợ" trên tab Công nợ — chỉ cần Ngày/Tháng Giờ:Phút, không cần năm/giây.
    static func congNoTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "--:-- --/--" }
        for f in isoInFormats {
            if let date = f.date(from: iso) {
                let out = DateFormatter()
                out.dateFormat = "HH:mm dd/MM"
                out.locale = Locale(identifier: "vi_VN")
                return out.string(from: date)
            }
        }
        return "--:-- --/--"
    }

    static func phanLoaiLabel(_ phanLoai: String?) -> String {
        switch phanLoai {
        case "Tại Chỗ": return "Tại chỗ"
        case "Mv": return "Mua về"
        case "Mh": return "Mua hộ"
        case "App": return "App"
        default: return "Ship"
        }
    }

    static func phanLoaiColor(_ phanLoai: String?) -> Color {
        switch phanLoai {
        case "Tại Chỗ": return .successColor
        case "Mv": return .warningColor
        case "Mh": return .pinkColor
        case "App": return .dangerColor
        default: return .brandPrimary
        }
    }

    /// Nền tint card theo PhanLoai — khớp hex `.debt-card.detail-pl-*` bên Mobile web
    /// (`TraSuaApp.Mobile/Pages/HoaDonTab.cshtml`), để người dùng quen mắt với web không thấy lạ.
    static func phanLoaiBgColor(_ phanLoai: String?) -> Color {
        switch phanLoai {
        case "Tại Chỗ": return Color(red: 0xCD / 255, green: 0xED / 255, blue: 0xDA / 255)
        case "Mv": return Color(red: 0xFC / 255, green: 0xDF / 255, blue: 0xC4 / 255)
        case "Mh": return Color(red: 0xF7 / 255, green: 0xD3 / 255, blue: 0xE6 / 255)
        case "App": return Color(red: 0xFB / 255, green: 0xE7 / 255, blue: 0xE9 / 255)
        default: return Color(red: 0xD6 / 255, green: 0xE6 / 255, blue: 0xFB / 255) // Ship
        }
    }

    /// Port y hệt HoaDonSortService.GetSortOrder (Desktop) / AppMobileAndroid HoaDonTabFragment.sortPriority.
    /// Đơn Ghi nợ rớt xuống ưu tiên thấp nhất (7) BẤT KỂ phân loại — check "isNo" phải nằm TRƯỚC nhánh
    /// Ship-chưa-gán-shipper, sai thứ tự if/else ở đây từng khiến kết quả sai.
    static func sortPriority(_ item: HoaDonListDto) -> Int {
        let phanLoai = item.phanLoai
        let conLai = item.conLai
        let chuaCoShipper = phanLoai == "Ship" && (item.nguoiShip?.isEmpty ?? true)
        let isNo = !(item.ngayNo?.isEmpty ?? true)

        if conLai <= 0.0 && phanLoai == "Ship" && chuaCoShipper { return 1 }
        if conLai <= 0.0 { return 6 }
        if isNo { return 7 }
        if phanLoai == "Ship" && chuaCoShipper { return 1 }
        if phanLoai == "Ship" { return 5 }
        if phanLoai == "Mv" || phanLoai == "Mh" { return 2 }
        if phanLoai == "App" { return 3 }
        return 4 // Tại Chỗ
    }
}
