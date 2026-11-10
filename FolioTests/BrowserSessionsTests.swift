import CommonCrypto
import Foundation
import Testing
@testable import Folio

/// Builds Apple `.binarycookies` files byte by byte.
private nonisolated enum BinaryCookies {
    struct Cookie {
        var domain: String
        var name: String
        var path: String
        var value: String
        var flags: UInt32 = 0
        /// Seconds since 2001-01-01. Zero means a session cookie.
        var expiry: Double = 0
    }

    static func be32(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }

    static func le32(_ value: UInt32) -> [UInt8] { be32(value).reversed() }

    static func le64(_ value: Double) -> [UInt8] {
        let bits = value.bitPattern
        return (0..<8).map { UInt8(bits >> (8 * UInt64($0)) & 0xFF) }
    }

    static func record(_ cookie: Cookie) -> [UInt8] {
        let header = 56
        let strings = [cookie.domain, cookie.name, cookie.path, cookie.value].map { Array($0.utf8) + [0] }
        var offsets: [UInt32] = []
        var cursor = header
        for string in strings {
            offsets.append(UInt32(cursor))
            cursor += string.count
        }
        var bytes: [UInt8] = []
        bytes += le32(UInt32(cursor))         // +0 size
        bytes += le32(0)                      // +4 unknown
        bytes += le32(cookie.flags)           // +8 flags
        bytes += le32(0)                      // +12 unknown
        bytes += le32(offsets[0])             // +16 domain
        bytes += le32(offsets[1])             // +20 name
        bytes += le32(offsets[2])             // +24 path
        bytes += le32(offsets[3])             // +28 value
        bytes += [UInt8](repeating: 0, count: 8) // +32 comment / end marker
        bytes += le64(cookie.expiry)          // +40 expiry
        bytes += le64(cookie.expiry - 3600)   // +48 creation
        for string in strings { bytes += string }
        return bytes
    }

    static func page(_ cookies: [Cookie]) -> [UInt8] {
        let records = cookies.map(record)
        let headerSize = 4 + 4 + 4 * records.count + 4
        var bytes: [UInt8] = [0x00, 0x00, 0x01, 0x00]
        bytes += le32(UInt32(records.count))
        var offset = headerSize
        for record in records {
            bytes += le32(UInt32(offset))
            offset += record.count
        }
        bytes += le32(0) // page footer
        for record in records { bytes += record }
        return bytes
    }

    static func file(_ pages: [[Cookie]]) -> Data {
        let built = pages.map(page)
        var bytes = Array("cook".utf8)
        bytes += be32(UInt32(built.count))
        for page in built { bytes += be32(UInt32(page.count)) }
        for page in built { bytes += page }
        bytes += [0x07, 0x17, 0x20, 0x05, 0, 0, 0, 0] // checksum/footer, ignored
        return Data(bytes)
    }
}

@Suite struct BinaryCookiesTests {
    let expiry = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func parsesCookiesAcrossPages() throws {
        let data = BinaryCookies.file([
            [
                .init(domain: ".chatgpt.com", name: "__Secure-next-auth.session-token", path: "/", value: "tok",
                      flags: 1 | 4, expiry: expiry.timeIntervalSinceReferenceDate),
                .init(domain: "chatgpt.com", name: "plain", path: "/c", value: "v", flags: 0, expiry: 0),
            ],
            [
                .init(domain: "auth.openai.com", name: "secure-only", path: "/", value: "s", flags: 1,
                      expiry: expiry.timeIntervalSinceReferenceDate),
                .init(domain: "example.com", name: "http-only", path: "/x", value: "h", flags: 4,
                      expiry: expiry.timeIntervalSinceReferenceDate),
            ],
        ])
        let cookies = try BrowserSessions.parseBinaryCookies(data)
        #expect(cookies.count == 4)
        guard cookies.count == 4 else { return }

        #expect(cookies[0].domain == ".chatgpt.com")
        #expect(cookies[0].name == "__Secure-next-auth.session-token")
        #expect(cookies[0].value == "tok")
        #expect(cookies[0].path == "/")
        #expect(cookies[0].isSecure)
        #expect(cookies[0].isHTTPOnly)
        #expect(cookies[0].expires == expiry)
        #expect(cookies[0].isSessionToken)

        #expect(cookies[1].path == "/c")
        #expect(!cookies[1].isSecure)
        #expect(!cookies[1].isHTTPOnly)
        #expect(cookies[1].expires == nil)

        #expect(cookies[2].domain == "auth.openai.com")
        #expect(cookies[2].isSecure)
        #expect(!cookies[2].isHTTPOnly)

        #expect(cookies[3].domain == "example.com")
        #expect(cookies[3].name == "http-only")
        #expect(!cookies[3].isSecure)
        #expect(cookies[3].isHTTPOnly)
    }

