import Foundation
import AppKit
import LinkPresentation

public final class LinkMetadataService: @unchecked Sendable {
    public static let shared = LinkMetadataService()

    public init() {}

    public func enrichLinkItem(
        itemID: String,
        urlString: String,
        database: DatabaseManager = .shared,
        assetStore: AssetStore = .shared,
        settings: VoidSettings = .shared,
        onUpdated: (@Sendable () -> Void)? = nil
    ) {
        guard settings.generateLinkPreviews,
              let url = URL(string: urlString) else {
            return
        }

        DispatchQueue.main.async {
            let provider = LPMetadataProvider()
            provider.timeout = 8.0
            provider.startFetchingMetadata(for: url) { metadata, _ in
                guard let metadata = metadata else { return }
                let pageTitle = metadata.title
                let hostSummary = url.host?.replacingOccurrences(of: "www.", with: "")

                if let imageProvider = metadata.imageProvider ?? metadata.iconProvider {
                    imageProvider.loadObject(ofClass: NSImage.self) { object, _ in
                        var thumbHash: String? = nil
                        if let nsImage = object as? NSImage,
                           let saved = assetStore.saveImage(nsImage) {
                            thumbHash = saved.thumbHash
                        }
                        database.updateLinkMetadata(
                            id: itemID,
                            linkTitle: pageTitle,
                            linkSummary: hostSummary,
                            thumbnailHash: thumbHash
                        )
                        onUpdated?()
                    }
                } else {
                    database.updateLinkMetadata(
                        id: itemID,
                        linkTitle: pageTitle,
                        linkSummary: hostSummary,
                        thumbnailHash: nil
                    )
                    onUpdated?()
                }
            }
        }
    }
}
