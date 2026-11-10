import CommonCrypto
import Foundation
import Security
import SQLite3

/// A browser profile that holds a ChatGPT sign-in Folio can copy.
nonisolated struct BrowserSession: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case chromium(ChromiumBrowser, cookies: URL)
        case safari(cookies: URL)
    }

    let id: String
    let browserName: String
    let profileName: String?
    let bundleIdentifier: String
    let source: Source
    /// False when macOS blocks reading the cookie file (Safari without Full Disk Access).
    let isReadable: Bool
    let lastUsed: Date?

    /// The keychain item macOS asks about when Folio decrypts the cookies.
    var keychainItem: String? {
        if case .chromium(let browser, _) = source { return browser.keychainService }
        return nil
    }
}

nonisolated struct ChromiumBrowser: Hashable, Sendable {
    let name: String
    let bundleIdentifier: String
    /// The browser's user data folder, relative to `~/Library/Application Support`.
    let dataPath: String
    let keychainService: String

    static let all = [
        ChromiumBrowser(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", dataPath: "Google/Chrome", keychainService: "Chrome Safe Storage"),
        ChromiumBrowser(name: "Chrome Beta", bundleIdentifier: "com.google.Chrome.beta", dataPath: "Google/Chrome Beta", keychainService: "Chrome Safe Storage"),
        ChromiumBrowser(name: "Chrome Canary", bundleIdentifier: "com.google.Chrome.canary", dataPath: "Google/Chrome Canary", keychainService: "Chrome Safe Storage"),
        ChromiumBrowser(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", dataPath: "Arc/User Data", keychainService: "Arc Safe Storage"),
        ChromiumBrowser(name: "Dia", bundleIdentifier: "company.thebrowser.dia", dataPath: "Dia/User Data", keychainService: "Dia Safe Storage"),
        ChromiumBrowser(name: "Brave", bundleIdentifier: "com.brave.Browser", dataPath: "BraveSoftware/Brave-Browser", keychainService: "Brave Safe Storage"),
        ChromiumBrowser(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac", dataPath: "Microsoft Edge", keychainService: "Microsoft Edge Safe Storage"),
        ChromiumBrowser(name: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi", dataPath: "Vivaldi", keychainService: "Vivaldi Safe Storage"),
        ChromiumBrowser(name: "Opera", bundleIdentifier: "com.operasoftware.Opera", dataPath: "com.operasoftware.Opera", keychainService: "Opera Safe Storage"),
        ChromiumBrowser(name: "Comet", bundleIdentifier: "ai.perplexity.comet", dataPath: "Comet", keychainService: "Comet Safe Storage"),
        // Atlas keeps its profiles one level down and shares Chrome's keychain item name.
        ChromiumBrowser(name: "ChatGPT Atlas", bundleIdentifier: "com.openai.atlas", dataPath: "com.openai.atlas/browser-data/host", keychainService: "Chrome Safe Storage"),
        ChromiumBrowser(name: "Chromium", bundleIdentifier: "org.chromium.Chromium", dataPath: "Chromium", keychainService: "Chromium Safe Storage"),
    ]
}

/// A cookie read from another browser, before it becomes an `HTTPCookie`.
nonisolated struct BrowserCookie: Sendable {
    var domain: String
    var name: String
    var value: String
    var path: String
    var expires: Date?
    var isSecure: Bool
    var isHTTPOnly: Bool
    /// "lax", "strict", or nil for none or unspecified.
    var sameSite: String?

    var isSessionToken: Bool {
        name.hasPrefix("__Secure-next-auth.session-token") && BrowserSessions.isChatGPTHost(domain)
    }

    var isExpired: Bool { expires.map { $0 < .now } ?? false }

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path.isEmpty ? "/" : path,
            .name: name,
            .value: value,
        ]
        if isSecure { properties[.secure] = "TRUE" }
        if isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires { properties[.expires] = expires }
        if sameSite == "lax" { properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue }
        if sameSite == "strict" { properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue }
        return HTTPCookie(properties: properties)
    }
}

nonisolated enum SessionImportError: LocalizedError {
    case keychainDenied(String)
    case keychain(OSStatus)
    case unreadable
    case notSignedIn
    case expired(String)

    var errorDescription: String? {
        switch self {
        case .keychainDenied(let item): "Folio wasn't allowed to use “\(item)”."
        case .keychain(let status): "The browser's keychain item couldn't be read (\(status))."
        case .unreadable: "The browser's cookies couldn't be read."
        case .notSignedIn: "That browser isn't signed in to ChatGPT anymore."
        case .expired(let browser): "\(browser)'s ChatGPT sign-in has expired. Open chatgpt.com in \(browser), then try again."
        }
    }
}

/// Finds ChatGPT sign-ins in installed browsers and reads their cookies.
/// Only chatgpt.com and OpenAI sign-in cookies are read; everything else in the browser is left alone.
nonisolated enum BrowserSessions {
    /// Cloudflare bot-check cookies are tied to the browser that earned them, so Folio gets its own.
    static let skippedNames: Set<String> = ["cf_clearance", "__cf_bm", "_cfuvid", "__cflb"]

    static func isChatGPTHost(_ domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com")
            || host == "openai.com" || host == "auth.openai.com"
    }

    private static func isWanted(_ cookie: BrowserCookie) -> Bool {
        isChatGPTHost(cookie.domain) && !skippedNames.contains(cookie.name) && !cookie.isExpired
    }

    // MARK: Finding sessions

    /// Signed-in browser profiles, most recently used first. Safari is listed when its cookies
    /// are unreadable, since it may well be signed in. Doesn't touch the keychain.
    static func find() -> [BrowserSession] {
        var found: [BrowserSession] = []
        for browser in ChromiumBrowser.all {
            for (profile, cookies) in chromiumProfiles(of: browser) {
                guard let rows = try? chromiumRows(at: cookies),
                      let token = rows.rows.first(where: { $0.cookie.isSessionToken && !$0.cookie.isExpired }) else { continue }
                found.append(BrowserSession(
                    id: cookies.path,
                    browserName: browser.name,
                    profileName: profile,
                    bundleIdentifier: browser.bundleIdentifier,
                    source: .chromium(browser, cookies: cookies),
                    isReadable: true,
                    lastUsed: token.lastAccess
                ))
            }
        }
        found.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        if let safari = safariSession() { found.append(safari) }
        return found
    }

    /// Reads the ChatGPT cookies of a session. Chromium browsers make macOS ask before Folio can decrypt them.
    static func cookies(for session: BrowserSession) throws -> [BrowserCookie] {
        let cookies: [BrowserCookie]
        switch session.source {
        case .chromium(let browser, let file):
            let key = try chromiumKey(service: browser.keychainService)
            let table = try chromiumRows(at: file)
            cookies = table.rows.compactMap { row in
                var cookie = row.cookie
                if !row.encrypted.isEmpty {
                    guard let value = decrypt(row.encrypted, key: key, stripsDomainHash: table.version >= 24) else { return nil }
                    cookie.value = value
                }
                return cookie
            }
        case .safari(let file):
            guard let data = try? Data(contentsOf: file) else { throw SessionImportError.unreadable }
            cookies = try parseBinaryCookies(data)
        }
        let wanted = cookies.filter(isWanted)
        guard wanted.contains(where: \.isSessionToken) else { throw SessionImportError.notSignedIn }
        return wanted
    }

    // MARK: Chromium

    /// Profile display names and cookie databases for one browser.
    private static func chromiumProfiles(of browser: ChromiumBrowser) -> [(String?, URL)] {
        let fileManager = FileManager.default
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(browser.dataPath)
        var names: [String: String] = [:]
        if let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] {
            for (folder, info) in cache {
                names[folder] = (info as? [String: Any])?["name"] as? String
            }
        }
        let folders = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        return folders
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") || names[$0] != nil }
            .sorted()
            .compactMap { folder in
                let profile = root.appendingPathComponent(folder)
                let cookies = [profile.appendingPathComponent("Network/Cookies"), profile.appendingPathComponent("Cookies")]
                    .first { fileManager.fileExists(atPath: $0.path) }
                guard let cookies else { return nil }
                // Single-profile browsers name their only profile something generic; leave it out.
                let name = folders.count(where: { $0 == "Default" || $0.hasPrefix("Profile ") }) > 1 ? names[folder] : nil
                return (name, cookies)
            }
    }

    private struct ChromiumRow {
        var cookie: BrowserCookie
        var encrypted: Data
        var lastAccess: Date?
    }

    /// Chromium stores times as microseconds since 1601.
    private static func chromiumDate(_ microseconds: Int64) -> Date? {
        microseconds == 0 ? nil : Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - 11_644_473_600)
    }

    /// Reads the ChatGPT rows from a copy of the database, so a running browser's lock doesn't get in the way.
    private static func chromiumRows(at file: URL) throws -> (version: Int, rows: [ChromiumRow]) {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("Cookies")
        try fileManager.copyItem(at: file, to: copy)
        for suffix in ["-journal", "-wal"] {
            let side = URL(fileURLWithPath: file.path + suffix)
            if fileManager.fileExists(atPath: side.path) {
                try? fileManager.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw SessionImportError.unreadable
        }
        defer { sqlite3_close(db) }

        var version = 0
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version'", -1, &statement, nil) == SQLITE_OK,
           sqlite3_step(statement) == SQLITE_ROW,
           let text = sqlite3_column_text(statement, 0) {
            version = Int(String(cString: text)) ?? 0
        }
        sqlite3_finalize(statement)

        let columns = "host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite, last_access_utc"
        let hosts = "(host_key LIKE '%chatgpt.com' OR host_key LIKE '%openai.com')"
        // Partitioned cookies belong to other sites' embeds; older databases lack the column.
        if sqlite3_prepare_v2(db, "SELECT \(columns) FROM cookies WHERE \(hosts) AND top_frame_site_key = ''", -1, &statement, nil) != SQLITE_OK {
            sqlite3_finalize(statement)
            guard sqlite3_prepare_v2(db, "SELECT \(columns) FROM cookies WHERE \(hosts)", -1, &statement, nil) == SQLITE_OK else {
                throw SessionImportError.unreadable
            }
        }
        defer { sqlite3_finalize(statement) }

        func text(_ column: Int32) -> String {
            sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
        }
        var rows: [ChromiumRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let blobLength = Int(sqlite3_column_bytes(statement, 3))
            let encrypted = sqlite3_column_blob(statement, 3).map { Data(bytes: $0, count: blobLength) } ?? Data()
            let sameSite: String? = switch sqlite3_column_int(statement, 8) {
            case 1: "lax"
            case 2: "strict"
            default: nil
            }
            let cookie = BrowserCookie(
                domain: text(0),
                name: text(1),
                value: text(2),
                path: text(4),
                expires: chromiumDate(sqlite3_column_int64(statement, 5)),
                isSecure: sqlite3_column_int(statement, 6) != 0,
                isHTTPOnly: sqlite3_column_int(statement, 7) != 0,
                sameSite: sameSite
            )
            guard isChatGPTHost(cookie.domain) else { continue }
            rows.append(ChromiumRow(cookie: cookie, encrypted: encrypted, lastAccess: chromiumDate(sqlite3_column_int64(statement, 9))))
        }
        return (version, rows)
    }

    /// The browser's cookie key: PBKDF2 of its "Safe Storage" keychain password. macOS asks the user first.
    private static func chromiumKey(service: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: break
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed: throw SessionImportError.keychainDenied(service)
        default: throw SessionImportError.keychain(status)
        }
        guard let password = result as? Data else { throw SessionImportError.keychain(status) }

        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let derived = password.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                bytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                &key, key.count
            )
        }
        guard derived == kCCSuccess else { throw SessionImportError.keychain(Int32(derived)) }
        return Data(key)
    }

    /// Decrypts a "v10" value: AES-128-CBC with an IV of spaces. Database version 24 and later
    /// prefix the plaintext with a SHA-256 of the cookie's domain.
    static func decrypt(_ blob: Data, key: Data, stripsDomainHash: Bool) -> String? {
        let prefix = blob.prefix(3)
        guard prefix == Data("v10".utf8) || prefix == Data("v11".utf8) else {
            return String(data: blob, encoding: .utf8)
        }
        let cipher = Data(blob.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var length = 0
        let status = cipher.withUnsafeBytes { cipherBytes in
            key.withUnsafeBytes { keyBytes in
                CCCrypt(
                    CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    keyBytes.baseAddress, key.count, iv,
                    cipherBytes.baseAddress, cipher.count,
                    &output, output.count, &length
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        var plain = output[..<length]
        if stripsDomainHash {
            guard plain.count >= 32 else { return nil }
            plain = plain.dropFirst(32)
        }
        return String(bytes: plain, encoding: .utf8)
    }

    // MARK: Safari

    private static func safariSession() -> BrowserSession? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let files = [
            home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"),
            home.appendingPathComponent("Library/Cookies/Cookies.binarycookies"),
        ]
        var blocked: URL?
        for file in files {
            do {
                let data = try Data(contentsOf: file)
                let cookies = try parseBinaryCookies(data)
                guard cookies.contains(where: { $0.isSessionToken && !$0.isExpired }) else { continue }
                return safari(file, isReadable: true)
            } catch CocoaError.fileReadNoPermission {
                blocked = blocked ?? file
            } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EPERM) {
                blocked = blocked ?? file
            } catch {
                continue
            }
        }
        return blocked.map { safari($0, isReadable: false) }
    }

    private static func safari(_ file: URL, isReadable: Bool) -> BrowserSession {
        BrowserSession(
            id: file.path,
            browserName: "Safari",
            profileName: nil,
            bundleIdentifier: "com.apple.Safari",
            source: .safari(cookies: file),
            isReadable: isReadable,
            lastUsed: nil
        )
    }

    /// Parses Apple's `.binarycookies` format: a big-endian page table, then little-endian cookie records.
    static func parseBinaryCookies(_ data: Data) throws -> [BrowserCookie] {
        let bytes = [UInt8](data)
        func u32be(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
        }
        func u32le(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return bytes[at..<at + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        func f64le(_ at: Int) -> Double? {
            guard at >= 0, at + 8 <= bytes.count else { return nil }
            let bits = bytes[at..<at + 8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return Double(bitPattern: bits)
        }
        func string(_ at: Int, limit: Int) -> String? {
            guard at >= 0, at < limit else { return nil }
            guard let end = bytes[at..<limit].firstIndex(of: 0) else { return nil }
            return String(bytes: bytes[at..<end], encoding: .utf8)
        }

        guard bytes.count >= 8, bytes[0..<4].elementsEqual("cook".utf8), let pageCount = u32be(4) else {
            throw SessionImportError.unreadable
        }
        var cookies: [BrowserCookie] = []
        var pageStart = 8 + pageCount * 4
        for page in 0..<pageCount {
            guard let pageSize = u32be(8 + page * 4) else { throw SessionImportError.unreadable }
            defer { pageStart += pageSize }
            let pageEnd = min(pageStart + pageSize, bytes.count)
            guard let count = u32le(pageStart + 4) else { continue }
            for index in 0..<count {
                guard let offset = u32le(pageStart + 8 + index * 4) else { break }
                let start = pageStart + offset
                guard let size = u32le(start), let flags = u32le(start + 8),
                      let domainOffset = u32le(start + 16), let nameOffset = u32le(start + 20),
                      let pathOffset = u32le(start + 24), let valueOffset = u32le(start + 28),
                      let expiry = f64le(start + 40) else { continue }
                let end = min(start + size, pageEnd)
                guard let domain = string(start + domainOffset, limit: end),
                      let name = string(start + nameOffset, limit: end),
                      let path = string(start + pathOffset, limit: end),
                      let value = string(start + valueOffset, limit: end) else { continue }
                cookies.append(BrowserCookie(
                    domain: domain,
                    name: name,
                    value: value,
                    path: path,
                    expires: expiry > 0 ? Date(timeIntervalSinceReferenceDate: expiry) : nil,
                    isSecure: flags & 1 != 0,
                    isHTTPOnly: flags & 4 != 0,
                    sameSite: nil
                ))
            }
        }
        return cookies
    }
}
