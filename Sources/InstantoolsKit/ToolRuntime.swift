import AppKit
import InstantoolsCore

public enum ToolRuntime {
    /// Runs a tool as a windowless accessory app. Started by anything but the host, it exits: macOS would treat
    /// it as its own app, without the host's permissions, and it could run beside the host's copy.
    @MainActor public static func run(_ tool: ToolId, delegate makeDelegate: () -> NSApplicationDelegate) {
        guard ProcessInfo.processInfo.environment[ToolLaunch.environmentKey] == "1" else {
            let message = "\(tool.executableName) is part of Instantools and runs only when Instantools starts it. Open Instantools instead.\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
        // A reply written after the host is gone must fail the write, not end the tool.
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        let delegate = makeDelegate()
        app.delegate = delegate
        // Tools have no Info.plist to set LSUIElement.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

public enum PipeIO {
    /// Blocking and unbuffered. With SIGPIPE ignored, a pipe whose reader is gone only fails the write.
    public static func write(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}
