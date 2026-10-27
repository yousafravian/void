import Foundation

public enum VoidUndoAction: Sendable {
    case restoreDeletedItems([ClipboardItem])
    case restoreItemSnapshot(ClipboardItem)
    case restorePinboard(Pinboard, pinnedItems: [ClipboardItem])

    public var actionName: String {
        switch self {
        case .restoreDeletedItems(let items):
            return items.count == 1 ? "Delete Item" : "Delete \(items.count) Items"
        case .restoreItemSnapshot:
            return "Edit Item"
        case .restorePinboard(let board, _):
            return "Delete Pinboard \"\(board.name)\""
        }
    }
}

public final class UndoManagerService: @unchecked Sendable {
    public static let shared = UndoManagerService()

    private let database: DatabaseManager
    private var stack: [VoidUndoAction] = []
    private let maxDepth = 50
    private let lock = NSLock()

    public init(database: DatabaseManager = .shared) {
        self.database = database
    }

    public var canUndo: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !stack.isEmpty
    }

    public func record(_ action: VoidUndoAction) {
        lock.lock()
        defer { lock.unlock() }
        stack.append(action)
        if stack.count > maxDepth {
            stack.removeFirst(stack.count - maxDepth)
        }
    }

    @discardableResult
    public func undoLast() -> VoidUndoAction? {
        lock.lock()
        guard let action = stack.popLast() else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        switch action {
        case .restoreDeletedItems(let items):
            for item in items {
                database.saveItem(item)
            }
        case .restoreItemSnapshot(let snapshot):
            database.saveItem(snapshot)
        case .restorePinboard(let board, let pinnedItems):
            database.savePinboard(board)
            for item in pinnedItems {
                database.saveItem(item)
            }
        }
        return action
    }
}
