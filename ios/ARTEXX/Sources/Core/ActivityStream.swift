import Foundation

/// SSE 客户端：订阅 /api/exploration/activity/stream，用于仪表盘活动流。
final class ActivityStream: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published private(set) var events: [ActivityEvent] = []
    @Published private(set) var connected = false
    @Published var lastError: String?

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = ""
    private var taskID: Int64?

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 3600
        cfg.timeoutIntervalForResource = .infinity
        cfg.waitsForConnectivity = true
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start(taskID: Int64? = nil) {
        stop()
        self.taskID = taskID
        let base = APIClient.shared.config.effectiveBase
        var urlStr = base + "/api/exploration/activity/stream"
        if let taskID { urlStr += "?task=\(taskID)" }
        guard let url = URL(string: urlStr) else { lastError = "SSE URL 无效"; return }
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !APIClient.shared.config.token.isEmpty {
            req.setValue("Bearer \(APIClient.shared.config.token)", forHTTPHeaderField: "Authorization")
        }
        task = session.dataTask(with: req)
        task?.resume()
        connected = true
    }

    func stop() {
        task?.cancel()
        task = nil
        connected = false
        buffer = ""
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk
        while let range = buffer.range(of: "\n\n") {
            let raw = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            handle(raw)
        }
    }

    private func handle(_ raw: String) {
        var payload = ""
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("data:") {
                payload += String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !payload.isEmpty else { return }
        let event: ActivityEvent
        if let d = payload.data(using: .utf8), let e = try? JSONDecoder().decode(ActivityEvent.self, from: d) {
            event = e
        } else {
            event = ActivityEvent(text: payload)
        }
        DispatchQueue.main.async {
            self.events.append(event)
            if self.events.count > 500 { self.events.removeFirst(self.events.count - 500) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.connected = false
            if let error { self.lastError = error.localizedDescription }
        }
    }
}
