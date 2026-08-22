import MessageUI
import SwiftUI

/// Bọc MFMessageComposeViewController (UIKit) để soạn sẵn 1 tin SMS — dùng khi khách không có
/// Zalo/Facebook để nhận ảnh "Gửi Bill" (share sheet), SMS là kênh chắc chắn tới được vì luôn cần
/// SĐT. Nội dung soạn sẵn nhưng KHÔNG tự gửi — luôn qua UI hệ thống, người dùng tự bấm Gửi, tránh
/// gửi nhầm/gửi ngoài ý muốn.
struct SMSComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true, completion: onFinish)
        }
    }
}
