import Foundation
import os

public enum Diagnostics {
    /// One subsystem for the host and every tool, with each process as its own category.
    public static let log = Logger(subsystem: "com.infeace.Instantools", category: ProcessInfo.processInfo.processName)
}
