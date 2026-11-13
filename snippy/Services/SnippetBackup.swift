//
//  SnippetBackup.swift
//  snippy
//

import Foundation
import OSLog
import SwiftData

/// A portable, human-readable backup of Snippy's settings and snippet tree.
struct SnippyBackup: Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var appVersion: String
    var exportedAt: Date
    var configuration: BackupConfiguration
    var groups: [BackupGroup]

    var counts: SnippetBackupCounts {
        var counts = SnippetBackupCounts()
        Self.count(groups, into: &counts)
        return counts
    }

    private static func count(_ groups: [BackupGroup], into counts: inout SnippetBackupCounts) {
        for group in groups {
            counts.groups += 1
            counts.snippets += group.snippets.count
            count(group.children, into: &counts)
        }
    }
}

struct BackupConfiguration: Codable, Equatable, Sendable {
    var pasteAutomatically: Bool
    var launchAtLogin: Bool
}

struct BackupGroup: Codable, Sendable {
    var name: String
    var iconName: String?
    var createdAt: Date
    var children: [BackupGroup]
    var snippets: [BackupSnippet]
}

struct BackupSnippet: Codable, Sendable {
    var name: String
    var content: String
    var isHidden: Bool?
    var createdAt: Date
    var updatedAt: Date
}

struct SnippetBackupCounts: Equatable, Sendable {
    var groups: Int = 0
    var snippets: Int = 0
}

struct SnippetBackupRestoreResult {
    let counts: SnippetBackupCounts
    let warning: String?
}

enum SnippetBackupError: LocalizedError {
    case unsupportedVersion(Int)
    case fileTooLarge
    case tooManyItems
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            if version > SnippyBackup.currentFormatVersion {
                return "This backup was created by a newer version of Snippy."
            }
            return "This backup uses an unsupported format."
        case .fileTooLarge:
            return "The backup file is too large to import."
        case .tooManyItems:
            return "The backup contains too many groups or snippets."
        case .invalidData(let message):
            return message
        }
    }
}

/// Reads and writes the JSON backup and replaces the SwiftData tree on import.
@MainActor
enum SnippetBackup {
    static let maximumFileSize = 20 * 1024 * 1024
    static let maximumDepth = 128
    static let maximumGroups = 10_000
    static let maximumSnippets = 50_000

    static var currentConfiguration: BackupConfiguration {
        BackupConfiguration(
            pasteAutomatically: SnippyPreferences.pasteAutomatically,
            launchAtLogin: LaunchAtLogin.isEnabled
        )
    }

    // MARK: - Export

    static func makeBackup(in context: ModelContext) throws -> SnippyBackup {
        try makeBackup(in: context, configuration: currentConfiguration)
    }

    static func makeBackup(
        in context: ModelContext,
        configuration: BackupConfiguration
    ) throws -> SnippyBackup {
        let groups = try context.fetch(FetchDescriptor<SnippetGroup>())
        let roots = SnippetStore.rootGroups(from: groups)

        var seen: Set<UUID> = []
        var counts = SnippetBackupCounts()
        var backupGroups: [BackupGroup] = []

        for group in roots {
            backupGroups.append(try makeGroup(group, seen: &seen, counts: &counts))
        }

        return SnippyBackup(
            formatVersion: SnippyBackup.currentFormatVersion,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            exportedAt: .now,
            configuration: configuration,
            groups: backupGroups
        )
    }

    private static func makeGroup(
        _ group: SnippetGroup,
        seen: inout Set<UUID>,
        counts: inout SnippetBackupCounts
    ) throws -> BackupGroup {
        guard seen.insert(group.id).inserted else {
            throw SnippetBackupError.invalidData("The snippet tree contains a cycle.")
        }

        counts.groups += 1

        var children: [BackupGroup] = []
        for child in group.orderedChildren {
            children.append(try makeGroup(child, seen: &seen, counts: &counts))
        }

        var snippets: [BackupSnippet] = []
        for snippet in group.orderedSnippets {
            counts.snippets += 1
            snippets.append(BackupSnippet(
                name: snippet.name,
                content: snippet.content,
                isHidden: snippet.isHidden,
                createdAt: snippet.createdAt,
                updatedAt: snippet.updatedAt
            ))
        }

        return BackupGroup(
            name: group.name,
            iconName: group.iconName,
            createdAt: group.createdAt,
            children: children,
            snippets: snippets
        )
    }