    @Test func emptyFileHasNoCookies() throws {
        #expect(try BrowserSessions.parseBinaryCookies(BinaryCookies.file([])).isEmpty)
        #expect(try BrowserSessions.parseBinaryCookies(BinaryCookies.file([[]])).isEmpty)
    }

    @Test(arguments: [
        Data(),
        Data("cook".utf8),
        Data("nope\0\0\0\u{1}".utf8),
        // Claims a page whose size entry isn't there.
        Data(Array("cook".utf8) + BinaryCookies.be32(1)),
        // Claims four billion pages.
        Data(Array("cook".utf8) + BinaryCookies.be32(0xFFFF_FFFF)),
    ])
    func malformedHeaderThrows(data: Data) {
        #expect(throws: (any Error).self) { try BrowserSessions.parseBinaryCookies(data) }
    }

    @Test func truncatedAndCorruptFilesDontCrash() throws {
        let valid = BinaryCookies.file([
            [.init(domain: ".chatgpt.com", name: "a", path: "/", value: "1", flags: 5, expiry: 1000)],
            [.init(domain: "openai.com", name: "b", path: "/", value: "2", flags: 1, expiry: 2000),
             .init(domain: "openai.com", name: "c", path: "/", value: "3")],
        ])
        // Every truncation.
        for length in 0..<valid.count {
            _ = try? BrowserSessions.parseBinaryCookies(valid.prefix(length))
        }
        // Deterministic byte corruption, including the offset and size fields.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        for _ in 0..<3000 {
            var bytes = [UInt8](valid)
            for _ in 0..<(1 + Int(next() % 4)) {
                let index = 4 + Int(next() % UInt64(bytes.count - 4)) // keep the magic so parsing goes deep
                bytes[index] = [0x00, 0xFF, 0x7F, 0x80, UInt8(next() & 0xFF)][Int(next() % 5)]
            }
            _ = try? BrowserSessions.parseBinaryCookies(Data(bytes))
        }
    }
}

@Suite struct ChromiumDecryptTests {
    let key = Data((0..<16).map { UInt8($0 * 7 + 3) })

    func encrypt(_ plain: Data) -> Data {
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: plain.count + kCCBlockSizeAES128)
        var length = 0
        let status = plain.withUnsafeBytes { plainBytes in
            key.withUnsafeBytes { keyBytes in
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, iv,
                        plainBytes.baseAddress, plain.count,
                        &output, output.count, &length)
            }
        }
        precondition(status == kCCSuccess)
        return Data(output[..<length])
    }

    func sha256(_ text: String) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        let bytes = Array(text.utf8)
        CC_SHA256(bytes, CC_LONG(bytes.count), &digest)
        return Data(digest)
    }

    @Test func v10RoundTripWithoutDomainHash() {
        let blob = Data("v10".utf8) + encrypt(Data("session-value.with.dots".utf8))
        #expect(BrowserSessions.decrypt(blob, key: key, stripsDomainHash: false) == "session-value.with.dots")
    }

    @Test func v10RoundTripWithDomainHash() {
        let blob = Data("v10".utf8) + encrypt(sha256(".chatgpt.com") + Data("eyJhbGciOi".utf8))
        #expect(BrowserSessions.decrypt(blob, key: key, stripsDomainHash: true) == "eyJhbGciOi")
    }

    @Test func emptyValueWithDomainHash() {
        let blob = Data("v10".utf8) + encrypt(sha256("chatgpt.com"))
        #expect(BrowserSessions.decrypt(blob, key: key, stripsDomainHash: true) == "")
    }

    @Test func plaintextShorterThanHashIsRejected() {
        let blob = Data("v10".utf8) + encrypt(Data("short".utf8))
        #expect(BrowserSessions.decrypt(blob, key: key, stripsDomainHash: true) == nil)
    }

    @Test func longValueSpanningBlocks() {
        let value = String(repeating: "abcdefghij", count: 40)
        let blob = Data("v10".utf8) + encrypt(Data(value.utf8))
        #expect(BrowserSessions.decrypt(blob, key: key, stripsDomainHash: false) == value)
    }

    @Test func unprefixedBlobPassesThrough() {
        #expect(BrowserSessions.decrypt(Data("plain-cookie".utf8), key: key, stripsDomainHash: false) == "plain-cookie")
        #expect(BrowserSessions.decrypt(Data("plain-cookie".utf8), key: key, stripsDomainHash: true) == "plain-cookie")
    }

    @Test func truncatedCipherDoesNotCrash() {
        // Not a whole AES block: CommonCrypto refuses it.
        let blob = Data("v10".utf8) + Data([1, 2, 3, 4, 5])
        #expect(BrowserSessions.decrypt(blob, key: key, stripsDomainHash: false) == nil)
    }
}

