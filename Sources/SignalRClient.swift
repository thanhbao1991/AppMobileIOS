import Foundation

/// Client SignalR tối giản (JSON Hub Protocol qua WebSocket thuần, không phụ thuộc SPM ngoài —
/// tránh rủi ro CI unsigned build phải resolve package lạ). Port hành vi cốt lõi từ
/// TraSuaApp.Desktop/Helpers/SignalRClient.cs: negotiate → connect → nghe "EntityChanged" →
/// tự retry khi rớt kết nối. Access token đọc qua query "access_token" — khớp
/// ApiConfigurationExtensions.OnMessageReceived (Backend) chỉ chấp nhận token qua query cho hub.
actor SignalRClient {
    static let shared = SignalRClient()

    private var task: URLSessionWebSocketTask?
    private var shouldRun = false
    private var retryDelay: UInt64 = 3
    private var invocationCounter = 0
    private var pendingInvocations: [String: CheckedContinuation<Any?, Error>] = [:]
    private var loopTask: Task<Void, Never>?

    /// entityName, action, id — nhận trên MainActor để các View cập nhật @State an toàn.
    private var onEntityChanged: (@MainActor (String, String, String) -> Void)?
    /// Tab "Xem màn hình Desktop" gán khi đang mở, gỡ khi rời view — ảnh JPEG (dirty-rect, không
    /// phải lúc nào cũng full-frame) + toạ độ x/y/w/h cần vẽ đè lên canvas hiện có, trả về từ
    /// Desktop client qua "ScreenshotReceived".
    private var onScreenshotReceived: (@MainActor (Data, Int, Int, Int, Int) -> Void)?
    /// Đường VP9 mới (ScreenAgent sidecar) — song song onScreenshotReceived (JPEG cũ) trong lúc
    /// verify. data = 1 khung VP9 đã encode (không phải NAL Annex-B).
    private var onVideoFrameReceived: (@MainActor (Data, Bool) -> Void)?

    func start(onEntityChanged: @escaping @MainActor (String, String, String) -> Void) {
        self.onEntityChanged = onEntityChanged
        guard !shouldRun else { return }
        shouldRun = true
        retryDelay = 3
        loopTask = Task { await connectLoop() }
    }

    func stop() {
        shouldRun = false
        loopTask?.cancel()
        loopTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Buộc reconnect NGAY, bỏ qua backoff đang chờ (3-30s) — gọi khi app quay lại foreground
    /// (`scenePhase == .active`). Không có bước này, sau khi đổi app qua lại, kết nối chết âm thầm
    /// (`receiveLoop()` có thể không tự throw — xem fix trong `invoke()`) và mọi thao tác (kể cả tap
    /// click, dùng `try?` nuốt lỗi) sẽ không làm gì cho tới khi backoff tự chạy tới lượt — cảm giác
    /// như tính năng "không hoạt động" dù thực ra chỉ đang chờ reconnect.
    func kickReconnect() {
        guard shouldRun else { return }
        loopTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        failAllPendingInvocations(URLError(.networkConnectionLost))
        retryDelay = 3
        loopTask = Task { await connectLoop() }
    }

    func setScreenshotHandler(_ handler: (@MainActor (Data, Int, Int, Int, Int) -> Void)?) {
        onScreenshotReceived = handler
    }

    func setVideoFrameHandler(_ handler: (@MainActor (Data, Bool) -> Void)?) {
        onVideoFrameReceived = handler
    }

    /// Gửi invocation và đợi completion (type 3) khớp invocationId — dùng cho lời gọi cần kết quả
    /// như GetConnectedDesktops, hoặc để biết ngay khi hub báo lỗi (vd. RequestDesktopScreenshot
    /// nhắm vào 1 máy đã ngắt kết nối).
    func invoke(_ method: String, args: [Any] = []) async throws -> Any? {
        guard let ws = task else { throw URLError(.networkConnectionLost) }
        invocationCounter += 1
        let invocationId = String(invocationCounter)
        let payload: [String: Any] = ["type": 1, "target": method, "arguments": args, "invocationId": invocationId]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8)! + "\u{1e}"
        do {
            try await ws.send(.string(text))
        } catch {
            // send() phát hiện socket chết ngay, nhưng receiveLoop() đang `await ws.receive()` có thể
            // không tự throw trong trường hợp này (quirk iOS sau khi app bị đưa xuống nền rồi mở lại)
            // — connectLoop() sẽ treo mãi không reconnect nếu không có ai chủ động cancel task chết
            // này. Cancel ở đây để receive() đang treo bung lỗi ngay, kích connectLoop() retry thật.
            if ws === task { task = nil }
            ws.cancel(with: .abnormalClosure, reason: nil)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingInvocations[invocationId] = continuation
        }
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
                failAllPendingInvocations(error)
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
    /// voice]; "ScreenshotReceived" arguments = [base64Bytes, x, y, width, height] — ảnh có thể chỉ
    /// là 1 dải ngang cần vẽ đè lên canvas hiện có, không phải lúc nào cũng full-frame). type 3 =
    /// completion (kết quả của invoke() có invocationId, vd. GetConnectedDesktops). type 6 = ping từ
    /// server, không cần phản hồi ở phía client cho hub này.
    private func handleRecord(_ record: String) {
        guard let data = record.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? Int else { return }

        if type == 3 {
            guard let invocationId = obj["invocationId"] as? String,
                  let continuation = pendingInvocations.removeValue(forKey: invocationId) else { return }
            if let errorMessage = obj["error"] as? String {
                continuation.resume(throwing: NSError(domain: "SignalRHub", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]))
            } else {
                continuation.resume(returning: obj["result"])
            }
            return
        }

        guard type == 1, let target = obj["target"] as? String,
              let args = obj["arguments"] as? [Any] else { return }

        if target == "EntityChanged", args.count >= 3,
           let entityName = args[0] as? String, let action = args[1] as? String, let id = args[2] as? String {
            let callback = onEntityChanged
            Task { @MainActor in callback?(entityName, action, id) }
        } else if target == "ScreenshotReceived", args.count >= 5,
                  let base64 = args[0] as? String, let imageData = Data(base64Encoded: base64),
                  let x = (args[1] as? NSNumber)?.intValue, let y = (args[2] as? NSNumber)?.intValue,
                  let w = (args[3] as? NSNumber)?.intValue, let h = (args[4] as? NSNumber)?.intValue {
            let callback = onScreenshotReceived
            Task { @MainActor in callback?(imageData, x, y, w, h) }
        } else if target == "VideoFrameReceived", args.count >= 2,
                  let base64 = args[0] as? String, let nalData = Data(base64Encoded: base64),
                  let isKeyframe = args[1] as? Bool {
            let callback = onVideoFrameReceived
            Task { @MainActor in callback?(nalData, isKeyframe) }
        }
    }

    /// [connectionId: nhãn tên máy] — danh sách Desktop client đang mở app, cho màn hình chọn máy.
    func fetchConnectedDesktops() async throws -> [String: String] {
        let result = try await invoke("GetConnectedDesktops")
        return (result as? [String: String]) ?? [:]
    }

    private func failAllPendingInvocations(_ error: Error) {
        for (_, continuation) in pendingInvocations { continuation.resume(throwing: error) }
        pendingInvocations.removeAll()
    }
}
