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

    func record(_ entry: LexEntry) {
        guard recordingLexID == nil else { return }
        recordingLexID = entry.id
        statusText = "Sign “\(entry.english)” now — pause when done"
        lastError = nil

        let recorder = self.recorder
        Task { [weak self] in
            do {
                let newCount = try await recorder.recordOne(for: entry.id)
                self?.counts[entry.id] = newCount
                self?.statusText = "Saved “\(entry.english)” (\(newCount))"
            } catch EnrollmentRecorder.RecordingError.cameraUnavailable {
                self?.lastError = "Camera unavailable — run on a device."
                self?.statusText = nil
            } catch EnrollmentRecorder.RecordingError.timedOut {
                self?.lastError = "No sign detected — try again."
                self?.statusText = nil
            } catch {
                self?.lastError = String(describing: error)
                self?.statusText = nil
            }
            self?.recordingLexID = nil
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
