/// Defines bounded timing values and decoded payloads for screenshot render
/// settling before viewport image export.
import Foundation

struct ScreenshotRenderSettling {
	static let fontTimeout: TimeInterval = 1.0
	static let frameTimeout: TimeInterval = 1.5
	static let frameCount = 3
	static let responseTimeoutHeadroom: TimeInterval = 20

	static var fontTimeoutMilliseconds: Int {
		milliseconds(fontTimeout)
	}

	static var maxTotalWaitTimeout: TimeInterval {
		max(0, DaemonTiming.commandResponseTimeout - responseTimeoutHeadroom)
	}

	static func nonResourceSettlingTimeout(captureDelay: TimeInterval) -> TimeInterval {
		fontTimeout
			+ frameTimeout
			+ fontTimeout
			+ max(0, captureDelay)
	}

	static func totalWaitTimeout(
		resourceTimeout: TimeInterval,
		captureDelay: TimeInterval
	) -> TimeInterval {
		let requestedWait =
			max(0, resourceTimeout)
			+ nonResourceSettlingTimeout(captureDelay: captureDelay)
		return min(maxTotalWaitTimeout, requestedWait)
	}

	static func resourceWaitTimeout(
		resourceTimeout: TimeInterval,
		captureDelay: TimeInterval
	) -> TimeInterval {
		guard resourceTimeout > 0 else {
			return 0
		}
		let totalTimeout = totalWaitTimeout(
			resourceTimeout: resourceTimeout,
			captureDelay: captureDelay
		)
		let reservedTimeout = nonResourceSettlingTimeout(captureDelay: captureDelay)
		return min(resourceTimeout, max(0, totalTimeout - reservedTimeout))
	}

	static func milliseconds(_ timeout: TimeInterval) -> Int {
		max(0, Int((timeout * 1000).rounded(.up)))
	}
}

struct ScreenshotCaptureWaitBudget {
	private let screenshotDeadline: Date
	private let resourceDeadline: Date?

	init(resourceTimeout: TimeInterval, captureDelay: TimeInterval, now: Date = Date()) {
		let totalTimeout = ScreenshotRenderSettling.totalWaitTimeout(
			resourceTimeout: resourceTimeout,
			captureDelay: captureDelay
		)
		screenshotDeadline = now.addingTimeInterval(totalTimeout)
		let resourceWaitTimeout = ScreenshotRenderSettling.resourceWaitTimeout(
			resourceTimeout: resourceTimeout,
			captureDelay: captureDelay
		)
		if resourceWaitTimeout > 0 {
			resourceDeadline = now.addingTimeInterval(resourceWaitTimeout)
		} else {
			resourceDeadline = nil
		}
	}

	func timeout(cappedAt cap: TimeInterval?, includingResourceBudget: Bool) -> TimeInterval {
		var remaining = max(0, screenshotDeadline.timeIntervalSinceNow)
		if includingResourceBudget {
			guard let resourceDeadline else {
				return 0
			}
			remaining = min(remaining, max(0, resourceDeadline.timeIntervalSinceNow))
		}
		if let cap {
			remaining = min(remaining, max(0, cap))
		}
		return remaining
	}
}

struct ScreenshotAnimationFrameWaitResult: Decodable {
	let completed: Bool
	let frames: Int
	let reason: String
}
