import SwiftUI

@main
struct AppMobileIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(edges: .bottom)
                // Màu nền card (pastelBackground) cố định sáng bất kể theme, nhưng chữ mặc định
                // (.primary) tự đổi trắng theo Dark Mode hệ thống — gây chữ trắng trên nền sáng,
                // mất tương phản. Khoá app luôn Light để khớp bộ màu vốn thiết kế cho nền sáng.
                .preferredColorScheme(.light)
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
    }
}
