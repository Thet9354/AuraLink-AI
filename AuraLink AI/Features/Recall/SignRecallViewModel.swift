//
//  SignRecallViewModel.swift
//  AuraLink AI
//
//  Lists only the signs the user has actually enrolled (not the whole catalog) and provides the
//  recorded skeleton for each so they can replay "which gesture did I use for this?".
//

import Foundation
import Observation

@MainActor
@Observable
final class SignRecallViewModel {

    private(set) var enrolled: [LexEntry] = []

    private let catalog: SignLexicon
    private let store: any ExemplarStoring
    private let phraseStore: any CustomPhraseStoring
    private var exemplarsByLex: [String: [SignExemplar]] = [:]

    init(catalog: SignLexicon, store: any ExemplarStoring, phraseStore: any CustomPhraseStoring) {
        self.catalog = catalog
        self.store = store
        self.phraseStore = phraseStore
    }

    func refresh() async {
        let all = (try? await store.loadAll()) ?? []
        var byLex: [String: [SignExemplar]] = [:]
        for exemplar in all {
            byLex[exemplar.lexID, default: []].append(exemplar)
        }
        exemplarsByLex = byLex

        let custom = ((try? await phraseStore.loadAll()) ?? []).map(\.asLexEntry)
        let merged = SignLexicon(entries: catalog.entries + custom)
        enrolled = byLex.keys
            .compactMap { merged[$0] }
            .sorted { $0.english.localizedCaseInsensitiveCompare($1.english) == .orderedAscending }
    }

    func count(for entry: LexEntry) -> Int { exemplarsByLex[entry.id]?.count ?? 0 }

    /// Skeleton frames of the most recent recording for this sign.
    func replayFrames(for entry: LexEntry) -> [SkeletonReplayFrame] {
        guard let latest = exemplarsByLex[entry.id]?.max(by: { $0.recordedAt < $1.recordedAt }) else {
            return []
        }
        return ExemplarReplay.frames(from: latest)
    }
}
