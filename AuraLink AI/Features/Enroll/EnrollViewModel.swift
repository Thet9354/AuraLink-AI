//
//  EnrollViewModel.swift
//  AuraLink AI
//
//  Drives sign enrollment: lists the catalog with per-sign exemplar counts and records new
//  exemplars on demand. A sign needs a few exemplars before the matcher can recognize it.
//

import Foundation
import Observation

@MainActor
@Observable
final class EnrollViewModel {

    /// Recommended exemplars per sign before it is considered "ready".
    static let targetPerSign = 3

    private(set) var counts: [String: Int] = [:]
    private(set) var customPhrases: [CustomPhrase] = []
    private(set) var recordingLexID: String?
    private(set) var statusText: String?
    private(set) var lastError: String?

    let lexicon: SignLexicon
    private let recorder: EnrollmentRecorder
    private let store: any ExemplarStoring
    private let phraseStore: any CustomPhraseStoring

    init(lexicon: SignLexicon,
         recorder: EnrollmentRecorder,
         store: any ExemplarStoring,
         phraseStore: any CustomPhraseStoring) {
        self.lexicon = lexicon
        self.recorder = recorder
        self.store = store
        self.phraseStore = phraseStore
    }

    /// Custom phrases first, then the catalog categories that have entries.
    var categories: [LexEntry.Category] {
        LexEntry.Category.allCases.filter { $0 == .custom ? !customPhrases.isEmpty
                                                          : !lexicon.entries(in: $0).isEmpty }
    }

    func entries(in category: LexEntry.Category) -> [LexEntry] {
        category == .custom ? customPhrases.map(\.asLexEntry) : lexicon.entries(in: category)
    }

    func count(for lexID: String) -> Int { counts[lexID] ?? 0 }

    var readyCount: Int {
        let all = lexicon.entries + customPhrases.map(\.asLexEntry)
        return all.filter { count(for: $0.id) >= Self.targetPerSign }.count
    }

    var totalCount: Int { lexicon.count + customPhrases.count }

    func refresh() async {
        counts = (try? await store.counts()) ?? [:]
        customPhrases = (try? await phraseStore.loadAll()) ?? []
    }

    func createPhrase(title: String, text: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let phrase = CustomPhrase(title: trimmedTitle.isEmpty ? trimmedText : trimmedTitle,
                                  text: trimmedText)
        let phraseStore = self.phraseStore
        Task { [weak self] in
            try? await phraseStore.save(phrase)
            self?.customPhrases.append(phrase)
        }
    }

    func deletePhrase(_ entry: LexEntry) {
        let phraseStore = self.phraseStore
        let store = self.store
        Task { [weak self] in
            try? await phraseStore.remove(id: entry.id)
            try? await store.removeAll(for: entry.id)   // and its recorded exemplars
            self?.customPhrases.removeAll { $0.id == entry.id }
            self?.counts[entry.id] = nil
        }
    }

    /// Records enough reps to reach the per-sign target (or one more if already full), with a
    /// countdown and live "N of M" auto-advance. The user holds the sign, moves, holds again.
    func record(_ entry: LexEntry) {
        guard recordingLexID == nil else { return }
        let already = count(for: entry.id)
        let reps = already >= Self.targetPerSign ? 1 : Self.targetPerSign - already

        recordingLexID = entry.id
        lastError = nil

        let recorder = self.recorder
        Task { [weak self] in
            guard let self else { return }
            for countdown in [3, 2, 1] {
                self.statusText = "Get ready to sign “\(entry.english)”… \(countdown)"
                try? await Task.sleep(for: .seconds(1))
            }
            self.statusText = "Hold the sign — recording \(reps)…"

            do {
                let final = try await recorder.recordSession(for: entry.id, count: reps) { saved in
                    Task { @MainActor [weak self] in
                        self?.counts[entry.id] = already + saved
                        self?.statusText = "Recorded \(already + saved) of \(Self.targetPerSign) — hold again"
                    }
                }
                self.counts[entry.id] = final
                self.statusText = "Saved “\(entry.english)” (\(final))"
            } catch EnrollmentRecorder.RecordingError.cameraUnavailable {
                self.lastError = "Camera unavailable — run on a device."
                self.statusText = nil
            } catch EnrollmentRecorder.RecordingError.timedOut {
                self.lastError = "No sign detected — try again."
                self.statusText = nil
            } catch {
                self.lastError = String(describing: error)
                self.statusText = nil
            }
            self.recordingLexID = nil
        }
    }

    // MARK: - Search

    func matchingCategories(_ query: String) -> [LexEntry.Category] {
        categories.filter { !entries(in: $0, matching: query).isEmpty }
    }

    func entries(in category: LexEntry.Category, matching query: String) -> [LexEntry] {
        let base = entries(in: category)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.english.localizedCaseInsensitiveContains(q) || $0.gloss.localizedCaseInsensitiveContains(q)
        }
    }

    func clear(_ entry: LexEntry) {
        let store = self.store
        Task { [weak self] in
            try? await store.removeAll(for: entry.id)
            self?.counts[entry.id] = 0
        }
    }

    func clearAll() {
        let store = self.store
        Task { [weak self] in
            try? await store.removeEverything()
            self?.counts = [:]
        }
    }
}
