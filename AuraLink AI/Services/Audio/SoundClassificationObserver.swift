//
//  SoundClassificationObserver.swift
//  AuraLink AI
//
//  Receives SoundAnalysis results on the analysis queue and forwards curated `SoundEvent`s. Kept
//  separate from the analyzer so the mapping (SoundEventMapper) stays testable and framework-free.
//
//  `@unchecked Sendable`: an `NSObject` (not `Sendable`) invoked only on the single analysis
//  DispatchQueue; the forwarding closure is itself `@Sendable`.
//

import SoundAnalysis

nonisolated final class SoundClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {

    private let onEvent: @Sendable (SoundEvent) -> Void

    init(onEvent: @escaping @Sendable (SoundEvent) -> Void) {
        self.onEvent = onEvent
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult,
              let top = classification.classifications.first else { return }
        if let event = SoundEventMapper.event(identifier: top.identifier,
                                              confidence: Float(top.confidence),
                                              timeSeconds: classification.timeRange.start.seconds) {
            onEvent(event)
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}
