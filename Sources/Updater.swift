import Foundation

// Check for Updates, the half that has no window in it.
//
// Paintbox is installed by building it on the user's own Mac (install.sh; CLAUDE.md says
// why), so "updating" can only mean running that installer again. Everything here is the
// part of that which can be decided without a network or a screen: what this copy was
// built from, what GitHub's answer means, whether a check is due, where the new copy
// goes, and what the installer's output says. UpdateUI.swift does the asking and the
// showing. The split is what lets --selftest prove all of it with no network at all.

// MARK: - What this copy was built from

/// The source commit build.sh stamped into Info.plist.
///
/// A version number would be the usual answer, but nobody bumps one here: every push to
/// main is the release, and the installer builds whatever main is. The commit is the only
/// version that is always true.
struct BuildStamp: Equatable {
    static let commitKey = "PaintboxCommit"
    static let commitDateKey = "PaintboxCommitDate"
    static let buildDateKey = "PaintboxBuildDate"

    /// Forty lowercase hex digits, or nil. A stamp that is present but not a commit — a
    /// hand-edited plist, a build.sh that ran with no git and no tarball header — is
    /// treated exactly like a missing one: "I cannot tell", never "up to date".
    let commit: String?
    let commitDate: Date?
    let buildDate: Date?

    init(info: [String: Any]?) {
        let raw = (info?[BuildStamp.commitKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        commit = raw.flatMap { BuildStamp.isCommit($0) ? $0 : nil }
        commitDate = (info?[BuildStamp.commitDateKey] as? String).flatMap(BuildStamp.parseDate)
        buildDate = (info?[BuildStamp.buildDateKey] as? String).flatMap(BuildStamp.parseDate)
    }

    static var current: BuildStamp { BuildStamp(info: Bundle.main.infoDictionary) }

    static func isCommit(_ s: String) -> Bool {
        s.count == 40 && s.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// git's `%cI` carries an offset, GitHub's API says `Z`; the internet-date-time
    /// format reads both.
    static func parseDate(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s)
    }

    var shortCommit: String? { commit.map { String($0.prefix(7)) } }

    static func display(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return f.string(from: date)
    }

    /// The parenthesised part of About's "Version 1.0 (…)": which commit, and from when.
    /// The commit's own date when git gave one, else the day it was built, which is the
    /// best a tarball install can say.
    func aboutVersion(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let when: String? = commitDate.map { BuildStamp.display($0, locale: locale, timeZone: timeZone) }
            ?? buildDate.map { "built " + BuildStamp.display($0, locale: locale, timeZone: timeZone) }
        switch (shortCommit, when) {
        case let (c?, w?): return "\(c), \(w)"
        case let (c?, nil): return c
        case let (nil, w?): return "unknown commit, \(w)"
        case (nil, nil): return "unknown build"
        }
    }
}

// MARK: - GitHub, as data

/// The repository the app updates from, and how to read GitHub's answers about it.
///
/// Fixed, not configurable: the app only ever asks about the repository the installer
/// builds from. PAINTBOX_REPO still points the INSTALLER elsewhere for testing.
enum GitHub {
    static let api = URL(string: "https://api.github.com/repos/pivable/paintbox")!
    static let branch = "main"
    static let installerURL = URL(string: "https://raw.githubusercontent.com/pivable/paintbox/main/install.sh")!
    static var installCommand: String { "curl -fsSL \(installerURL.absoluteString) | bash" }

    static var latestURL: URL { api.appendingPathComponent("commits/\(branch)") }

    /// `base...head`: GitHub's `status` then says how `head` (main) stands relative to
    /// `base` (this copy).
    static func compareURL(installed: String, latest: String) -> URL {
        api.appendingPathComponent("compare/\(installed)...\(latest)")
    }

    struct Commit: Equatable {
        var sha: String
        var subject: String
        var date: Date?
    }

    struct Comparison: Equatable {
        /// "ahead": main has commits this copy lacks. "behind": this copy is newer than
        /// main, which is a developer's build. "identical", or "diverged".
        var status: String
        var totalCommits: Int
        /// Newest first, which is how people read a list of changes. GitHub sends them
        /// oldest first.
        var subjects: [String]
    }

    /// The first line of a commit message is its subject; the rest is a body and, here,
    /// usually a Co-Authored-By trailer nobody needs in a dialog.
    static func subject(of message: String) -> String {
        message.split(separator: "\n", omittingEmptySubsequences: false).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    static func parseLatest(_ data: Data) -> Commit? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = (obj["sha"] as? String)?.lowercased(), BuildStamp.isCommit(sha),
              let commit = obj["commit"] as? [String: Any]
        else { return nil }
        let message = commit["message"] as? String ?? ""
        let date = ((commit["committer"] as? [String: Any])?["date"] as? String).flatMap(BuildStamp.parseDate)
        return Commit(sha: sha, subject: subject(of: message), date: date)
    }

    static func parseCompare(_ data: Data) -> Comparison? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? String
        else { return nil }
        let commits = obj["commits"] as? [[String: Any]] ?? []
        let subjects = commits.compactMap { c -> String? in
            ((c["commit"] as? [String: Any])?["message"] as? String).map(subject(of:))
        }
        return Comparison(status: status,
                          totalCommits: obj["total_commits"] as? Int ?? subjects.count,
                          subjects: Array(subjects.reversed()))
    }
}

// MARK: - The verdict

enum UpdateVerdict: Equatable {
    case upToDate(latest: GitHub.Commit)
    /// `installedKnown` is false when this copy carries no usable stamp — an install from
    /// before stamping existed, or a garbled plist. Offering the update is right then: the
    /// installer is safe to re-run, and saying "up to date" would be a guess.
    /// `changes` is empty when GitHub could not say what changed, which is not a reason to
    /// withhold the update.
    case available(latest: GitHub.Commit, installedKnown: Bool, changes: [String], totalChanges: Int)

