import Foundation

public final class RetentionService: @unchecked Sendable {
    private let database: DatabaseManager
    private let assetStore: AssetStore
    private let settings: VoidSettings
    private var timer: Timer?

    public init(
        database: DatabaseManager = .shared,
        assetStore: AssetStore = .shared,
        settings: VoidSettings = .shared
    ) {
        self.database = database
        self.assetStore = assetStore
        self.settings = settings
    }

    public func startPeriodicCleanup(intervalSeconds: TimeInterval = 3600) {
        stopPeriodicCleanup()
        runCleanupNow()
        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
                self?.runCleanupNow()
            }
        }
    }

    public func stopPeriodicCleanup() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    public func runCleanupNow() -> (deletedItems: Int, deletedBlobs: Int) {
        var deletedItems = 0
        if let interval = settings.retentionPeriod.timeInterval {
            let cutoff = Date().addingTimeInterval(-interval)
            deletedItems = database.pruneExpiredUnpinnedItems(olderThan: cutoff)
        }
        let referenced = database.allReferencedAssetHashes()
        let deletedBlobs = assetStore.garbageCollect(referencedHashes: referenced)
        return (deletedItems, deletedBlobs)
    }

    @discardableResult
    public func eraseAllUnpinnedHistory() -> (deletedItems: Int, deletedBlobs: Int) {
        let deletedItems = database.eraseAllUnpinnedHistory()
        let referenced = database.allReferencedAssetHashes()
        let deletedBlobs = assetStore.garbageCollect(referencedHashes: referenced)
        return (deletedItems, deletedBlobs)
    }
}
