import Foundation

enum WireCommand: String, Codable, Equatable, Sendable {
    case ping
    case browserCreate
    case browserList
    case browserClose
    case browserDump
    case browserResume
    case open
    case page
    case click
    case fill
    case submit
    case eval
    case js
    case text
    case html
    case daemonStop
}

struct WireRequest: Codable, Sendable {
    var command: WireCommand
    var browser: String?
    var url: String?
    var script: String?
    var index: Int?
    var value: String?
    var selector: String?

    init(
        command: WireCommand,
        browser: String? = nil,
        url: String? = nil,
        script: String? = nil,
        index: Int? = nil,
        value: String? = nil,
        selector: String? = nil
    ) {
        self.command = command
        self.browser = browser
        self.url = url
        self.script = script
        self.index = index
        self.value = value
        self.selector = selector
    }

    func requiredBrowserID() throws -> String {
        try browser.nilIfEmpty.unwrap("missing browser id")
    }

    func requiredURL() throws -> URL {
        let rawURL = try url.nilIfEmpty.unwrap("missing URL")
        let normalized = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
        guard let url = URL(string: normalized) else {
            throw WPError.message("invalid URL: \(rawURL)")
        }
        return url
    }

    func requiredScript() throws -> String {
        try script.nilIfEmpty.unwrap("missing JavaScript")
    }

    func requiredIndex() throws -> Int {
        try index.unwrap("missing action number")
    }

    func requiredValue() throws -> String {
        try value.unwrap("missing value")
    }
}

struct WireResponse: Codable, Sendable {
    var ok: Bool
    var browser: String?
    var browsers: [BrowserSummary]?
    var page: PageSnapshot?
    var value: String?
    var text: String?
    var html: String?
    var message: String?
    var error: String?

    static func success(
        browser: String? = nil,
        browsers: [BrowserSummary]? = nil,
        page: PageSnapshot? = nil,
        value: String? = nil,
        text: String? = nil,
        html: String? = nil,
        message: String? = nil
    ) -> WireResponse {
        WireResponse(
            ok: true,
            browser: browser,
            browsers: browsers,
            page: page,
            value: value,
            text: text,
            html: html,
            message: message,
            error: nil
        )
    }

    static func failure(_ message: String) -> WireResponse {
        WireResponse(
            ok: false,
            browser: nil,
            browsers: nil,
            page: nil,
            value: nil,
            text: nil,
            html: nil,
            message: nil,
            error: message
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
    let text: String?
    let actions: [BrowserAction]
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