    static func decide(installed: String?, latest: GitHub.Commit, comparison: GitHub.Comparison?) -> UpdateVerdict {
        guard let installed = installed, BuildStamp.isCommit(installed) else {
            return .available(latest: latest, installedKnown: false, changes: [], totalChanges: 0)
        }
        if installed == latest.sha { return .upToDate(latest: latest) }
        switch comparison?.status {
        case "identical", "behind":
            // A build NEWER than main is somebody working on Paintbox. Replacing their
            // build with an older one is not an update.
            return .upToDate(latest: latest)
        default:
            let changes = comparison?.status == "ahead" || comparison?.status == "diverged"
                ? comparison?.subjects ?? [] : []
            return .available(latest: latest, installedKnown: true, changes: changes,
                              totalChanges: comparison?.totalCommits ?? changes.count)
        }
    }
}

// MARK: - Asking

enum FetchResult {
    case ok(Data)
    case status(Int)
    case failed(String)
}

/// The network seam. The app's fetcher is a URLSession; the self-test's answers from a
/// dictionary and records every URL it was asked for, which is how the suite proves it
/// never reaches past api.github.com and never reaches anything at all during a test.
protocol UpdateFetching {
    func fetch(_ url: URL, completion: @escaping (FetchResult) -> Void)
}

enum UpdateCheckError: Error, Equatable {
    case unreachable(String)
    case rateLimited
    case http(Int)
    case unreadable

