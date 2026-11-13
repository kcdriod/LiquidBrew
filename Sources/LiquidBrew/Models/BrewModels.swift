import Foundation
import SwiftUI

// MARK: - Navigation & Filter Models

public enum NavigationTab: String, CaseIterable, Identifiable, Hashable {
    case packages = "Packages"
    case discover = "Discover"
    case updates = "Updates"
    case services = "Services"
    case graph = "Dependency Graph"
    case taps = "Taps & Brewfile"
    case health = "Health & Cleanup"
    case security = "Security"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .packages: return "shippingbox.fill"
        case .discover: return "sparkles"
        case .updates: return "arrow.triangle.2.circlepath.circle.fill"
        case .services: return "gearshape.2.fill"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .taps: return "spigot.fill"
        case .health: return "stethoscope"
        case .security: return "shield.lefthalf.filled"
        }
    }

    public var subtitle: String {
        switch self {
        case .packages: return "Installed Formulae & Casks"
        case .discover: return "Search & Install"
        case .updates: return "Outdated Packages"
        case .services: return "Background Daemons"
        case .graph: return "Visual Dependency Tree"
        case .taps: return "Repositories & Bundle"
        case .health: return "Doctor & Disk Space"
        case .security: return "Reports & Package Warnings"
        }
    }
}

public enum PackageFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case formulae = "Formulae"
    case casks = "Casks"
    case leaves = "Top-Level (Leaves)"
    case pinned = "Pinned"
    case outdated = "Outdated"

    public var id: String { rawValue }
}

// MARK: - Core Homebrew Models

public struct BrewPackage: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(isCask ? "cask" : "formula"):\(name)" }
    public let name: String
    public let fullName: String
    public let desc: String?
    public let homepage: String?
    public let version: String
    public let installedVersions: [String]
    public let outdatedVersion: String?
    public let isCask: Bool
    public let isOutdated: Bool
    public let isPinned: Bool
    public let isInstalledOnRequest: Bool
    public let isLeaf: Bool
    public let tap: String?
    public let license: String?
    public let caveats: String?
    public let dependencies: [String]
    public let buildDependencies: [String]
    public let installedTime: Date?
    public let runtimeDependencies: [String]

    public init(
        name: String,
        fullName: String? = nil,
        desc: String? = nil,
        homepage: String? = nil,
        version: String,
        installedVersions: [String] = [],
        outdatedVersion: String? = nil,
        isCask: Bool = false,
        isOutdated: Bool = false,
        isPinned: Bool = false,
        isInstalledOnRequest: Bool = true,
        isLeaf: Bool = false,
        tap: String? = "homebrew/core",
        license: String? = nil,
        caveats: String? = nil,
        dependencies: [String] = [],
        buildDependencies: [String] = [],
        installedTime: Date? = nil,
        runtimeDependencies: [String] = []
    ) {
        self.name = name
        self.fullName = fullName ?? name
        self.desc = desc
        self.homepage = homepage
        self.version = version
        self.installedVersions = installedVersions.isEmpty ? [version] : installedVersions
        self.outdatedVersion = outdatedVersion
        self.isCask = isCask
        self.isOutdated = isOutdated
        self.isPinned = isPinned
        self.isInstalledOnRequest = isInstalledOnRequest
        self.isLeaf = isLeaf
        self.tap = tap
        self.license = license
        self.caveats = caveats
        self.dependencies = dependencies
        self.buildDependencies = buildDependencies
        self.installedTime = installedTime
        self.runtimeDependencies = runtimeDependencies
    }
}

public struct OutdatedPackage: Identifiable, Hashable, Codable {
    public var id: String { "\(isCask ? "cask" : "formula"):\(name)" }
    public let name: String
    public let installedVersions: [String]
    public let currentVersion: String
    public let isPinned: Bool
    public let pinnedVersion: String?
    public let isCask: Bool

    public init(
        name: String,
        installedVersions: [String],
        currentVersion: String,
        isPinned: Bool = false,
        pinnedVersion: String? = nil,
        isCask: Bool = false
    ) {
        self.name = name
        self.installedVersions = installedVersions
        self.currentVersion = currentVersion
        self.isPinned = isPinned
        self.pinnedVersion = pinnedVersion
        self.isCask = isCask
    }
}