    static func encode(_ backup: SnippyBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            return try encoder.encode(backup)
        } catch {
            throw SnippetBackupError.invalidData("Could not encode the backup: \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    static func read(from url: URL) throws -> SnippyBackup {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > maximumFileSize {
            throw SnippetBackupError.fileTooLarge
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SnippetBackupError.invalidData("Could not read the backup: \(error.localizedDescription)")
        }

        guard data.count <= maximumFileSize else {
            throw SnippetBackupError.fileTooLarge
        }

        return try decode(data)
    }

    static func decode(_ data: Data) throws -> SnippyBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup: SnippyBackup
        do {
            backup = try decoder.decode(SnippyBackup.self, from: data)
        } catch {
            throw SnippetBackupError.invalidData("This file is not a valid Snippy backup.")
        }

        try validate(backup)
        return backup
    }

    static func write(_ backup: SnippyBackup, to url: URL) throws {
        let data = try encode(backup)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw SnippetBackupError.invalidData("Could not write the backup: \(error.localizedDescription)")
        }
    }

    @discardableResult
    static func validate(_ backup: SnippyBackup) throws -> SnippetBackupCounts {
        guard backup.formatVersion == SnippyBackup.currentFormatVersion else {
            throw SnippetBackupError.unsupportedVersion(backup.formatVersion)
        }

        var counts = SnippetBackupCounts()
        try validate(backup.groups, depth: 0, counts: &counts)
        return counts
    }

    private static func validate(
        _ groups: [BackupGroup],
        depth: Int,
        counts: inout SnippetBackupCounts
    ) throws {
        guard depth <= maximumDepth else {
            throw SnippetBackupError.invalidData("The backup is nested too deeply.")
        }

        for group in groups {
            counts.groups += 1
            counts.snippets += group.snippets.count

            guard counts.groups <= maximumGroups, counts.snippets <= maximumSnippets else {
                throw SnippetBackupError.tooManyItems
            }

            try validate(group.children, depth: depth + 1, counts: &counts)
        }
    }

    /// Replaces the current tree with the backup's groups and snippets.
    @discardableResult
    static func replaceSnippets(
        in context: ModelContext,
        with backup: SnippyBackup
    ) throws -> SnippetBackupCounts {
        try validate(backup)

        do {
            try context.delete(model: Snippet.self)
            try context.delete(model: SnippetGroup.self)

            var counts = SnippetBackupCounts()
            for (index, group) in backup.groups.enumerated() {
                insert(group, parent: nil, sortIndex: index, into: context, counts: &counts)
            }

            try context.save()
            return counts
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func insert(
        _ dto: BackupGroup,
        parent: SnippetGroup?,
        sortIndex: Int,
        into context: ModelContext,
        counts: inout SnippetBackupCounts
    ) {
        let group = SnippetGroup(
            name: dto.name,
            parent: parent,
            createdAt: dto.createdAt,
            sortIndex: sortIndex,
            iconName: dto.iconName
        )
        context.insert(group)
        group.parent = parent
        counts.groups += 1

        for (index, snippetDTO) in dto.snippets.enumerated() {
            let snippet = Snippet(
                name: snippetDTO.name,
                content: snippetDTO.content,
                group: group,
                createdAt: snippetDTO.createdAt,
                sortIndex: index,
                isHidden: snippetDTO.isHidden ?? false
            )
            snippet.updatedAt = snippetDTO.updatedAt
            context.insert(snippet)
            snippet.group = group
            counts.snippets += 1
        }

        for (index, child) in dto.children.enumerated() {
            insert(child, parent: group, sortIndex: index, into: context, counts: &counts)
        }
    }

    // MARK: - Restore

    static func restore(
        _ backup: SnippyBackup,
        in context: ModelContext
    ) throws -> SnippetBackupRestoreResult {
        let counts = try replaceSnippets(in: context, with: backup)

        UserDefaults.standard.set(
            backup.configuration.pasteAutomatically,
            forKey: SnippyPreferences.pasteAutomaticallyKey
        )

        var warning: String?
        if backup.configuration.launchAtLogin != LaunchAtLogin.isEnabled {
            do {
                try LaunchAtLogin.setEnabled(backup.configuration.launchAtLogin)
            } catch {
                warning = "Launch at login couldn't be updated: \(error.localizedDescription)"
                AppLog.settings.error(
                    "Failed to restore launch at login: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return SnippetBackupRestoreResult(counts: counts, warning: warning)
    }
}
