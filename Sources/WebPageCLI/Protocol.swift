import Foundation

enum WireProtocol {
    static let version = 28
}

enum WireCommand: String, Codable, Equatable, Sendable {
    case ping
    case browserCreate
    case browserList
    case browserClose
    case browserDump
    case browserShow
    case browserHide
    case open
    case page
    case click
    case fill
    case submit
    case eval
    case screenshot
    case coordinate
    case daemonStop
}

struct WireRequest: Codable, Sendable {
    var command: WireCommand
    var browser: String?
    var url: String?
    var script: String?
    var functionBody: Bool?
    var action: String?
    var index: Int?
    var value: String?
    var destinationPath: String?
    var coordinateAction: String?
    var x: Double?
    var y: Double?
    var deltaX: Double?
    var deltaY: Double?

    init(
        command: WireCommand,
        browser: String? = nil,
        url: String? = nil,
        script: String? = nil,
        functionBody: Bool? = nil,
        action: String? = nil,
        index: Int? = nil,
        value: String? = nil,
        destinationPath: String? = nil,
        coordinateAction: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil
    ) {
        self.command = command
        self.browser = browser
        self.url = url
        self.script = script
        self.functionBody = functionBody
        self.action = action
        self.index = index
        self.value = value
        self.destinationPath = destinationPath
        self.coordinateAction = coordinateAction
        self.x = x
        self.y = y
        self.deltaX = deltaX
        self.deltaY = deltaY
    }

    func requiredBrowserID() throws -> String {
        try browser.nilIfEmpty.unwrap("missing browser id")
    }

    func requiredURL() throws -> URL {
        let rawURL = try url.nilIfEmpty.unwrap("missing URL")
        let normalized = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
        guard let url = URL(string: normalized) else {
            throw WBError.message("invalid URL: \(rawURL)")
        }
        return url
    }

    func requiredScript() throws -> String {
        try script.nilIfEmpty.unwrap("missing JavaScript")
    }

    func requiredAction() throws -> String {
        if let action = action.nilIfEmpty {
            return action
        }
        if let index {
            return String(index)
        }
        throw WBError.message("missing action number or ID")
    }

    func requiredValue() throws -> String {
        try value.unwrap("missing value")
    }

    func requiredDestinationPath() throws -> String {
        try destinationPath.nilIfEmpty.unwrap("missing destination path")
    }

    func requiredCoordinateAction() throws -> String {
        try coordinateAction.nilIfEmpty.unwrap("missing coordinate action")
    }

    func requiredX() throws -> Double {
        try x.unwrap("missing x coordinate")
    }

    func requiredY() throws -> Double {
        try y.unwrap("missing y coordinate")
    }

    func requiredDeltaX() throws -> Double {
        try deltaX.unwrap("missing x scroll delta")
    }

    func requiredDeltaY() throws -> Double {
        try deltaY.unwrap("missing y scroll delta")
    }
}

struct WireResponse: Codable, Sendable {
    var protocolVersion: Int?
    var ok: Bool
    var browser: String?
    var browsers: [BrowserSummary]?
    var environment: WBEnvironmentMetadata?
    var page: PageSnapshot?
    var value: String?
    var message: String?
    var error: String?
    var url: String?

    static func success(
        browser: String? = nil,
        browsers: [BrowserSummary]? = nil,
        environment: WBEnvironmentMetadata? = nil,
        page: PageSnapshot? = nil,
        value: String? = nil,
        message: String? = nil,
        url: String? = nil
    ) -> WireResponse {
        WireResponse(
            protocolVersion: WireProtocol.version,
            ok: true,
            browser: browser,
            browsers: browsers,
            environment: environment,
            page: page,
            value: value,
            message: message,
            error: nil,
            url: url
        )
    }

    static func failure(
        _ message: String,
        browser: String? = nil,
        environment: WBEnvironmentMetadata? = nil,
        page: PageSnapshot? = nil,
        url: String? = nil
    ) -> WireResponse {
        WireResponse(
            protocolVersion: WireProtocol.version,
            ok: false,
            browser: browser,
            browsers: nil,
            environment: environment,
            page: page,
            value: nil,
            message: nil,
            error: message,
            url: url
        )
    }
}

struct BrowserSummary: Codable, Sendable {
    let browser: String
    let title: String?
    let url: String?
    let loading: Bool
    let progress: Double
    let actions: Int
    let visible: Bool?
    let createdAt: String
    let updatedAt: String
    let dumped: Bool?
    let dumpedAt: String?
}

struct PageSnapshot: Codable, Sendable {
    let browser: String
    let title: String
    let url: String?
    let loading: Bool
    let progress: Double
    let imageCount: Int?
    let images: [BrowserImage]
    let htmlBytes: Int?
    let text: String?
    let actions: [BrowserAction]

    init(
        browser: String,
        title: String,
        url: String?,
        loading: Bool,
        progress: Double,
        imageCount: Int?,
        images: [BrowserImage],
        htmlBytes: Int?,
        text: String?,
        actions: [BrowserAction]
    ) {
        self.browser = browser
        self.title = title
        self.url = url
        self.loading = loading
        self.progress = progress
        self.imageCount = imageCount
        self.images = images
        self.htmlBytes = htmlBytes
        self.text = text
        self.actions = actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        browser = try container.decode(String.self, forKey: .browser)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        loading = try container.decode(Bool.self, forKey: .loading)
        progress = try container.decode(Double.self, forKey: .progress)
        htmlBytes = try container.decodeIfPresent(Int.self, forKey: .htmlBytes)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        actions = try container.decode([BrowserAction].self, forKey: .actions)

        if let decodedImages = try? container.decode([BrowserImage].self, forKey: .images) {
            images = decodedImages
            imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? decodedImages.count
        } else {
            let legacyImageCount = try container.decodeIfPresent(Int.self, forKey: .images)
            images = []
            imageCount = try container.decodeIfPresent(Int.self, forKey: .imageCount) ?? legacyImageCount
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(browser, forKey: .browser)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(loading, forKey: .loading)
        try container.encode(progress, forKey: .progress)
        try container.encodeIfPresent(imageCount, forKey: .imageCount)
        try container.encode(images, forKey: .images)
        try container.encodeIfPresent(htmlBytes, forKey: .htmlBytes)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encode(actions, forKey: .actions)
    }

    private enum CodingKeys: String, CodingKey {
        case actions
        case browser
        case htmlBytes
        case imageCount
        case images
        case loading
        case progress
        case text
        case title
        case url
    }
}

struct BrowserImage: Codable, Sendable {
    let index: Int
    let url: String
    let alt: String?
}

struct BrowserAction: Codable, Sendable {
    let index: Int
    let id: String
    let kind: String
    let tag: String
    let type: String
    let text: String
    let href: String
    let disabled: Bool
    let selector: String?
}

enum WireCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    static func encodeError(_ message: String) -> Data {
        (try? encode(WireResponse.failure(message))) ?? Data()
    }
}