    var message: String {
        switch self {
        case .unreachable(let why):
            return "GitHub could not be reached (\(why)). Check the connection and try again."
        case .rateLimited:
            return "GitHub is limiting how often it can be asked right now. Try again in an hour."
        case .http(let code):
            return "GitHub answered with an error (HTTP \(code)). Try again later."
        case .unreadable:
            return "GitHub's answer could not be read."
        }
    }
}

enum UpdateCheck {
    /// One request when there is nothing to compare, two when there is. The compare is a
    /// nicety: if it fails, the update is still offered, just without the list.
    static func run(installed: String?, fetcher: UpdateFetching,
                    completion: @escaping (Result<UpdateVerdict, UpdateCheckError>) -> Void) {
        fetcher.fetch(GitHub.latestURL) { result in
            let latest: GitHub.Commit
            switch result {
            case .failed(let why): return completion(.failure(.unreachable(why)))
            // Unauthenticated callers get 60 requests an hour per address, and GitHub
            // says so with 403 as often as with 429.
            case .status(403), .status(429): return completion(.failure(.rateLimited))
            case .status(let code): return completion(.failure(.http(code)))
            case .ok(let data):
                guard let parsed = GitHub.parseLatest(data) else { return completion(.failure(.unreadable)) }
                latest = parsed
            }
            guard let installed = installed, BuildStamp.isCommit(installed), installed != latest.sha else {
                return completion(.success(UpdateVerdict.decide(installed: installed, latest: latest, comparison: nil)))
            }
            fetcher.fetch(GitHub.compareURL(installed: installed, latest: latest.sha)) { cmp in
                var comparison: GitHub.Comparison?
                if case .ok(let data) = cmp { comparison = GitHub.parseCompare(data) }
                completion(.success(UpdateVerdict.decide(installed: installed, latest: latest, comparison: comparison)))
            }
        }
    }
}

/// The real fetcher. Ephemeral, so nothing about the request is cached or kept in a
/// cookie jar; no token, so nothing identifies the user beyond the request itself.
final class URLSessionFetcher: UpdateFetching {
    private let session: URLSession

    init(timeout: TimeInterval = 15) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        session = URLSession(configuration: config)
    }

