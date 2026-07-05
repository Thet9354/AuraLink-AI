//
//  ExemplarFileStore.swift
//  AuraLink AI
//
//  Documents-directory JSON store for the exemplar library. One file per exemplar
//  (Exemplars/<lexID>-<uuid>.json) so a corrupt write can never take down the whole library.
//  Files are written with complete file protection. Phase 5 adds Secure-Enclave key wrapping.
//

import Foundation

actor ExemplarFileStore: ExemplarStoring {

    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = docs.appendingPathComponent("Exemplars", isDirectory: true)
        }
    }

    func loadAll() throws -> [SignExemplar] {
        try ensureDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let exemplar = try? decoder.decode(SignExemplar.self, from: data) else {
                    return nil   // skip unreadable files; never fail the whole library
                }
                // A layout-version mismatch must be skipped, not misinterpreted.
                return exemplar.layoutVersion == FeatureExtractor.Layout.version ? exemplar : nil
            }
    }

    func save(_ exemplar: SignExemplar) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(exemplar.lexID)-\(exemplar.id.uuidString).json")
        let data = try encoder.encode(exemplar)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func counts() throws -> [String: Int] {
        try loadAll().reduce(into: [:]) { counts, exemplar in
            counts[exemplar.lexID, default: 0] += 1
        }
    }

    func removeAll(for lexID: String) throws {
        try ensureDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        for url in files where url.lastPathComponent.hasPrefix("\(lexID)-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
