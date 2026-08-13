import SwiftUI

// Web app thật (ASP.NET Core Razor, TraSuaApp.Mobile) chạy tại đây, đằng sau Cloudflare —
// bọc bằng WKWebView thay vì Safari để có icon/app riêng trên màn hình chính, không có
// thanh địa chỉ/tab. Không cần push/TTS nền nên không cần Apple Developer Program.
private let mobileUrl = URL(string: "https://mobile.denncoffee.uk/")!

struct ContentView: View {
    var body: some View {
        WebView(url: mobileUrl)
    }
}