@Suite struct ChatGPTHostTests {
    @Test(arguments: [
        ("chatgpt.com", true),
        (".chatgpt.com", true),
        ("sub.chatgpt.com", true),
        ("CHATGPT.COM", true),
        ("openai.com", true),
        (".openai.com", true),
        ("auth.openai.com", true),
        ("platform.openai.com", false),
        ("evil-chatgpt.com", false),
        ("chatgpt.com.evil.com", false),
        ("example.com", false),
        ("", false),
    ])
    func host(domain: String, expected: Bool) {
        #expect(BrowserSessions.isChatGPTHost(domain) == expected)
    }
}

@Suite struct BrowserCookieTests {
    func cookie(
        domain: String = ".chatgpt.com", name: String = "n", path: String = "/", expires: Date? = nil,
        secure: Bool = false, httpOnly: Bool = false, sameSite: String? = nil
    ) -> BrowserCookie {
        BrowserCookie(domain: domain, name: name, value: "v", path: path, expires: expires,
                      isSecure: secure, isHTTPOnly: httpOnly, sameSite: sameSite)
    }

    @Test func httpCookieCarriesEveryProperty() throws {
        // Foundation caps cookie lifetimes at 400 days, so stay inside that.
        let expires = Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate + 30 * 86_400).rounded())
        let http = try #require(cookie(name: "sid", expires: expires, secure: true, httpOnly: true, sameSite: "lax").httpCookie)
        #expect(http.domain == ".chatgpt.com")
        #expect(http.name == "sid")
        #expect(http.value == "v")
        #expect(http.path == "/")
        #expect(http.isSecure)
        #expect(http.isHTTPOnly)
        #expect(http.expiresDate == expires)
        #expect(!http.isSessionOnly)
        #expect(http.sameSitePolicy == .sameSiteLax)
    }

    @Test func httpCookieDefaults() throws {
        let http = try #require(cookie(domain: "chatgpt.com", path: "").httpCookie)
        #expect(http.path == "/")
        #expect(!http.isSecure)
        #expect(!http.isHTTPOnly)
        #expect(http.expiresDate == nil)
        #expect(http.isSessionOnly)
        #expect(http.sameSitePolicy == nil)
    }

    @Test func strictSameSite() throws {
        let http = try #require(cookie(path: "/api", sameSite: "strict").httpCookie)
        #expect(http.sameSitePolicy == .sameSiteStrict)
        #expect(http.path == "/api")
    }

    @Test func sessionToken() {
        #expect(cookie(name: "__Secure-next-auth.session-token").isSessionToken)
        #expect(cookie(domain: "chatgpt.com", name: "__Secure-next-auth.session-token.0").isSessionToken)
        #expect(!cookie(domain: "evil-chatgpt.com", name: "__Secure-next-auth.session-token").isSessionToken)
        #expect(!cookie(domain: "platform.openai.com", name: "__Secure-next-auth.session-token").isSessionToken)
        #expect(!cookie(name: "next-auth.session-token").isSessionToken)
        #expect(!cookie(name: "__Secure-next-auth.callback-url").isSessionToken)
    }

    @Test func expiry() {
        #expect(!cookie(expires: nil).isExpired)
        #expect(cookie(expires: .now.addingTimeInterval(-60)).isExpired)
        #expect(!cookie(expires: .now.addingTimeInterval(3600)).isExpired)
    }
}
