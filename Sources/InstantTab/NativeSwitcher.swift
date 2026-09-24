import Dispatch
import Darwin
import SkyLightShim

/// Turns native Cmd+Tab off while InstantTab handles it, and back on for every way the process can end.
/// The setting outlives the process, so a missed restore would leave the Mac without Cmd+Tab.
enum NativeSwitcher {
    static func disable() {
        for hotKey in SymbolicHotKey.allCases { SkyLight.setEnabled(false, hotKey) }
    }

    static func restore() {
        for hotKey in SymbolicHotKey.allCases { SkyLight.setEnabled(true, hotKey) }
    }

    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []
    /// Runs on the main thread when a termination signal (such as a replacing copy's SIGTERM) arrives.
    nonisolated(unsafe) static var beforeSignalExit: (@MainActor () -> Void)?

    /// Normal exits restore through `atexit`. Termination signals exit normally, and crash signals
    /// restore on a best-effort basis and then re-raise so the crash is still reported. Crash handlers
    /// run on their own stack so a main-thread stack overflow can still restore.
    static func installExitHandlers() {
        atexit { NativeSwitcher.restore() }
        // Stopped with the hotkeys registered, Cmd+Tab would do nothing until resumed.
        signal(SIGTSTP, SIG_IGN)

        let stackSize = 64 * 1024
        var stack = stack_t(ss_sp: malloc(stackSize), ss_size: stackSize, ss_flags: 0)
        sigaltstack(&stack, nil)

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
