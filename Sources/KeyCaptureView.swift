import SwiftUI
import UIKit

/// View vô hình bắt bàn phím thô (không dùng UITextField vì cần override cả phím mũi tên qua
/// `keyCommands`, UITextField sẽ nuốt trước khi tới được đây). `insertText` nhận ký tự thường (kể cả
/// chuỗi dài do gõ nhanh/gợi ý) VÀ "\n" khi bấm Return — tách riêng ra thành phím đặc biệt.
final class KeyCaptureUIView: UIView, UIKeyInput {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?
    var onSpecialKey: ((String) -> Void)?

    var hasText: Bool { false }

    func insertText(_ text: String) {
        if text == "\n" {
            onSpecialKey?("Enter")
        } else {
            onInsertText?(text)
        }
    }

    func deleteBackward() {
        onDeleteBackward?()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDown)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)),
        ]
    }

    @objc private func handleLeft() { onSpecialKey?("ArrowLeft") }
    @objc private func handleRight() { onSpecialKey?("ArrowRight") }
    @objc private func handleUp() { onSpecialKey?("ArrowUp") }
    @objc private func handleDown() { onSpecialKey?("ArrowDown") }
    @objc private func handleEscape() { onSpecialKey?("Escape") }
}

struct KeyCaptureView: UIViewRepresentable {
    @Binding var isActive: Bool
    let onText: (String) -> Void
    let onSpecial: (String) -> Void

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onInsertText = onText
        view.onDeleteBackward = { onSpecial("Backspace") }
        view.onSpecialKey = onSpecial
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        if isActive && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isActive && uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }
}

/// SwiftUI không có gesture 2-ngón thuần tuý đáng tin cậy — bọc UIPanGestureRecognizer để dùng làm
/// "cuộn chuột" khi ở chế độ Điều khiển.
struct TwoFingerScrollView: UIViewRepresentable {
    let onScroll: (CGPoint, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll) }

    final class Coordinator: NSObject {
        var onScroll: (CGPoint, CGFloat) -> Void
        private var lastTranslationY: CGFloat = 0

        init(onScroll: @escaping (CGPoint, CGFloat) -> Void) { self.onScroll = onScroll }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastTranslationY = 0
            case .changed:
                let translation = gesture.translation(in: gesture.view)
                let delta = translation.y - lastTranslationY
                lastTranslationY = translation.y
                onScroll(gesture.location(in: gesture.view), delta)
            default:
                break
            }
        }
    }
}