    func fetch(_ url: URL, completion: @escaping (FetchResult) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub refuses API requests that carry no User-Agent at all.
        request.setValue("Paintbox", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            let result: FetchResult
            if let error = error {
                result = .failed(error.localizedDescription)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .status(http.statusCode)
            } else {
                result = .ok(data ?? Data())
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

// MARK: - When to ask by itself

/// The two settings, in whatever defaults it is handed. The app hands it the standard
/// ones; the self-test hands it a throwaway suite, so a test run never changes what the
/// user chose.
struct UpdatePreferences {
    static let automaticKey = "CheckForUpdatesAutomatically"
    static let lastCheckKey = "LastUpdateCheck"
    static let interval: TimeInterval = 24 * 60 * 60

    let defaults: UserDefaults

    /// On unless somebody turned it off. Read as "absent means on" rather than through
    /// `register(defaults:)`, so it is true in every process, including one that never
    /// registered anything.
    var checksAutomatically: Bool {
        get { defaults.object(forKey: UpdatePreferences.automaticKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: UpdatePreferences.automaticKey) }
    }

    var lastCheck: Date? {
        get { defaults.object(forKey: UpdatePreferences.lastCheckKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: UpdatePreferences.lastCheckKey) }
    }

    /// At most once a day. A last check in the FUTURE means the clock was wrong then or is
    /// wrong now; trusting it would silence the check until that date comes round.
    func automaticCheckDue(now: Date) -> Bool {
        guard checksAutomatically else { return false }
        guard let last = lastCheck else { return true }
        return last > now || now.timeIntervalSince(last) >= UpdatePreferences.interval
    }
}

// MARK: - Running the installer

enum UpdateInstall {
    enum Phase: Int, CaseIterable {
        case fetching, building, checking, installing

        var title: String {
            switch self {
            case .fetching: return "Fetching the source"
            case .building: return "Building"
            case .checking: return "Checking it works"
            case .installing: return "Installing"
            }
        }
    }

    /// install.sh announces each step on a line of its own; this is the one place that
    /// knows those lines. Prefixes, because the installing line carries the folder.
    static func phase(forLine line: String) -> Phase? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("Fetching the source") { return .fetching }
        if t.hasPrefix("Building") { return .building }
        if t.hasPrefix("Checking it works") { return .checking }
        if t.hasPrefix("Installing to") || t.hasPrefix("Replacing the copy") { return .installing }
        return nil
    }

    /// install.sh's last word on success, and the only proof it got that far: a zero exit
    /// status alone could come from an installer that changed shape.
    static func succeeded(status: Int32, log: String) -> Bool {
        status == 0 && log.contains("Installed to ")
    }

    /// The folder that holds the RUNNING copy, so an install in ~/Applications is updated
    /// in ~/Applications rather than gaining a second copy in /Applications.
    ///
    /// nil when there is no sensible answer: a bundle that is not an .app (the self-test
    /// binary run on its own), or one macOS has translocated to a randomised read-only
    /// path, where the folder is not where the user put it at all.
    static func destination(forBundle bundle: URL) -> URL? {
        let b = bundle.standardizedFileURL
        guard b.pathExtension == "app", !b.path.contains("/AppTranslocation/") else { return nil }
        return b.deletingLastPathComponent()
    }

    /// The new copy lands as `Paintbox.app` in the destination, whatever the running one
    /// is called, because that is the name install.sh writes.
    static func installedApp(in destination: URL) -> URL {
        destination.appendingPathComponent("Paintbox.app")
    }

    /// Why the installer would fail to write, said before a minute of building rather
    /// than after. Replacing the bundle means renaming it, which needs the folder to be
    /// writable — and on macOS renaming a directory needs the directory itself writable too.
    static func destinationProblem(destination: URL, isWritable: (String) -> Bool) -> String? {
        let app = installedApp(in: destination)
        let fm = FileManager.default
        if !isWritable(destination.path) || (fm.fileExists(atPath: app.path) && !isWritable(app.path)) {
            // The command has to name the folder: bare `sudo bash` installs to /Applications,
            // which would leave the copy that could not be replaced exactly as it was.
            let target = destination.standardizedFileURL.path == "/Applications" ? ""
                : "PAINTBOX_DEST='\(destination.path)' "
            return """
                Paintbox is in \(destination.path), which this account cannot change, so the \
                update cannot replace it. Either move Paintbox to the Applications folder in \
                your home folder, or update from Terminal with:

                    curl -fsSL \(GitHub.installerURL.absoluteString) | sudo \(target)bash
                """
        }
        return nil
    }

    static let commandLineToolsMessage = """
        Apple's command line tools are missing, so there is no Swift compiler to build the \
        update with. Install them (it is free; Xcode itself is not needed) by running this in \
        Terminal, then choose Check for Updates again:

            xcode-select --install
        """

    /// What to tell somebody whose update failed, taken from the installer's own words.
    /// install.sh's `die` prints a blank line, the reason, and a blank line; the reason is
    /// the last such block.
    static func failureMessage(log: String, status: Int32) -> String {
        if log.contains("command line tools are missing") { return commandLineToolsMessage }
        let blocks = log.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let reason = blocks.last.map { block in
            block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        } ?? "The installer stopped with status \(status) and said nothing."
        return reason
    }

    /// The installer's environment: the user's, plus where to install and the request not
    /// to open the app itself — the app offers "Relaunch now" instead, and two copies of
    /// Paintbox running at once is what the installer's own `open` would otherwise give.
    /// PATH is set because an app started from the Finder inherits a minimal one.
    static func environment(base: [String: String], destination: URL) -> [String: String] {
        var env = base
        env["PAINTBOX_DEST"] = destination.path
        env["PAINTBOX_NO_OPEN"] = "1"
        let system = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = (base["PATH"].map { $0 + ":" } ?? "") + system
        return env
    }

    /// `/bin/sh` arguments that wait for this process to be gone and then open the new
    /// copy. Waiting is the point: opening the bundle while this process still runs would
    /// just activate THIS process again, which is the old code.
    static func relaunchArguments(pid: Int32, app: URL) -> [String] {
        ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\"",
         "paintbox-relaunch", String(pid), app.path]
    }

    /// Where the full installer output is kept, for "Show Log".
    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Paintbox/update.log")
    }
}
