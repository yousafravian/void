import Foundation
import AppKit
import Vision

public final class VisionOCRService: @unchecked Sendable {
    public static let shared = VisionOCRService()
    private let queue = DispatchQueue(label: "com.voidapp.mac.vision-ocr", qos: .userInitiated)

    public init() {}

    public func performOCR(on image: NSImage) -> (text: String, regions: [OCRTextRegion]) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ("", [])
        }

        var recognizedLines: [String] = []
        var regions: [OCRTextRegion] = []

        let request = VNRecognizeTextRequest { req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let topCandidate = obs.topCandidates(1).first else { continue }
                let str = topCandidate.string
                recognizedLines.append(str)
                let box = obs.boundingBox
                // Convert Vision bottom-left origin to top-left origin normalized coordinates (0...1)
                let topOriginY = 1.0 - box.origin.y - box.size.height
                regions.append(
                    OCRTextRegion(
                        text: str,
                        x: Double(box.origin.x),
                        y: Double(max(0, topOriginY)),
                        width: Double(box.size.width),
                        height: Double(box.size.height)
                    )
                )
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return (recognizedLines.joined(separator: "\n"), regions)
    }

    public func enrichImageItemAsync(
        itemID: String,
        imageHash: String,
        database: DatabaseManager = .shared,
        assetStore: AssetStore = .shared,
        onUpdated: (@Sendable () -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self = self,
                  let image = assetStore.loadImage(forHash: imageHash) else {
                return
            }
            let result = self.performOCR(on: image)
            guard !result.text.isEmpty else { return }
            database.updateOCR(id: itemID, ocrText: result.text, ocrBoxes: result.regions)
            onUpdated?()
        }
    }
}
