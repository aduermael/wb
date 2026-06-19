import Foundation
import Darwin

enum WPError: LocalizedError {
    case message(String)

    static func posix(_ operation: String) -> WPError {
        .message("\(operation): \(String(cString: strerror(errno)))")
    }

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else {
            throw WPError.message(message)
        }
        return value
    }
}

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        switch self {
        case .some(let value):
            return value.nilIfEmpty
        case .none:
            return nil
        }
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

func printable(_ value: Any?) -> String {
    guard let value else {
        return "nil"
    }

    if value is NSNull {
        return "null"
    }

    if let string = value as? String {
        return string
    }

    if let number = value as? NSNumber {
        return number.stringValue
    }

    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
       let string = String(data: data, encoding: .utf8) {
        return string
    }

    return String(describing: value)
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8) ?? "{}")
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}
