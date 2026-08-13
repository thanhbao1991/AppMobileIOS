import SwiftUI

// Web app thật (ASP.NET Core Razor, TraSuaApp.Mobile) chạy tại đây, đằng sau Cloudflare —
// bọc bằng WKWebView thay vì Safari để có icon/app riêng trên màn hình chính, không có
// thanh địa chỉ/tab. Không cần push/TTS nền nên không cần Apple Developer Program.
// "/" redirect qua http:// (không phải https://) trước khi Cloudflare 301 lại về https —
// iOS ATS chặn cứng bước trung gian http:// đó trong WKWebView (Safari lại tolerant/dùng HSTS
// cache nên không sao) → màn hình trắng vĩnh viễn không lỗi. Trỏ thẳng /Login (https, không qua
// hop http nào) để né hẳn, xem thêm NSExceptionDomains trong project.yml làm lưới an toàn.
private let mobileUrl = URL(string: "https://mobile.denncoffee.uk/Login")!

struct ContentView: View {
    var body: some View {
        WebView(url: mobileUrl)
    }
}
