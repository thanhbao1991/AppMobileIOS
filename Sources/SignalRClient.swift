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

    /// entityName, action, id — nhận trên MainActor để các View cập nhật @State an toàn.
    private var onEntityChanged: (@MainActor (String, String, String) -> Void)?

    func start(onEntityChanged: @escaping @MainActor (String, String, String) -> Void) {
        self.onEntityChanged = onEntityChanged
        guard !shouldRun else { return }
        shouldRun = true
        retryDelay = 3
        Task { await connectLoop() }
    }

    func stop() {
        shouldRun = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connectLoop() async {
        while shouldRun {
            do {
                try await connectOnce()
                retryDelay = 3
            } catch {
                if !shouldRun { return }
            }
            guard shouldRun else { return }
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

    /// type 1 = invocation. "EntityChanged" arguments = [entityName, action, id, senderConnectionId, voice].
    /// type 6 = ping từ server, không cần phản hồi ở phía client cho hub này.
    private func handleRecord(_ record: String) {
        guard let data = record.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard (obj["type"] as? Int) == 1,
              (obj["target"] as? String) == "EntityChanged",
              let args = obj["arguments"] as? [Any], args.count >= 3,
              let entityName = args[0] as? String,
              let action = args[1] as? String,
              let id = args[2] as? String else { return }
        let callback = onEntityChanged
        Task { @MainActor in callback?(entityName, action, id) }
    }
}
