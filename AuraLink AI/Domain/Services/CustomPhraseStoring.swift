//
//  CustomPhraseStoring.swift
//  AuraLink AI
//
//  Persistence seam for user-created phrases. Like exemplars, phrases are personal data and are
//  encrypted at rest by the concrete store.
//

nonisolated protocol CustomPhraseStoring: Sendable {
    func loadAll() async throws -> [CustomPhrase]
    func save(_ phrase: CustomPhrase) async throws
    func remove(id: String) async throws
}
