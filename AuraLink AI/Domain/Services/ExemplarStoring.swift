//
//  ExemplarStoring.swift
//  AuraLink AI
//
//  Persistence seam for the exemplar library. The pipeline and the enrollment UI depend on this
//  protocol; the concrete store is a documents-directory file store (Secure-Enclave encryption of
//  the library lands with Phase 5 personalization).
//

nonisolated protocol ExemplarStoring: Sendable {
    /// All exemplars whose layout version matches the current feature layout.
    func loadAll() async throws -> [SignExemplar]

    /// Persist a newly recorded exemplar.
    func save(_ exemplar: SignExemplar) async throws

    /// Exemplar counts keyed by lex id (drives the enrollment UI).
    func counts() async throws -> [String: Int]

    /// Remove all exemplars for a sign (re-recording flow).
    func removeAll(for lexID: String) async throws
}
