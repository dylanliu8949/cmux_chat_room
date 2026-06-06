public import Foundation
public import CmuxChatRoomCore

/// JSON-file-per-room ``ChatHistoryStore``, keyed by the stable ``ChatRoomID`` so history reconnects
/// after restore even though `Workspace.id` is re-minted.
///
/// Each room is one file `<directory>/<chatRoomID>.json` holding an ordered (oldest-first) array of
/// ``Exchange``. The directory is injected for testability.
public actor JSONChatHistoryStore: ChatHistoryStore {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cache: [ChatRoomID: [Exchange]] = [:]

    /// Creates a store rooted at `directory` (created on first write if absent).
    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    private func fileURL(_ room: ChatRoomID) -> URL {
        directory.appendingPathComponent("\(room.raw.uuidString).json")
    }

    private func load(_ room: ChatRoomID) -> [Exchange] {
        if let cached = cache[room] { return cached }
        guard let data = try? Data(contentsOf: fileURL(room)),
              let list = try? decoder.decode([Exchange].self, from: data) else {
            cache[room] = []
            return []
        }
        cache[room] = list
        return list
    }

    private func persist(_ list: [Exchange], _ room: ChatRoomID) {
        cache[room] = list
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? encoder.encode(list) {
            try? data.write(to: fileURL(room), options: .atomic)
        }
    }

    public func append(_ exchange: Exchange, in room: ChatRoomID) {
        var list = load(room)
        list.append(exchange)
        persist(list, room)
    }

    public func update(_ exchange: Exchange, in room: ChatRoomID) {
        var list = load(room)
        guard let i = list.firstIndex(where: { $0.id == exchange.id }) else { return }
        list[i] = exchange
        persist(list, room)
    }

    public func recent(in room: ChatRoomID, limit: Int) -> [Exchange] {
        Array(load(room).suffix(limit))
    }

    public func page(in room: ChatRoomID, before: ExchangeID, limit: Int) -> [Exchange] {
        let list = load(room)
        guard let i = list.firstIndex(where: { $0.id == before }) else { return [] }
        return Array(list[..<i].suffix(limit))
    }
}
