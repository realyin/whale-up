import Foundation
import Network
import FocusGuardCore

/// 只监听 127.0.0.1 的小服务，接收浏览器扩展上报的观看记录。
@MainActor
final class LocalServer {
    static let port: UInt16 = 47621

    private var listener: NWListener?
    private let onViews: ([ContentView]) -> Void
    private let status: () -> [String: Any]
    private(set) var lastReportAt: Date?
    private(set) var error: String?

    init(onViews: @escaping ([ContentView]) -> Void, status: @escaping () -> [String: Any]) {
        self.onViews = onViews
        self.status = status
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let e) = state {
                    Task { @MainActor in self?.error = "本机接收服务启动失败：\(e.localizedDescription)" }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            self.error = "本机接收服务启动失败：\(error.localizedDescription)"
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, err in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                switch HTTPRequest.parse(buffer) {
                case .complete(let req): self.respond(conn, to: req)
                case .incomplete where !done && err == nil: self.receive(conn, buffer: buffer)
                default: self.send(conn, status: 400, json: ["error": "bad request"])
                }
            }
        }
    }

    private func respond(_ conn: NWConnection, to req: HTTPRequest) {
        guard req.isFromExtension else { return send(conn, status: 403, json: ["error": "forbidden"]) }
        switch (req.method, req.path) {
        case ("GET", "/status"):
            send(conn, status: 200, json: status())
        case ("POST", "/views"):
            guard let views = try? JSONDecoder().decode([ContentView].self, from: req.body) else {
                return send(conn, status: 400, json: ["error": "invalid json"])
            }
            lastReportAt = Date()
            onViews(views)
            send(conn, status: 200, json: ["ok": true])
        default:
            send(conn, status: 404, json: ["error": "not found"])
        }
    }

    private func send(_ conn: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }
}
