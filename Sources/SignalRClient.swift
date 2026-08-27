import Foundation

/// Client SignalR tối giản (JSON Hub Protocol qua WebSocket thuần, không phụ thuộc SPM ngoài —
/// tránh rủi ro CI unsigned build phải resolve package lạ). Port hành vi cốt lõi từ
/// TraSuaApp.Desktop/Helpers/SignalRClient.cs: negotiate → connect → nghe "EntityChanged" →
/// tự retry khi rớt kết nối. Access token đọc qua query "access_token" — khớp
/// ApiConfigurationExtensions.OnMessageReceived (Backend) chỉ chấp nhận token qua query cho hub.
/// (2026-08-27: bỏ hẳn phần "Xem màn hình Desktop" khỏi client này — invoke()/GetConnectedDesktops/
/// ScreenshotReceived — nay đi qua HTTP POST/GET thường, xem DesktopScreenView.swift. Chỉ còn lo
/// đúng 1 việc: relay "EntityChanged" cho EntityChangeBus.)
actor SignalRClient {
    static let shared = SignalRClient()

    private var task: URLSessionWebSocketTask?
    private var shouldRun = false
    private var retryDelay: UInt64 = 3
    private var loopTask: Task<Void, Never>?

    /// entityName, action, id, voice — nhận trên MainActor để các View cập nhật @State an toàn.
    /// voice là chuỗi "hiển thị||đọc" backend gửi kèm (rỗng nếu signal không có mô tả riêng) — dùng
    /// để báo lý do rung cho nhân viên (xem EntityChangeBus.notifyReceived).
    private var onEntityChanged: (@MainActor (String, String, String, String) -> Void)?

    func start(onEntityChanged: @escaping @MainActor (String, String, String, String) -> Void) {
        self.onEntityChanged = onEntityChanged
        guard !shouldRun else { return }
        shouldRun = true
        retryDelay = 3
        loopTask = Task { await connectLoop() }
    }

    /// Còn kết nối thật hay không — dùng để QUYẾT ĐỊNH có cần kickReconnect() hay không khi quay lại
    /// foreground, thay vì luôn ép reconnect vô điều kiện (trước đây làm vậy khiến app switch NHANH
    /// trong lúc background task (~30s) vẫn còn hiệu lực bị NGẮT reconnect không cần thiết — kết nối
    /// thật ra vẫn còn sống, chỉ là bị buộc tái tạo lại, tạo cảm giác "mất kết nối liền").
    var isConnected: Bool { task != nil }

    func stop() {
        shouldRun = false
        loopTask?.cancel()
        loopTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Buộc reconnect NGAY, bỏ qua backoff đang chờ (3-30s) — gọi khi app quay lại foreground
    /// (`scenePhase == .active`). Không có bước này, sau khi đổi app qua lại, kết nối chết âm thầm
    /// và mọi thao tác sẽ không làm gì cho tới khi backoff tự chạy tới lượt.
    func kickReconnect() {
        guard shouldRun else { return }
        loopTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        retryDelay = 3
        loopTask = Task { await connectLoop() }
    }

    private func connectLoop() async {
        // Task.isCancelled bắt buộc phải kiểm — kickReconnect() cancel loopTask cũ rồi spawn loopTask
        // mới ngay, nếu không check thì vòng lặp CŨ (Task.sleep bị cancel chỉ throw, `try?` nuốt lỗi,
        // shouldRun vẫn true) tiếp tục chạy song song với vòng MỚI → 2 kết nối cùng lúc.
        while shouldRun, !Task.isCancelled {
            do {
                try await connectOnce()
                retryDelay = 3
            } catch {
                if !shouldRun { return }
            }
            guard shouldRun, !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: retryDelay * 1_000_000_000)
            retryDelay = min(retryDelay * 2, 30)
        }
    }

    private func connectOnce() async throws {
        guard let token = Prefs.token, !token.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        // 1. Negotiate — lấy connectionId để mở WebSocket.
        var negotiateReq = URLRequest(url: URL(string: Prefs.apiBase + "/hub/entity/negotiate?negotiateVersion=1")!)
        negotiateReq.httpMethod = "POST"
        negotiateReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (negData, negResp) = try await URLSession.shared.data(for: negotiateReq)
        guard (negResp as? HTTPURLResponse)?.statusCode == 200,
              let negObj = try? JSONSerialization.jsonObject(with: negData) as? [String: Any],
              let connectionId = (negObj["connectionToken"] as? String) ?? (negObj["connectionId"] as? String) else {
            throw URLError(.badServerResponse)
        }

        // 2. Mở WebSocket kèm access_token + id trên query string.
        var comps = URLComponents(string: Prefs.apiBase + "/hub/entity")!
        comps.scheme = comps.scheme == "https" ? "wss" : "ws"
        comps.queryItems = [
            URLQueryItem(name: "id", value: connectionId),
            URLQueryItem(name: "access_token", value: token),
        ]
        let ws = URLSession.shared.webSocketTask(with: comps.url!)
        self.task = ws
        ws.resume()

        // 3. Handshake JSON Hub Protocol — bản tin kết thúc bằng 0x1E.
        let handshake = "{\"protocol\":\"json\",\"version\":1}\u{1e}"
        try await ws.send(.string(handshake))

        try await receiveLoop(ws)
    }

    private func receiveLoop(_ ws: URLSessionWebSocketTask) async throws {
        while shouldRun {
            let message = try await ws.receive()
            let text: String
            switch message {
            case .string(let s): text = s
            case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
            @unknown default: continue
            }
            for record in text.split(separator: "\u{1e}", omittingEmptySubsequences: true) {
                handleRecord(String(record))
            }
        }
    }

    /// type 1 = invocation ("EntityChanged" arguments = [entityName, action, id, senderConnectionId,
    /// voice]). type 6 = ping từ server, không cần phản hồi ở phía client cho hub này.
    private func handleRecord(_ record: String) {
        guard let data = record.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? Int, type == 1,
              let target = obj["target"] as? String, target == "EntityChanged",
              let args = obj["arguments"] as? [Any] else { return }

        if args.count >= 3,
           let entityName = args[0] as? String, let action = args[1] as? String, let id = args[2] as? String {
            let voice = (args.count >= 5 ? args[4] as? String : nil) ?? ""
            let callback = onEntityChanged
            Task { @MainActor in callback?(entityName, action, id, voice) }
        }
    }
}
