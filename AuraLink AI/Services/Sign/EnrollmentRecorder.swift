//
//  EnrollmentRecorder.swift
//  AuraLink AI
//
//  Records reference exemplars for a sign — the only way real pose data enters the DTW library.
//  Shares the same capture → vision → segmenter path as translation, so an exemplar is captured
//  under the exact conditions it will later be matched against. This is also the foundation of
//  Phase 5 personalization (enrollment = recording the user's own exemplars).
//

import Foundation

actor EnrollmentRecorder {

    enum RecordingError: Error {
        case cameraUnavailable
        case timedOut
    }

    private let capture: CaptureActor
    private let vision: VisionActor
    private let store: any ExemplarStoring

    init(capture: CaptureActor, vision: VisionActor, store: any ExemplarStoring) {
        self.capture = capture
        self.vision = vision
        self.store = store
    }

    /// Captures the next complete gesture segment and saves it as an exemplar for `lexID`.
    /// The caller performs one sign; the segmenter's pause detection closes the recording.
    /// Returns the new exemplar count for that sign.
    func recordOne(for lexID: String, timeoutSeconds: Double = 20) async throws -> Int {
        await vision.attach(to: capture.frames)
        let features = await vision.subscribeFeatures()

        do {
            try await capture.start()
        } catch {
            throw RecordingError.cameraUnavailable
        }
        defer { Task { await self.capture.stop() } }

        var segmenter = GestureSegmenter()
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        for await feature in features {
            if let segment = segmenter.ingest(feature) {
                try await store.save(SignExemplar(lexID: lexID, segment: segment))
                let counts = (try? await store.counts()) ?? [:]
                return counts[lexID] ?? 1
            }
            if Date() > deadline {
                throw RecordingError.timedOut
            }
        }
        throw RecordingError.timedOut
    }
}
