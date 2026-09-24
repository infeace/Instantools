import Dispatch
import Darwin
import SkyLightShim

/// Native Cmd+Tab stays off only while InstantTab handles it. The setting outlives the process, so it is
/// restored on every way out: normal exit, termination signals, and crashes.
enum NativeSwitcher {
    static func disable() {
        for hotKey in SymbolicHotKey.allCases { SkyLight.setEnabled(false, hotKey) }
    }

    static func restore() {
        for hotKey in SymbolicHotKey.allCases { SkyLight.setEnabled(true, hotKey) }
    }

    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []
    nonisolated(unsafe) static var beforeSignalExit: (@MainActor () -> Void)?

    static func installExitHandlers() {
        atexit { NativeSwitcher.restore() }
        // A stopped process would keep the hotkeys registered and Cmd+Tab would do nothing.
        signal(SIGTSTP, SIG_IGN)

        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { beforeSignalExit?() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }

        // Crash handlers run on their own stack so a stack overflow can still restore, then re-raise so
        // the crash is reported.
        let stackSize = 64 * 1024
        var stack = stack_t(ss_sp: malloc(stackSize), ss_size: stackSize, ss_flags: 0)
        sigaltstack(&stack, nil)
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { sig in
                NativeSwitcher.restore()
                signal(sig, SIG_DFL)
                raise(sig)
            }
            action.sa_flags = SA_ONSTACK
            sigaction(sig, &action, nil)
        }
    }
}
