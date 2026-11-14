import Foundation
import Network
import PerryCore

/// Loopback-only HTTP listener. One request per connection, then close.
final class ControlServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "perry.server")
    private let handler: (HTTPRequest) -> (Int, String)

    init(port: UInt16, handler: @escaping (HTTPRequest) -> (Int, String)) throws {
        self.handler = handler
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
    }

    func start(onFailure: @escaping (Error) -> Void) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: dlog("listening on 127.0.0.1:\(Config.port)")
            case .failed(let e): onFailure(e)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] c in self?.handle(c) }
        listener.start(queue: queue)
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        var buf = Data()
        func read() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, done, err in
                if let d = data { buf.append(d) }
                if let req = HTTPRequest.parse(buf) {
                    let (code, body) = self.handler(req)
                    let resp = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Not Found")\r\n"
                        + "Content-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
                        + "Connection: close\r\n\r\n\(body)"
                    c.send(content: Data(resp.utf8), completion: .contentProcessed { _ in c.cancel() })
                } else if done || err != nil {
                    c.cancel()
                } else {
                    read()
                }
            }
        }
        read()
    }
}
