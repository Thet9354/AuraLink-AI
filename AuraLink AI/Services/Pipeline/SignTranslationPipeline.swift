//
//  SignTranslationPipeline.swift
//  AuraLink AI
//
//  The real translation graph behind the `CaptionProducing` seam:
//
//    capture frames → VisionActor (pose → features) → GestureSegmenter → SignMatcher (DTW)
//      → GlossGrammar → CaptionDTO → LatestSlot → @MainActor view model
//
//  Admission control note: DTW fires only on segment CLOSE (≤ ~2/s by construction — segments
//  are bounded by human signing cadence) and costs single-digit milliseconds after pruning, so
//  the serial actor itself is the admission gate; a separate coordinator would be machinery
//  without a queue to manage. Revisit if a learned encoder replaces DTW.
//

import Foundation
import CoreMedia
import os

actor SignTranslationPipeline: CaptionProducing {

    nonisolated let output = LatestSlot<CaptionDTO>()

    private let capture: CaptureActor
    private let vision: VisionActor
    private let catalog: SignLexicon
    private let store: any ExemplarStoring
    private let phraseStore: any CustomPhraseStoring
    private let tier: CapabilityTier

    private var segmenter = GestureSegmenter()
    private var matcher: SignMatcher?
    private var lexicon: SignLexicon
    private var loop: Task<Void, Never>?
    private var isRunning = false

    /// Rolling sentence window: recognized (or unknown) segments assemble into a live caption.
    private var sentence: [GlossGrammar.Item] = []
    private var lastSegmentEnd: Double = 0
    private var previousLexID: String?
    // Consecutive-repeat suppression: the same sign held/re-held within this gap is ignored so a
    // single hold doesn't caption (or speak) twice.
    private var lastMatchLexID: String?
    private var lastMatchEnd: Double = 0
    private let repeatGapSeconds: Double = 1.5

    /// A silence gap longer than this starts a new sentence.
    private let sentenceGapSeconds: Double = 2.5
    /// Sentence window bound — captions stay readable, memory stays fixed.
    private let maxSentenceItems = 12

    init(capture: CaptureActor,
         vision: VisionActor,
         lexicon: SignLexicon,
         store: any ExemplarStoring,
         phraseStore: any CustomPhraseStoring,
         tier: CapabilityTier) {
        self.capture = capture
        self.vision = vision
        self.catalog = lexicon
        self.lexicon = lexicon
        self.store = store
        self.phraseStore = phraseStore
        self.tier = tier
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true

        // Reload each session — enrollment may have added signs and custom phrases since.
        let customEntries = ((try? await phraseStore.loadAll()) ?? []).map(\.asLexEntry)
        lexicon = SignLexicon(entries: catalog.entries + customEntries)
        let exemplars = (try? await store.loadAll()) ?? []
        matcher = SignMatcher(lexicon: lexicon,
                              exemplars: exemplars.map(SignMatcher.PreparedExemplar.init))

        await vision.attach(to: capture.frames)
        let features = await vision.subscribeFeatures()

        segmenter.reset()
        sentence.removeAll()
        previousLexID = nil
        lastMatchLexID = nil
        lastMatchEnd = 0

        loop = Task {
            for await feature in features {
                await self.ingest(feature)
            }
        }

        do {
            try await capture.start()
        } catch {
            // Camera unavailable (denied, or simulator): surface an honest system caption.
            let dto = CaptionDTO(spans: [StyledSpan(text: "Camera unavailable", weight: .tentative)],
                                 band: .low, latencyMs: 0, source: .sign, timestamp: .now)
            await output.put(dto)
        }
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        loop?.cancel()   // terminates our private feature stream; VisionActor prunes the subscriber
        loop = nil
        segmenter.reset()
        await capture.stop()
    }

    // MARK: - Segment → caption

    private func ingest(_ feature: FeatureVector) async {
        guard let segment = segmenter.ingest(feature) else { return }
        guard let matcher else { return }

        let interval = Signposts.latency.beginInterval("segmentToCaption")
        defer { Signposts.latency.endInterval("segmentToCaption", interval) }

        // New sentence after a long silence.
        if lastSegmentEnd > 0, segment.startSeconds - lastSegmentEnd > sentenceGapSeconds {
            sentence.removeAll()
            previousLexID = nil
            lastMatchLexID = nil
        }
        lastSegmentEnd = segment.endSeconds

        var spokenText: String?
        switch matcher.match(segment, previousLexID: previousLexID) {
        case .matched(let best, _):
            // Suppress an immediate repeat of the same sign — one hold must not fire twice.
            if best.entry.id == lastMatchLexID, segment.endSeconds - lastMatchEnd < repeatGapSeconds {
                return
            }
            lastMatchLexID = best.entry.id
            lastMatchEnd = segment.endSeconds
            sentence.append(GlossGrammar.Item(entry: best.entry, confidence: best.confidence))
            previousLexID = best.entry.id
            spokenText = best.entry.english   // spoken aloud by the view model

        case .unknown:
            // Motion that matched nothing in the vocabulary: an explicit, honest gap.
            sentence.append(GlossGrammar.Item(entry: nil, confidence: 0))
            previousLexID = nil
            lastMatchLexID = nil

        case .noExemplars:
            let dto = CaptionDTO(spans: [StyledSpan(text: "No signs enrolled yet — record in Enroll",
                                                    weight: .tentative)],
                                 band: .low, latencyMs: 0, source: .sign, timestamp: .now)
            await output.put(dto)
            return
        }

        if sentence.count > maxSentenceItems {
            sentence.removeFirst(sentence.count - maxSentenceItems)
        }

        let (spans, band) = GlossGrammar.render(sentence)
        // Glass-to-caption latency: emission time minus the segment's last frame, on the shared
        // host/capture clock.
        let nowSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let latencyMs = max(0, Int((nowSeconds - segment.endSeconds) * 1000))

        let dto = CaptionDTO(spans: spans,
                             band: band,
                             latencyMs: latencyMs,
                             source: .sign,
                             timestamp: .now,
                             utterance: spokenText)
        await output.put(dto)
    }
}
