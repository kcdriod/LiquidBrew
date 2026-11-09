import Foundation

public struct BrewCommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var combinedOutput: String {
        if stderr.isEmpty { return stdout }
        if stdout.isEmpty { return stderr }
        return stdout + "\n" + stderr
    }
}

public enum BrewCLIError: LocalizedError {
    case binaryNotFound
    case executionFailed(String)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Homebrew binary ('brew') could not be found in /opt/homebrew/bin or /usr/local/bin."
        case .executionFailed(let message):
            return message
        case .invalidOutput:
            return "Unable to decode output from Homebrew CLI."
        }
    }
}

public actor BrewCLIService {
    public static let shared = BrewCLIService()

    private let brewExecutableURL: URL
    private let useEnvFallback: Bool

    public init() {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/home/linuxbrew/.linuxbrew/bin/brew"
        ]

        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            self.brewExecutableURL = URL(fileURLWithPath: found)
            self.useEnvFallback = false
        } else {
            self.brewExecutableURL = URL(fileURLWithPath: "/usr/bin/env")
            self.useEnvFallback = true
        }
    }

    // MARK: - Core Process Execution

    private nonisolated func makeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPath = env["PATH"] ?? ""
        let combinedPaths = extraPaths + existingPath.split(separator: ":").map(String.init)
        var seen = Set<String>()
        let deduplicatedPath = combinedPaths.filter { seen.insert($0).inserted }.joined(separator: ":")

        env["PATH"] = deduplicatedPath
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        env["NONINTERACTIVE"] = "1"
        return env
    }

    public func runCommand(_ arguments: [String]) async throws -> BrewCommandResult {
        let execURL = brewExecutableURL
        let envFallback = useEnvFallback
        let environment = makeEnvironment()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = execURL
                process.arguments = envFallback ? (["brew"] + arguments) : arguments
                process.environment = environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let result = BrewCommandResult(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }
        }
    }

    public func streamCommand(
        _ arguments: [String],
        onLine: @escaping @Sendable (String, Bool) -> Void
    ) async throws -> Int32 {
        let execURL = brewExecutableURL
        let envFallback = useEnvFallback
        let environment = makeEnvironment()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = execURL
                process.arguments = envFallback ? (["brew"] + arguments) : arguments
                process.environment = environment

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let lock = NSLock()
                var stdoutBuffer = ""
                var stderrBuffer = ""

                func processChunk(_ data: Data, isError: Bool) {
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    var linesToEmit: [String] = []
                    lock.lock()
                    if isError {
                        stderrBuffer += chunk
                        let parts = stderrBuffer.components(separatedBy: .newlines)
                        if parts.count > 1 {
                            linesToEmit = Array(parts.dropLast())
                            stderrBuffer = parts.last ?? ""
                        }
                    } else {
                        stdoutBuffer += chunk
                        let parts = stdoutBuffer.components(separatedBy: .newlines)
                        if parts.count > 1 {
                            linesToEmit = Array(parts.dropLast())
                            stdoutBuffer = parts.last ?? ""
                        }
                    }
                    lock.unlock()

                    for line in linesToEmit {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onLine(line, isError)
                        }
                    }
                }

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    processChunk(data, isError: false)
                }

                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    processChunk(data, isError: true)
                }

                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                process.waitUntilExit()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                processChunk(remainingOut, isError: false)
                let remainingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                processChunk(remainingErr, isError: true)

                lock.lock()
                let finalOut = stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                let finalErr = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                stdoutBuffer = ""
                stderrBuffer = ""
                lock.unlock()

                if !finalOut.isEmpty {
                    onLine(finalOut, false)
                }
                if !finalErr.isEmpty {
                    onLine(finalErr, true)
                }

                continuation.resume(returning: process.terminationStatus)
            }
        }
    }

    // MARK: - Installed Packages (`brew info --json=v2 --installed`)

    public func fetchInstalledPackages() async throws -> [BrewPackage] {
        let result = try await runCommand(["info", "--json=v2", "--installed"])
        guard let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            return []
        }
        return try Self.parseInfoJSONv2(data: data)
    }

    public static func parseInfoJSONv2(data: Data) throws -> [BrewPackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrewCLIError.invalidOutput
        }

        let formulaeDicts = root["formulae"] as? [[String: Any]] ?? []
        let caskDicts = root["casks"] as? [[String: Any]] ?? []

        // Collect all reverse dependency references across installed formulae to compute `isLeaf`
        var dependedUponNames = Set<String>()
        for formula in formulaeDicts {
            if let deps = formula["dependencies"] as? [String] {
                for dep in deps {
                    dependedUponNames.insert(dep)
                    if let shortName = dep.split(separator: "/").last {
                        dependedUponNames.insert(String(shortName))
                    }
                }
            }
            if let installedArr = formula["installed"] as? [[String: Any]] {
                for inst in installedArr {
                    if let runtimeDeps = inst["runtime_dependencies"] as? [[String: Any]] {
                        for rDep in runtimeDeps {
                            if let fullName = rDep["full_name"] as? String {
                                dependedUponNames.insert(fullName)
                                if let shortName = fullName.split(separator: "/").last {
                                    dependedUponNames.insert(String(shortName))
                                }
                            }
                        }
                    }
                }
            }
        }

        var packages: [BrewPackage] = []
        packages.reserveCapacity(formulaeDicts.count + caskDicts.count)

        for formula in formulaeDicts {
            guard let name = formula["name"] as? String else { continue }
            let fullName = formula["full_name"] as? String ?? name
            let desc = formula["desc"] as? String
            let homepage = formula["homepage"] as? String
            let tap = formula["tap"] as? String
            let license = formula["license"] as? String
            let caveats = formula["caveats"] as? String
            let isOutdated = formula["outdated"] as? Bool ?? false
            let isPinned = formula["pinned"] as? Bool ?? false
            let dependencies = formula["dependencies"] as? [String] ?? []
            let buildDependencies = formula["build_dependencies"] as? [String] ?? []

            let versionsDict = formula["versions"] as? [String: Any]
            let latestStable = versionsDict?["stable"] as? String

            let installedList = formula["installed"] as? [[String: Any]] ?? []
            let installedVersions = installedList.compactMap { $0["version"] as? String }
            let primaryInstalled = installedList.first

            let version = installedVersions.last ?? latestStable ?? "unknown"
            let outdatedVersion: String? = isOutdated ? (latestStable ?? version) : nil
            let isInstalledOnRequest = primaryInstalled?["installed_on_request"] as? Bool ?? true

            var installedTime: Date?
            if let timeValue = primaryInstalled?["time"] as? TimeInterval {
                installedTime = Date(timeIntervalSince1970: timeValue)
            } else if let timeInt = primaryInstalled?["time"] as? Int {
                installedTime = Date(timeIntervalSince1970: TimeInterval(timeInt))
            }

            var runtimeDeps: [String] = []
            if let runtimeList = primaryInstalled?["runtime_dependencies"] as? [[String: Any]] {
                runtimeDeps = runtimeList.compactMap { dict in
                    guard let fn = dict["full_name"] as? String else { return nil }
                    return fn.split(separator: "/").last.map(String.init) ?? fn
                }
            }

            let isLeaf = !dependedUponNames.contains(name) && !dependedUponNames.contains(fullName)

            let pkg = BrewPackage(
                name: name,
                fullName: fullName,
                desc: desc,
                homepage: homepage,
                version: version,
                installedVersions: installedVersions.isEmpty ? [version] : installedVersions,
                outdatedVersion: outdatedVersion,
                isCask: false,
                isOutdated: isOutdated,
                isPinned: isPinned,
                isInstalledOnRequest: isInstalledOnRequest,
                isLeaf: isLeaf,
                tap: tap,
                license: license,
                caveats: caveats,
                dependencies: dependencies,
                buildDependencies: buildDependencies,
                installedTime: installedTime,
                runtimeDependencies: runtimeDeps
            )
            packages.append(pkg)
        }

        for cask in caskDicts {
            guard let token = cask["token"] as? String else { continue }
            let fullToken = cask["full_token"] as? String ?? token
            let names = cask["name"] as? [String]
            let displayFullName = names?.first ?? fullToken
            let desc = cask["desc"] as? String
            let homepage = cask["homepage"] as? String
            let tap = cask["tap"] as? String
            let caveats = cask["caveats"] as? String
            let isOutdated = cask["outdated"] as? Bool ?? false

            let latestVersion = cask["version"] as? String ?? "latest"
            let installedVersion = cask["installed"] as? String ?? latestVersion
            let outdatedVersion: String? = isOutdated ? latestVersion : nil

            var installedTime: Date?
            if let timeValue = cask["installed_time"] as? TimeInterval {
                installedTime = Date(timeIntervalSince1970: timeValue)
            } else if let timeInt = cask["installed_time"] as? Int {
                installedTime = Date(timeIntervalSince1970: TimeInterval(timeInt))
            }

            var dependencies: [String] = []
            if let dependsOn = cask["depends_on"] as? [String: Any] {
                if let formulaDeps = dependsOn["formula"] as? [String] {
                    dependencies.append(contentsOf: formulaDeps)
                }
                if let caskDeps = dependsOn["cask"] as? [String] {
                    dependencies.append(contentsOf: caskDeps)
                }
            }

            let pkg = BrewPackage(
                name: token,
                fullName: displayFullName,
                desc: desc,
                homepage: homepage,
                version: installedVersion,
                installedVersions: [installedVersion],
                outdatedVersion: outdatedVersion,
                isCask: true,
                isOutdated: isOutdated,
                isPinned: false,
                isInstalledOnRequest: true,
                isLeaf: true,
                tap: tap,
                license: nil,
                caveats: caveats,
                dependencies: dependencies,
                buildDependencies: [],
                installedTime: installedTime,
                runtimeDependencies: []
            )
            packages.append(pkg)
        }

        return packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Outdated Packages (`brew outdated --json=v2`)

    public func fetchOutdatedPackages() async throws -> [OutdatedPackage] {
        let result = try await runCommand(["outdated", "--json=v2"])
        guard let data = result.stdout.data(using: .utf8), !data.isEmpty else {
            return []
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var items: [OutdatedPackage] = []

        if let formulae = root["formulae"] as? [[String: Any]] {
            for f in formulae {
                guard let name = f["name"] as? String else { continue }
                let installedVersions: [String]
                if let arr = f["installed_versions"] as? [String] {
                    installedVersions = arr
                } else if let str = f["installed_versions"] as? String {
                    installedVersions = [str]
                } else {
                    installedVersions = []
                }
                let currentVersion = f["current_version"] as? String ?? "latest"
                let isPinned = f["pinned"] as? Bool ?? false
                let pinnedVersion = f["pinned_version"] as? String

                items.append(
                    OutdatedPackage(
                        name: name,
                        installedVersions: installedVersions,
                        currentVersion: currentVersion,
                        isPinned: isPinned,
                        pinnedVersion: pinnedVersion,
                        isCask: false
                    )
                )
            }
        }

        if let casks = root["casks"] as? [[String: Any]] {
            for c in casks {
                guard let name = c["name"] as? String else { continue }
                let installedVersions: [String]
                if let arr = c["installed_versions"] as? [String] {
                    installedVersions = arr
                } else if let str = c["installed_versions"] as? String {
                    installedVersions = [str]
                } else {
                    installedVersions = []
                }
                let currentVersion = c["current_version"] as? String ?? "latest"

                items.append(
                    OutdatedPackage(
                        name: name,
                        installedVersions: installedVersions,
                        currentVersion: currentVersion,
                        isPinned: false,
                        pinnedVersion: nil,
                        isCask: true
                    )
                )
            }
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Background Services (`brew services list --json`)

    public func fetchServices() async throws -> [BrewServiceItem] {
        let jsonResult = try await runCommand(["services", "list", "--json"])
        if jsonResult.exitCode == 0,
           let data = jsonResult.stdout.data(using: .utf8),
           !data.isEmpty,
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { dict -> BrewServiceItem? in
                guard let name = dict["name"] as? String else { return nil }
                let statusRaw = (dict["status"] as? String ?? "unknown").lowercased()
                let status = ServiceStatus(rawValue: statusRaw) ?? .unknown
                let user = dict["user"] as? String
                let file = dict["file"] as? String
                let exitCode = dict["exit_code"] as? Int
                let pid = dict["pid"] as? Int
                return BrewServiceItem(
                    name: name,
                    status: status,
                    user: user,
                    file: file,
                    exitCode: exitCode,
                    pid: pid
                )
            }
        }

        // Fallback to line parsing of `brew services list`
        let textResult = try await runCommand(["services", "list"])
        let lines = textResult.stdout.components(separatedBy: .newlines)
        var services: [BrewServiceItem] = []

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("Name ") { continue }
            let cols = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard cols.count >= 2 else { continue }
            let name = cols[0]
            let statusRaw = cols[1].lowercased()
            let status = ServiceStatus(rawValue: statusRaw) ?? .unknown
            let user = cols.count >= 3 ? cols[2] : nil
            let file = cols.count >= 4 ? cols.dropFirst(3).joined(separator: " ") : nil
            services.append(
                BrewServiceItem(
                    name: name,
                    status: status,
                    user: user == "none" ? nil : user,
                    file: file == "none" ? nil : file
                )
            )
        }
        return services
    }

    // MARK: - Taps (`brew tap-info --json=v1 --installed`)

    public func fetchTaps() async throws -> [BrewTap] {
        let result = try await runCommand(["tap-info", "--json=v1", "--installed"])
        if result.exitCode == 0,
           let data = result.stdout.data(using: .utf8),
           !data.isEmpty,
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { dict -> BrewTap? in
                guard let name = dict["name"] as? String else { return nil }
                let user = dict["user"] as? String ?? ""
                let repo = dict["repo"] as? String ?? ""
                let path = dict["path"] as? String
                let isInstalled = dict["installed"] as? Bool ?? true
                let official = dict["official"] as? Bool ?? name.hasPrefix("homebrew/")
                let remote = dict["remote"] as? String
                let formulaNames = dict["formula_names"] as? [String] ?? []
                let caskTokens = dict["cask_tokens"] as? [String] ?? []
                return BrewTap(
                    name: name,
                    user: user,
                    repo: repo,
                    path: path,
                    isInstalled: isInstalled,
                    official: official,
                    remote: remote,
                    formulaCount: formulaNames.count,
                    caskCount: caskTokens.count
                )
            }
        }

        // Fallback to `brew tap`
        let fallbackResult = try await runCommand(["tap"])
        return fallbackResult.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { BrewTap(name: $0) }
    }

    // MARK: - Remote Search (`brew search`)

    public func searchPackages(query: String, installedNames: Set<String> = []) async throws -> [BrewPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let formulaSearch = runCommand(["search", "--formula", trimmed])
        async let caskSearch = runCommand(["search", "--cask", trimmed])

        let (fRes, cRes) = try await (formulaSearch, caskSearch)

        let formulaNames = fRes.stdout
            .components(separatedBy: .newlines)
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }

        let caskNames = cRes.stdout
            .components(separatedBy: .newlines)
            .flatMap { $0.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }

        // Enrich top matches using `brew info --json=v2` for rich descriptions & versions
        let topFormulae = Array(formulaNames.prefix(15))
        let topCasks = Array(caskNames.prefix(15))
        let targets = topFormulae + topCasks

        if !targets.isEmpty {
            let infoRes = try? await runCommand(["info", "--json=v2"] + targets)
            if let data = infoRes?.stdout.data(using: .utf8),
               let detailed = try? Self.parseRemoteInfoJSONv2(data: data, installedNames: installedNames),
               !detailed.isEmpty {
                return detailed
            }
        }

        var fallbackResults: [BrewPackage] = []
        for f in topFormulae {
            fallbackResults.append(
                BrewPackage(
                    name: f,
                    fullName: f,
                    desc: "Homebrew Formula",
                    version: "latest",
                    isCask: false
                )
            )
        }
        for c in topCasks {
            fallbackResults.append(
                BrewPackage(
                    name: c,
                    fullName: c,
                    desc: "macOS Cask Application",
                    version: "latest",
                    isCask: true
                )
            )
        }
        return fallbackResults
    }

    private static func parseRemoteInfoJSONv2(data: Data, installedNames: Set<String>) throws -> [BrewPackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let formulaeDicts = root["formulae"] as? [[String: Any]] ?? []
        let caskDicts = root["casks"] as? [[String: Any]] ?? []
        var packages: [BrewPackage] = []

        for formula in formulaeDicts {
            guard let name = formula["name"] as? String else { continue }
            let fullName = formula["full_name"] as? String ?? name
            let desc = formula["desc"] as? String
            let homepage = formula["homepage"] as? String
            let tap = formula["tap"] as? String
            let license = formula["license"] as? String
            let caveats = formula["caveats"] as? String
            let dependencies = formula["dependencies"] as? [String] ?? []
            let buildDependencies = formula["build_dependencies"] as? [String] ?? []
            let versionsDict = formula["versions"] as? [String: Any]
            let version = versionsDict?["stable"] as? String ?? "latest"

            packages.append(
                BrewPackage(
                    name: name,
                    fullName: fullName,
                    desc: desc,
                    homepage: homepage,
                    version: version,
                    installedVersions: [version],
                    isCask: false,
                    isOutdated: false,
                    isPinned: false,
                    isInstalledOnRequest: installedNames.contains(name),
                    isLeaf: true,
                    tap: tap,
                    license: license,
                    caveats: caveats,
                    dependencies: dependencies,
                    buildDependencies: buildDependencies
                )
            )
        }

        for cask in caskDicts {
            guard let token = cask["token"] as? String else { continue }
            let names = cask["name"] as? [String]
            let fullName = names?.first ?? token
            let desc = cask["desc"] as? String
            let homepage = cask["homepage"] as? String
            let tap = cask["tap"] as? String
            let caveats = cask["caveats"] as? String
            let version = cask["version"] as? String ?? "latest"

            packages.append(
                BrewPackage(
                    name: token,
                    fullName: fullName,
                    desc: desc,
                    homepage: homepage,
                    version: version,
                    installedVersions: [version],
                    isCask: true,
                    isOutdated: false,
                    isPinned: false,
                    isInstalledOnRequest: installedNames.contains(token),
                    isLeaf: true,
                    tap: tap,
                    license: nil,
                    caveats: caveats
                )
            )
        }

        return packages
    }

    // MARK: - Brewfile Preview

    public func generateBrewfileContent() async throws -> String {
        let result = try await runCommand(["bundle", "dump", "--file=-"])
        if result.exitCode == 0 && !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return result.stdout
        }
        return result.combinedOutput
    }

    // MARK: - Health & Diagnostics

    public func fetchHealthReport() async -> BrewHealthReport {
        async let versionRes = try? runCommand(["--version"])
        async let prefixRes = try? runCommand(["--prefix"])
        async let cacheRes = try? runCommand(["--cache"])
        async let doctorRes = try? runCommand(["doctor"])
        async let cleanupRes = try? runCommand(["cleanup", "-n"])
        async let autoremoveRes = try? runCommand(["autoremove", "-n"])

        let (vOut, pOut, cOut, docOut, cleanOut, autoOut) = await (
            versionRes, prefixRes, cacheRes, doctorRes, cleanupRes, autoremoveRes
        )

        let brewVersion = vOut?.stdout
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Homebrew"

        let homebrewPrefix = pOut?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "/opt/homebrew"

        let cachePath = cOut?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ??
            (NSHomeDirectory() + "/Library/Caches/Homebrew")

        let cacheSizeBytes = Self.calculateDirectorySize(path: cachePath)

        let doctorCombined = docOut?.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Your system is ready to brew."
        let isHealthy = (docOut?.exitCode == 0) || doctorCombined.contains("Your system is ready to brew")

        var warnings: [String] = []
        if !isHealthy {
            let chunks = doctorCombined.components(separatedBy: "Warning:")
            for chunk in chunks.dropFirst() {
                let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    warnings.append("Warning: " + trimmed)
                }
            }
            if warnings.isEmpty && !doctorCombined.isEmpty {
                warnings.append(doctorCombined)
            }
        }

        let cleanupItems = (cleanOut?.stdout ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }

        let autoremoveItems = (autoOut?.stdout ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }

        return BrewHealthReport(
            isHealthy: isHealthy,
            rawOutput: doctorCombined.isEmpty ? "Your system is ready to brew." : doctorCombined,
            warnings: warnings,
            cachePath: cachePath,
            cacheSizeBytes: cacheSizeBytes,
            cleanupDryRunItems: cleanupItems,
            autoremoveCandidates: autoremoveItems,
            brewVersion: brewVersion,
            homebrewPrefix: homebrewPrefix,
            checkedAt: Date()
        )
    }

    private nonisolated static func calculateDirectorySize(path: String) -> Int64 {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
