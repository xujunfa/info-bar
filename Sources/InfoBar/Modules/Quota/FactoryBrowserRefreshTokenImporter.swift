import Foundation
#if os(macOS)
import SweetCookieKit
#endif

protocol FactoryRefreshTokenImporting {
    func importRefreshToken() throws -> String?
}

protocol FactoryRefreshTokenPersisting {
    func persistRefreshToken(_ token: String, origin: String, key: String)
}

struct FactoryBrowserRefreshTokenImporter: FactoryRefreshTokenImporting {
#if os(macOS)
    private let browserClient: BrowserCookieClient
    private let candidateOrigins: [String]

    init(
        browserClient: BrowserCookieClient = BrowserCookieClient(),
        candidateOrigins: [String] = [
            "https://factory.ai",
            "https://www.factory.ai",
            "https://app.factory.ai",
            "https://studio.factory.ai",
            "https://api.factory.ai"
        ]
    ) {
        self.browserClient = browserClient
        self.candidateOrigins = candidateOrigins
    }

    func importRefreshToken() throws -> String? {
        let browsers = Browser.defaultImportOrder.filter(\.usesChromiumProfileStore)

        var visitedProfiles = Set<String>()
        for browser in browsers {
            let stores = browserClient.stores(for: browser)
            for store in stores {
                let profilePath = store.profile.id
                guard visitedProfiles.insert(profilePath).inserted else { continue }

                let levelDBURL = URL(fileURLWithPath: profilePath)
                    .appendingPathComponent("Local Storage")
                    .appendingPathComponent("leveldb")
                var isDir = ObjCBool(false)
                guard FileManager.default.fileExists(atPath: levelDBURL.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                if let token = findRefreshToken(in: levelDBURL) {
                    return token
                }
            }
        }

        return nil
    }

    private func findRefreshToken(in levelDBURL: URL) -> String? {
        for origin in candidateOrigins {
            let entries = ChromiumLocalStorageReader.readEntries(for: origin, in: levelDBURL)
            if let token = entries
                .first(where: { Self.isRefreshTokenKey($0.key) })
                .flatMap({ Self.normalizeToken($0.value) })
            {
                return token
            }
        }

        let textEntries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL)
        if let token = textEntries
            .first(where: { Self.isRefreshTokenKey($0.key) })
            .flatMap({ Self.normalizeToken($0.value) })
        {
            return token
        }

        return nil
    }
#else
    init() {}

    func importRefreshToken() throws -> String? {
        nil
    }
#endif

    private static func isRefreshTokenKey(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains("workos:refresh-token")
    }

    private static func normalizeToken(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }
}

protocol FactoryCommandRunning {
    func run(executable: String, arguments: [String], timeout: TimeInterval) throws -> CLIRunResult
}

extension CLIRunner: FactoryCommandRunning {}

struct FactoryRefreshTokenLocalStoragePersister: FactoryRefreshTokenPersisting {
    private let runner: FactoryCommandRunning
    private let chromiumAppNames: [String]

    init(
        runner: FactoryCommandRunning = CLIRunner(),
        chromiumAppNames: [String] = [
            "Google Chrome",
            "Arc",
            "Brave Browser",
            "Microsoft Edge",
            "Chromium",
            "Vivaldi",
            "Dia"
        ]
    ) {
        self.runner = runner
        self.chromiumAppNames = chromiumAppNames
    }

    func persistRefreshToken(_ token: String, origin: String, key: String) {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        _ = runAppleScript(Self.safariScript, args: [origin, key, normalized])
        for appName in chromiumAppNames {
            _ = runAppleScript(Self.chromiumScript, args: [appName, origin, key, normalized])
        }
    }

    private func runAppleScript(_ script: String, args: [String]) -> Bool {
        let commandArgs = ["-e", script] + args
        guard let result = try? runner.run(
            executable: "/usr/bin/osascript",
            arguments: commandArgs,
            timeout: 3
        ) else {
            return false
        }
        return result.exitCode == 0
    }

    private static let safariScript = """
    on run argv
        set targetOrigin to item 1 of argv
        set storageKey to item 2 of argv
        set tokenValue to item 3 of argv
        tell application "Safari"
            if not running then return
            set currentDocument to missing value
            repeat with docRef in documents
                if (URL of docRef starts with targetOrigin) then
                    set currentDocument to docRef
                    exit repeat
                end if
            end repeat
            if currentDocument is missing value then
                if (count of documents) is 0 then
                    make new document with properties {URL:targetOrigin}
                else
                    set URL of front document to targetOrigin
                end if
                delay 0.3
                set currentDocument to front document
            end if
            set js to "localStorage.setItem(" & quote & storageKey & quote & ", " & quote & tokenValue & quote & ");"
            do JavaScript js in currentDocument
        end tell
    end run
    """

    private static let chromiumScript = """
    on run argv
        set appName to item 1 of argv
        set targetOrigin to item 2 of argv
        set storageKey to item 3 of argv
        set tokenValue to item 4 of argv
        tell application appName
            if not running then return
            set targetTab to missing value
            repeat with winRef in windows
                repeat with tabRef in tabs of winRef
                    if (URL of tabRef starts with targetOrigin) then
                        set targetTab to tabRef
                        exit repeat
                    end if
                end repeat
                if targetTab is not missing value then exit repeat
            end repeat
            if targetTab is missing value then
                if (count of windows) is 0 then make new window
                tell front window
                    set targetTab to make new tab with properties {URL:targetOrigin}
                end tell
                delay 0.3
            end if
            set js to "localStorage.setItem(" & quote & storageKey & quote & ", " & quote & tokenValue & quote & ");"
            execute targetTab javascript js
        end tell
    end run
    """
}
