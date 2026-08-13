import AppKit
import Foundation

/// Ordered snip records (oldest first, newest last). Memory + disk under Application Support.
@MainActor
final class SnipHistoryStore {
    /// Default capacity (Snipaste-like); oldest dropped when exceeded.
    var maxCount: Int {
        didSet {
            guard !isLoading else { return }
            guard maxCount > 0 else {
                maxCount = 1
                return
            }
            pruneIfNeeded()
            persistIndex()
        }
    }

    /// Oldest first, newest last.
    private(set) var records: [SnipRecord] = []

    private let rootURL: URL
    private let fileManager: FileManager
    private var isLoading = false

    var count: Int { records.count }

    var newest: SnipRecord? { records.last }

    init(
        rootURL: URL = SnipHistoryStore.defaultRootURL(),
        maxCount: Int = 20,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        // Avoid didSet writing an empty index before load completes.
        self.isLoading = true
        self.maxCount = max(1, maxCount)
        loadFromDisk()
    }

    func record(at index: Int) -> SnipRecord? {
        guard records.indices.contains(index) else { return nil }
        return records[index]
    }

    /// Append a confirmed snip (memory + disk). Does not overwrite prior entries.
    func append(_ record: SnipRecord) {
        do {
            try writeRecordToDisk(record)
        } catch {
            NSLog("SnipHistory: failed to write record %@: %@", record.id.uuidString, String(describing: error))
        }
        records.append(record)
        pruneIfNeeded()
        persistIndex()
    }

    /// Reload from Application Support (also called from `init`).
    func loadFromDisk() {
        isLoading = true
        defer { isLoading = false }

        records = []
        ensureRootExists()

        let index = readIndex() ?? AnnotationCoding.IndexFile(
            schemaVersion: AnnotationCoding.schemaVersion,
            maxCount: maxCount,
            ids: []
        )
        if index.maxCount > 0 {
            maxCount = index.maxCount
        }

        var loadedIDs: [String] = []
        for idString in index.ids {
            if let record = loadRecord(idString: idString) {
                records.append(record)
                loadedIDs.append(idString)
            } else {
                try? fileManager.removeItem(at: recordDirectory(for: idString))
            }
        }

        pruneIfNeeded()
        if loadedIDs != records.map(\.id.uuidString)
            || index.ids != loadedIDs
            || index.schemaVersion != AnnotationCoding.schemaVersion
            || index.maxCount != maxCount
        {
            persistIndex()
        }
    }

    // MARK: - Disk paths

    nonisolated static func defaultRootURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return support
            .appendingPathComponent("click.yinsb.EggplantShot", isDirectory: true)
            .appendingPathComponent("snip-history", isDirectory: true)
    }

    private var indexURL: URL {
        rootURL.appendingPathComponent("index.json", isDirectory: false)
    }

    private func recordDirectory(for id: UUID) -> URL {
        recordDirectory(for: id.uuidString)
    }

    private func recordDirectory(for idString: String) -> URL {
        rootURL.appendingPathComponent(idString, isDirectory: true)
    }

    // MARK: - Private I/O

    private func ensureRootExists() {
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func pruneIfNeeded() {
        while records.count > maxCount {
            let removed = records.removeFirst()
            try? fileManager.removeItem(at: recordDirectory(for: removed.id))
        }
    }

    private func persistIndex() {
        ensureRootExists()
        let index = AnnotationCoding.IndexFile(
            schemaVersion: AnnotationCoding.schemaVersion,
            maxCount: maxCount,
            ids: records.map(\.id.uuidString)
        )
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("SnipHistory: failed to write index.json: %@", String(describing: error))
        }
    }

    private func readIndex() -> AnnotationCoding.IndexFile? {
        guard fileManager.fileExists(atPath: indexURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode(AnnotationCoding.IndexFile.self, from: data)
        } catch {
            NSLog("SnipHistory: failed to read index.json: %@", String(describing: error))
            return nil
        }
    }

    private func writeRecordToDisk(_ record: SnipRecord) throws {
        ensureRootExists()
        let dir = recordDirectory(for: record.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let png = AnnotationCoding.pngData(from: record.baseImage) else {
            throw StoreError.encodeImageFailed
        }
        try png.write(to: dir.appendingPathComponent("base.png"), options: .atomic)

        let meta = AnnotationCoding.encodeMeta(for: record)
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
    }

    private func loadRecord(idString: String) -> SnipRecord? {
        let dir = recordDirectory(for: idString)
        let metaURL = dir.appendingPathComponent("meta.json")
        let pngURL = dir.appendingPathComponent("base.png")
        guard fileManager.fileExists(atPath: metaURL.path),
              fileManager.fileExists(atPath: pngURL.path)
        else { return nil }

        do {
            let metaData = try Data(contentsOf: metaURL)
            let meta = try JSONDecoder().decode(AnnotationCoding.MetaFile.self, from: metaData)
            let pngData = try Data(contentsOf: pngURL)
            guard let image = AnnotationCoding.image(fromPNG: pngData, pointSize: meta.imagePoints.cgSize)
            else { return nil }
            return AnnotationCoding.decodeRecord(meta: meta, baseImage: image)
        } catch {
            NSLog("SnipHistory: failed to load record %@: %@", idString, String(describing: error))
            return nil
        }
    }

    private enum StoreError: Error {
        case encodeImageFailed
    }
}
