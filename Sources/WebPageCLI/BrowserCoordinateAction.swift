/// Models pointer, drag, and wheel actions requested by coordinate-based
/// daemon commands.
import Foundation

enum BrowserCoordinateAction {
	case click(CGPoint)
	case press(CGPoint)
	case drag(CGPoint)
	case release(CGPoint)
	case scroll(point: CGPoint, deltaX: Double, deltaY: Double)

	init(request: WireRequest) throws {
		let action = try request.requiredCoordinateAction()
		let point = CGPoint(
			x: CGFloat(try request.requiredX()),
			y: CGFloat(try request.requiredY())
		)

		switch action {
		case "click":
			self = .click(point)
		case "press":
			self = .press(point)
		case "drag":
			self = .drag(point)
		case "release":
			self = .release(point)
		case "scroll":
			self = .scroll(
				point: point,
				deltaX: try request.requiredDeltaX(),
				deltaY: try request.requiredDeltaY()
			)
		default:
			throw WBError.message("unknown coordinate action \(action)")
		}
	}

	var name: String {
		switch self {
		case .click: return "click"
		case .press: return "press"
		case .drag: return "drag"
		case .release: return "release"
		case .scroll: return "scroll"
		}
	}

	var point: CGPoint {
		switch self {
		case .click(let point),
			.press(let point),
			.drag(let point),
			.release(let point):
			return point
		case .scroll(let point, _, _):
			return point
		}
	}

	var javascriptArguments: [String: Any] {
		var arguments: [String: Any] = [
			"action": name,
			"x": Double(point.x),
			"y": Double(point.y),
		]

		if case .scroll(_, let deltaX, let deltaY) = self {
			arguments["deltaX"] = deltaX
			arguments["deltaY"] = deltaY
		}

		return arguments
	}
}
