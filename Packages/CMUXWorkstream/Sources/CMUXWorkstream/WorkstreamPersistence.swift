import Foundation

/// Append-only JSONL persistence for `WorkstreamItem`. One item per line,
/// unbounded on disk. The in-memory ring buffer on `WorkstreamStore` is
/// the only cap on working set size; this layer exists for restart
/// recovery and long-term audit.
///
/// Writes are serialized through an actor so the store can fire them off
/// without awaiting disk IO; reads happen on the caller's executor since
/// load runs once per process at launch.
public actor WorkstreamPersistence {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var handle: FileHandle?

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Default JSONL path in the user's cmuxterm state directory.
    public static func defaultFileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".cmuxterm", isDirectory: true)
            .appendingPathComponent("workstream.jsonl", isDirectory: false)
    }

    /// Appends a single item as a JSON line. Creates the file and parent
    /// directory lazily on first write.
    public func append(_ item: WorkstreamItem) throws {
        let data = try encoder.encode(item)
        var line = data
        line.append(0x0A) // "\n"
        let fh = try handleForWriting()
        try fh.seekToEnd()
        try fh.write(contentsOf: line)
    }

    /// Loads the last `limit` items from the file. Order in the returned
    /// array is oldest-first. Missing file returns empty.
    public func loadRecent(limit: Int) throws -> [WorkstreamItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        let lines = data
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .suffix(limit)
        var out: [WorkstreamItem] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            let slice = Data(line)
            if let item = try? decoder.decode(WorkstreamItem.self, from: slice) {
                out.append(item)
            }
            // Malformed lines are dropped silently; the audit log is
            // append-only and we don't want a corrupt row to block startup.
        }
        return out
    }

    /// Truncates the JSONL file. Used by `cmux feed clear`.
    public func clear() throws {
        try? FileManager.default.removeItem(at: fileURL)
        if let fh = handle {
            try? fh.close()
        }
        handle = nil
    }

    private func handleForWriting() throws -> FileHandle {
        if let handle { return handle }
        let fm = FileManager.default
        try fm.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        let fh = try FileHandle(forWritingTo: fileURL)
        handle = fh
        return fh
    }
}
