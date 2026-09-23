import os

enum Diagnostics {
    static let subsystem = "com.infeace.InstantTab"
    static let log = Logger(subsystem: subsystem, category: "app")
    /// Points of interest show up in Instruments and `log stream` without extra setup.
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
