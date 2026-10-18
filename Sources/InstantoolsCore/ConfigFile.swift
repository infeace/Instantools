import Foundation

/// A tool's JSON5 settings file in ~/.config/instantools. Settings in the host writes it, and the tool reads it
/// and follows every change.
public protocol ConfigFile: Sendable, Equatable {
    static var fileName: String { get }

    /// The defaults.
    init()

    static func parse(_ data: Data) throws(ConfigError) -> ParsedConfig<Self>

    /// The whole file, comments included, as Settings writes it.
    var fileContents: String { get }
}

extension ConfigFile {
    public static var defaultFileContents: String { Self().fileContents }

    /// `fileContents`, once they parse back to this config, so Settings never writes a file that does not
    /// parse or reads back as other settings.
    public func checkedFileContents() throws(ConfigError) -> String {
        let contents = fileContents
        guard try Self.parse(Data(contents.utf8)).config == self else {
            throw .invalid("the file would read back as different settings")
        }
        return contents
    }
}

public struct ParsedConfig<Value: Sendable & Equatable>: Sendable, Equatable {
    public var config: Value
    public var warnings: [String]

    public init(config: Value, warnings: [String]) {
        self.config = config
        self.warnings = warnings
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case syntax(String)
    case invalid(String)

    public var description: String {
        switch self {
        case .syntax(let message): "syntax error: \(message)"
        case .invalid(let message): message
        }
    }
}

public enum ConfigValues {
    /// JSON5 with a readable message for a syntax error.
    public static func object(from data: Data) throws(ConfigError) -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
        } catch {
            let nsError = error as NSError
            throw .syntax(nsError.userInfo[NSDebugDescriptionErrorKey] as? String ?? nsError.localizedDescription)
        }
        guard let root = object as? [String: Any] else { throw .invalid("the config must be an object") }
        return root
    }

    /// JSON booleans bridge to NSNumber and would otherwise pass as 0 or 1.
    public static func isBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }

    public static func enumValue<Value: RawRepresentable & CaseIterable>(
        _ key: String, _ value: Any
    ) throws(ConfigError) -> Value where Value.RawValue == String {
        guard let raw = value as? String, let parsed = Value(rawValue: raw) else {
            let allowed = Value.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
            throw .invalid("\(key) must be one of \(allowed)")
        }
        return parsed
    }

    public static func quoted(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }
}
