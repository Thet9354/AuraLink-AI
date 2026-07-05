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

    /// Records `count` exemplars in one continuous capture session. The user performs the sign,
    /// holds (one saved), moves the hand to re-arm, holds again — `onSaved` fires after each so the
    /// UI can auto-advance ("2 of 3"). Keeping capture open across reps avoids restart lag.
    /// Returns the final exemplar count for the sign.
    func recordSession(for lexID: String,
                       count: Int,
                       perRepTimeoutSeconds: Double = 20,
                       onSaved: @escaping @Sendable (Int) -> Void) async throws -> Int {
        await vision.attach(to: capture.frames)
        let features = await vision.subscribeFeatures()

        do {
            try await capture.start()
        } catch {
            throw RecordingError.cameraUnavailable
        }
        defer { Task { await self.capture.stop() } }

        var segmenter = GestureSegmenter()
        var saved = 0
        var deadline = Date().addingTimeInterval(perRepTimeoutSeconds)

        for await feature in features {
            if let segment = segmenter.ingest(feature) {
                try await store.save(SignExemplar(lexID: lexID, segment: segment))
                saved += 1
                onSaved(saved)
                if saved >= count { break }
                deadline = Date().addingTimeInterval(perRepTimeoutSeconds)   // reset for the next rep
            }
            if Date() > deadline {
                if saved == 0 { throw RecordingError.timedOut }
                break   // some reps saved; stop waiting for the rest
            }
        }

        let counts = (try? await store.counts()) ?? [:]
        return counts[lexID] ?? saved
    }
}
