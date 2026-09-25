import Dispatch
import Darwin
import SkyLightShim

/// Native Cmd+Tab stays off only while the Cmd+Tab tool handles it. The setting outlives the process, so the
/// tool restores it on every way out: normal exit, termination signals, and crashes. The host restores it
/// too whenever the tool exits any other way than a clean stop.
public enum NativeSwitcher {
    /// False when macOS refused, for example because the private call no longer exists.
    public static func disable() -> Bool {
        set(enabled: false)
    }

    public static func restore() {
        _ = set(enabled: true)
    }

    /// No array or loop over the cases: this also runs in the crash handler, where allocating can deadlock.
    private static func set(enabled: Bool) -> Bool {
        let tab = SkyLight.setEnabled(enabled, .commandTab)
        let shiftTab = SkyLight.setEnabled(enabled, .commandShiftTab)
        return tab && shiftTab
    }

    nonisolated(unsafe) private static var signalSources: [DispatchSourceSignal] = []

    public static func installExitHandlers() {
        atexit { NativeSwitcher.restore() }
        // A stopped process would keep the hotkeys registered and Cmd+Tab would do nothing.
        signal(SIGTSTP, SIG_IGN)

        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            // Ignored first, so the default action does not kill the process before the source runs.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { exit(0) }
            source.resume()
            signalSources.append(source)
        }

        // Crash handlers restore, then re-raise so the crash is reported. The alternate stack lets them run
        // after a stack overflow on the main thread; sigaltstack is per thread.
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
