import Foundation
import InstantoolsCore

/// The tool's end of the pipes to the host: requests on stdin, replies and events on stdout, one JSON object
/// per line. Encoding and writes have their own queue, so neither a status full of latency samples nor a host
/// that stops reading holds up the tool's main thread.
@MainActor
public final class ToolChannel {
    private let status: () -> ToolMessage
    private let output = DispatchQueue(label: "com.infeace.Instantools.channel", qos: .utility)
    private var isStarted = false

    public init(status: @escaping () -> ToolMessage) {
        self.status = status
    }

    /// Call at the end of launch. The host shows the tool as running from the ready event; whether its tap or
    /// hotkeys work is in its status.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let thread = Thread { [weak self] in
            Self.readRequests(
                deliver: { requests in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(requests) } }
                },
                hostGone: {
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.hostGone() } }
                }
            )
        }
        thread.name = "com.infeace.Instantools.channel"
        thread.qualityOfService = .utility
        thread.start()
        send(ToolMessage(event: .ready))
    }

    private func send(_ message: ToolMessage) {
        output.async {
            guard let line = MessageCoding.line(message) else { return }
            PipeIO.write(line, to: STDOUT_FILENO)
        }
    }

    private func handle(_ requests: [HostRequest]) {
        for request in requests {
            switch request.request {
            case .status: send(status())
            case .ping: send(ToolMessage(event: .pong))
            }
        }
    }

    /// Stdin ends only when the host is gone. The tool keeps working for a while, so a host that crashed and
    /// is relaunched by launchd finds it still running and replaces it, then exits normally so its exit
    /// handlers run.
    private func hostGone() {
        Diagnostics.log.notice("host is gone, exiting in \(ToolLaunch.hostGoneGrace, privacy: .public)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + ToolLaunch.hostGoneGrace) { exit(0) }
    }

    nonisolated private static func readRequests(deliver: @escaping @Sendable ([HostRequest]) -> Void, hostGone: @Sendable () -> Void) {
        var lines = LineBuffer()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if count > 0 {
                let requests = lines.append(chunk[..<count]).compactMap { MessageCoding.decode(HostRequest.self, from: $0) }
                if !requests.isEmpty { deliver(requests) }
            } else if count < 0, errno == EINTR {
                continue
            } else {
                return hostGone()
            }
        }
    }
}
