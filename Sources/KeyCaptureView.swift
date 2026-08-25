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

/// TOÀN BỘ cử chỉ điều khiển (tap=click, long-press=chuột phải, 1 ngón kéo=pan khung nhìn, 2 ngón
/// kéo=cuộn, pinch=zoom) dùng `UIGestureRecognizer` CHUẨN của UIKit — KHÔNG tự viết state machine
/// touchesBegan/Moved/Ended thủ công như bản trước (bản đó có bug thật: 1 lần touchesEnded/Cancelled
/// bị lỡ — vd đổi app iOS giữa lúc đang pinch 2 ngón — làm state kẹt vĩnh viễn, mọi tap sau đó bị
/// chặn câm lặng tới khi khởi động lại app). Theo đúng tinh thần RustDesk (Flutter `RawGestureDetector`
/// + các `GestureRecognizer` chuẩn của framework, xem
/// `flutter/lib/common/widgets/remote_input.dart`) — dùng recognizer đã được Apple/Google kiểm thử kỹ
/// thay vì tự quản lý vòng đời touch, loại bỏ hẳn lớp bug "state kẹt" này.
final class RemoteControlSurfaceView: UIView {
    var onTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    private let tapRecognizer = UITapGestureRecognizer()
    private let longPressRecognizer = UILongPressGestureRecognizer()
    private let panRecognizer = UIPanGestureRecognizer()
    private let twoFingerPanRecognizer = UIPanGestureRecognizer()
    private let pinchRecognizer = UIPinchGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true

        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.addTarget(self, action: #selector(handleTap))

        longPressRecognizer.minimumPressDuration = 0.5
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress))

        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.addTarget(self, action: #selector(handlePan))

        twoFingerPanRecognizer.minimumNumberOfTouches = 2
        twoFingerPanRecognizer.maximumNumberOfTouches = 2
        twoFingerPanRecognizer.addTarget(self, action: #selector(handleTwoFingerPan))

        pinchRecognizer.addTarget(self, action: #selector(handlePinch))

        // pinch + cuộn 2 ngón CẦN chạy đồng thời (1 cử chỉ 2 ngón thật luôn lẫn cả xê dịch lẫn co
        // giãn) — UIKit mặc định các recognizer loại trừ nhau, phải khai riêng qua delegate mới cho
        // phép cả 2 cùng nhận diện 1 lượt chạm.
        twoFingerPanRecognizer.delegate = self
        pinchRecognizer.delegate = self

        [tapRecognizer, longPressRecognizer, panRecognizer, twoFingerPanRecognizer, pinchRecognizer]
            .forEach(addGestureRecognizer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended else { return }
        onTap?(g.location(in: self))
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        onLongPress?(g.location(in: self))
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        onPan?(CGSize(width: t.x, height: t.y))
    }

    @objc private func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        onScroll?(g.location(in: self), t.y)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed else { return }
        let factor = g.scale
        g.scale = 1
        onPinch?(factor)
    }
}

extension RemoteControlSurfaceView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let pair: Set = [ObjectIdentifier(gestureRecognizer), ObjectIdentifier(otherGestureRecognizer)]
        return pair == [ObjectIdentifier(pinchRecognizer), ObjectIdentifier(twoFingerPanRecognizer)]
    }
}

struct RemoteControlSurface: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void
    let onPan: (CGSize) -> Void
    let onScroll: (CGPoint, CGFloat) -> Void
    let onPinch: (CGFloat) -> Void

    func makeUIView(context: Context) -> RemoteControlSurfaceView {
        let view = RemoteControlSurfaceView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: RemoteControlSurfaceView, context: Context) {
        uiView.onTap = onTap
        uiView.onLongPress = onLongPress
        uiView.onPan = onPan
        uiView.onScroll = onScroll
        uiView.onPinch = onPinch
    }
}
