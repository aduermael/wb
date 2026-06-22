/// Encodes exported PNG screenshot data into the requested destination image
/// format.
import AppKit
import Foundation

enum ScreenshotFormat {
	case png
	case jpeg

	init(path: String) throws {
		switch URL(fileURLWithPath: path).pathExtension.lowercased() {
		case "png":
			self = .png
		case "jpg", "jpeg":
			self = .jpeg
		default:
			throw WBError.message("screenshot destination must end in .png, .jpg, or .jpeg")
		}
	}

	var name: String {
		switch self {
		case .png: return "png"
		case .jpeg: return "jpeg"
		}
	}

	func encodedData(fromPNG pngData: Data) throws -> Data {
		switch self {
		case .png:
			return pngData
		case .jpeg:
			guard let image = NSImage(data: pngData),
				let tiffData = image.tiffRepresentation,
				let bitmap = NSBitmapImageRep(data: tiffData),
				let jpegData = bitmap.representation(
					using: .jpeg,
					properties: [.compressionFactor: 0.9]
				)
			else {
				throw WBError.message("failed to encode JPEG screenshot")
			}
			return jpegData
		}
	}
}
