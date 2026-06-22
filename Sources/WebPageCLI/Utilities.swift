/// Provides shared error handling, compact JSON rendering, logging, and small
/// value helpers used across the command-line process and daemon.
import Darwin
import Foundation

enum WBError: LocalizedError {
	case message(String)

	static func posix(_ operation: String) -> WBError {
		.message("\(operation): \(String(cString: strerror(errno)))")
	}

	var errorDescription: String? {
		switch self {
		case .message(let message):
			return message
		}
	}
}

struct WBExit: Error {
	let code: Int32
}

extension Optional {
	func unwrap(_ message: String) throws -> Wrapped {
		guard let value = self else {
			throw WBError.message(message)
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
		let string = String(data: data, encoding: .utf8)
	{
		return string
	}

	return String(describing: value)
}

func printJSON<T: Encodable>(_ value: T) throws {
	print(try compactJSONString(value))
}

func compactJSONString<T: Encodable>(_ value: T) throws -> String {
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.sortedKeys]
	let encoded = try encoder.encode(value)
	let object = try JSONSerialization.jsonObject(with: encoded)
	let pruned = pruneJSONObject(object)
	return try renderJSONObject(pruned)
}

func printError(_ message: String) {
	FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

func daemonLog(_ message: String) {
	let path = WBConfig.current().logPath
	let sanitizedMessage =
		message
		.replacingOccurrences(of: "\r", with: " ")
		.replacingOccurrences(of: "\n", with: " ")
	let line = "[\(Date().iso8601String)] pid=\(Darwin.getpid()) \(sanitizedMessage)\n"
	let flags = O_WRONLY | O_CREAT | O_APPEND
	let mode = mode_t(S_IRUSR | S_IWUSR)
	let fd = Darwin.open(path, flags, mode)
	guard fd >= 0 else {
		printError("daemon log open failed: \(String(cString: strerror(errno)))")
		return
	}
	defer { Darwin.close(fd) }

	let data = Data(line.utf8)
	data.withUnsafeBytes { buffer in
		guard let baseAddress = buffer.baseAddress else {
			return
		}

		var written = 0
		while written < buffer.count {
			let count = Darwin.write(
				fd,
				baseAddress.advanced(by: written),
				buffer.count - written
			)
			if count < 0 {
				if errno == EINTR {
					continue
				}
				return
			}
			if count == 0 {
				return
			}
			written += count
		}
	}
}

private func pruneJSONObject(_ value: Any, key: String? = nil) -> Any {
	if let dictionary = value as? [String: Any] {
		var result: [String: Any] = [:]
		for (key, rawValue) in dictionary {
			let prunedValue = pruneJSONObject(rawValue, key: key)
			if !shouldOmitJSONValue(prunedValue, key: key) {
				result[key] = prunedValue
			}
		}
		return result
	}

	if let array = value as? [Any] {
		return array.map { pruneJSONObject($0, key: key) }
	}

	return value
}

private func shouldOmitJSONValue(_ value: Any, key: String? = nil) -> Bool {
	if value is NSNull {
		return true
	}

	if isJSONFalse(value) {
		return key != "ok"
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
		throw WBError.message("failed to render JSON string")
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
