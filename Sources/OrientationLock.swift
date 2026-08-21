import UIKit
import SwiftUI

/// App bị ép portrait-only (`project.yml`) trừ màn hình "Xem màn hình Desktop" cần xoay ngang
/// full màn hình. `AppDelegate.orientationLock` quyết định orientation cho phép — DesktopScreenView
/// đổi giá trị này khi vào/ra thay vì mở landscape cho toàn app.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}

enum OrientationLock {
    @MainActor
    static func lockLandscape() {
        AppDelegate.orientationLock = .landscape
        requestGeometryUpdate(.landscapeRight)
    }

    @MainActor
    static func lockPortrait() {
        AppDelegate.orientationLock = .portrait
        requestGeometryUpdate(.portrait)
    }

    @MainActor
    private static func requestGeometryUpdate(_ orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation == .portrait ? .portrait : .landscape))
    }
}
