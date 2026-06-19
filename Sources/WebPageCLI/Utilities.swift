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

extension String {
    var iso8601Date: Date? {
        ISO8601DateFormatter().date(from: self)
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
    encoder.outputFormatting = [.sortedKeys]
    let encoded = try encoder.encode(value)
    let object = try JSONSerialization.jsonObject(with: encoded)
    let pruned = pruneJSONObject(object)
    print(try renderJSONObject(pruned))
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

private func pruneJSONObject(_ value: Any) -> Any {
    if let dictionary = value as? [String: Any] {
        var result: [String: Any] = [:]
        for (key, rawValue) in dictionary {
            let prunedValue = pruneJSONObject(rawValue)
            if !shouldOmitJSONValue(prunedValue) {
                result[key] = prunedValue
            }
        }
        return result
    }

    if let array = value as? [Any] {
        return array.map(pruneJSONObject)
    }

    return value
}

private func shouldOmitJSONValue(_ value: Any) -> Bool {
    if value is NSNull {
        return true
    }

    if isJSONFalse(value) {
        return true
    }

    if let string = value as? String {
        return string.isEmpty
    }

    if let array = value as? [Any] {
        return array.isEmpty
    }

    if let dictionary = value as? [String: Any] {
        return dictionary.isEmpty
    }

    return false
}

private func isJSONFalse(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else {
        return false
    }

    return CFGetTypeID(number) == CFBooleanGetTypeID() && !number.boolValue
}

private func renderJSONObject(_ value: Any, key: String? = nil) throws -> String {
    if let dictionary = value as? [String: Any] {
        let fields = try dictionary.keys.sorted().map { fieldKey in
            let renderedKey = try renderJSONString(fieldKey)
            let renderedValue = try renderJSONObject(dictionary[fieldKey]!, key: fieldKey)
            return "\(renderedKey):\(renderedValue)"
        }
        return "{\(fields.joined(separator: ","))}"
    }

    if let array = value as? [Any] {
        let items = try array.map { try renderJSONObject($0, key: key) }
        return "[\(items.joined(separator: ","))]"
    }

    if let string = value as? String {
        return try renderJSONString(string)
    }

    if value is NSNull {
        return "null"
    }

    if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }

        if key == "progress" {
            return renderJSONFloat(number.doubleValue)
        }

        return number.stringValue
    }

    return try renderJSONString(String(describing: value))
}

private func renderJSONString(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: [value])
    guard let rendered = String(data: data, encoding: .utf8) else {
        throw WPError.message("failed to render JSON string")
    }
    return String(rendered.dropFirst().dropLast())
}

private func renderJSONFloat(_ value: Double) -> String {
    var rendered = String(value)
    if !rendered.contains(".") && !rendered.lowercased().contains("e") {
        rendered += ".0"
    }
    return rendered
}
