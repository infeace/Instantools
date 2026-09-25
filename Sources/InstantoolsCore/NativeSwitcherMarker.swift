/// Whether InstantTab may have left native Cmd+Tab off, kept by the host in its defaults so it outlives a
/// host that crashed or was killed. The host restores native Cmd+Tab only while this says so: another
/// switcher can turn the same hotkeys off for itself, and restoring them while InstantTab is off would undo it.
public struct NativeSwitcherMarker: Equatable, Sendable {
    public private(set) var mayBeOff: Bool

    public init(mayBeOff: Bool) {
        self.mayBeOff = mayBeOff
    }

    /// Before the tool starts, so a host that crashes right after still restores at its next launch.
    public mutating func startingSwitcher() {
        mayBeOff = true
    }

    /// True when the host has to restore. `normally` is an exit through `exit()`, whose atexit handler
    /// restored. A signal may have skipped the crash handler, and after an exit it did not ask for the host
    /// restores anyway. Either way native Cmd+Tab is back, until the next start.
    public mutating func switcherExited(asked: Bool, normally: Bool) -> Bool {
        mayBeOff = false
        return !asked || !normally
    }

    /// At quit and on termination signals, after the tools were stopped or killed. `switcherWasRunning` covers
    /// a tool still running or stopping, whether or not it is enabled, since the host exits before it could
    /// report how the tool ended.
    public mutating func quitting(switcherWasRunning: Bool) -> Bool {
        defer { mayBeOff = false }
        return mayBeOff || switcherWasRunning
    }

    /// At launch, once leftover processes are stopped and before any tool starts. A marker still set was left
    /// by a host that crashed or was killed, and a leftover InstantTab may have been killed just now.
    public mutating func launched(stoppedLeftoverSwitcher: Bool) -> Bool {
        defer { mayBeOff = false }
        return mayBeOff || stoppedLeftoverSwitcher
    }
}
