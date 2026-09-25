import Dispatch
import Darwin

@MainActor
public enum TerminationSignals {
    private static var sources: [DispatchSourceSignal] = []

    public static func handle(_ handler: @escaping @MainActor () -> Void) {
        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            // Ignored first, so the default action does not kill the process before the source runs.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { MainActor.assumeIsolated { handler() } }
            source.resume()
            sources.append(source)
        }
    }
}