public enum ServiceStatus: String, Codable, CaseIterable {
    case started = "started"
    case stopped = "stopped"
    case error = "error"
    case none = "none"
    case unknown = "unknown"

    public var displayTitle: String {
        switch self {
        case .started: return "Running"
        case .stopped, .none: return "Stopped"
        case .error: return "Error"
        case .unknown: return "Unknown"
        }
    }

    public var color: Color {
        switch self {
        case .started: return .green
        case .stopped, .none: return .secondary
        case .error: return .red
        case .unknown: return .orange
        }
    }
}

public struct BrewServiceItem: Identifiable, Hashable, Codable {
    public var id: String { name }
    public let name: String
    public let status: ServiceStatus
    public let user: String?
    public let file: String?
    public let exitCode: Int?
    public let pid: Int?

    public init(
        name: String,
        status: ServiceStatus,
        user: String? = nil,
        file: String? = nil,
        exitCode: Int? = nil,
        pid: Int? = nil
    ) {
        self.name = name
        self.status = status
        self.user = user
        self.file = file
        self.exitCode = exitCode
        self.pid = pid
    }
}

public struct BrewTap: Identifiable, Hashable, Codable {
    public var id: String { name }
    public let name: String
    public let user: String
    public let repo: String
    public let path: String?
    public let isInstalled: Bool
    public let official: Bool
    public let remote: String?
    public let formulaCount: Int
    public let caskCount: Int

    public init(
        name: String,
        user: String = "",
        repo: String = "",
        path: String? = nil,
        isInstalled: Bool = true,
        official: Bool = false,
        remote: String? = nil,
        formulaCount: Int = 0,
        caskCount: Int = 0
    ) {
        self.name = name
        let parts = name.split(separator: "/")
        self.user = user.isEmpty ? (parts.first.map(String.init) ?? "") : user
        self.repo = repo.isEmpty ? (parts.dropFirst().first.map(String.init) ?? "") : repo
        self.path = path
        self.isInstalled = isInstalled
        self.official = official || name.hasPrefix("homebrew/")
        self.remote = remote
        self.formulaCount = formulaCount
        self.caskCount = caskCount
    }
}

public struct BrewHealthReport: Hashable {
    public let isHealthy: Bool
    public let rawOutput: String
    public let warnings: [String]
    public let cachePath: String
    public let cacheSizeBytes: Int64
    public let cleanupDryRunItems: [String]
    public let autoremoveCandidates: [String]
    public let brewVersion: String
    public let homebrewPrefix: String
    public let checkedAt: Date

    public init(
        isHealthy: Bool = true,
        rawOutput: String = "Your system is ready to brew.",
        warnings: [String] = [],
        cachePath: String = "~/Library/Caches/Homebrew",
        cacheSizeBytes: Int64 = 0,
        cleanupDryRunItems: [String] = [],
        autoremoveCandidates: [String] = [],
        brewVersion: String = "Homebrew",
        homebrewPrefix: String = "/opt/homebrew",
        checkedAt: Date = Date()
    ) {
        self.isHealthy = isHealthy
        self.rawOutput = rawOutput
        self.warnings = warnings
        self.cachePath = cachePath
        self.cacheSizeBytes = cacheSizeBytes
        self.cleanupDryRunItems = cleanupDryRunItems
        self.autoremoveCandidates = autoremoveCandidates
        self.brewVersion = brewVersion
        self.homebrewPrefix = homebrewPrefix
        self.checkedAt = checkedAt
    }

    public var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }
}

public struct CommandLogEntry: Identifiable, Hashable {
    public let id = UUID()
    public let timestamp: Date
    public let text: String
    public let isError: Bool
    public let isCommandHeader: Bool

    public init(
        timestamp: Date = Date(),
        text: String,
        isError: Bool = false,
        isCommandHeader: Bool = false
    ) {
        self.timestamp = timestamp
        self.text = text
        self.isError = isError
        self.isCommandHeader = isCommandHeader
    }
}
