//
//  ExemplarFileStore.swift
//  AuraLink AI
//
//  Documents-directory store for the exemplar library. One file per exemplar so a corrupt write
//  can never take down the whole library, written with complete file protection.
//
//  When an `ExemplarCryptor` is supplied (production), each exemplar's JSON is AES-GCM encrypted at
//  rest under a device-only key and written as a `.sealed` file — nothing on disk reveals which
//  signs the user recorded. Without a cryptor (tests / previews) it writes plaintext `.json`.
//

import Foundation

actor ExemplarFileStore: ExemplarStoring {

    private let directory: URL
    private let cryptor: ExemplarCryptor?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var fileExtension: String { cryptor == nil ? "json" : "sealed" }

    init(directory: URL? = nil, cryptor: ExemplarCryptor? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.directory = docs.appendingPathComponent("Exemplars", isDirectory: true)
        }
        self.cryptor = cryptor
    }

    func loadAll() throws -> [SignExemplar] {
        try ensureDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == fileExtension }
            .compactMap { url in
                guard let raw = try? Data(contentsOf: url),
                      let decoded = try? decode(raw),
                      decoded.layoutVersion == FeatureExtractor.Layout.version else {
                    return nil   // unreadable / wrong-layout files are skipped, never misinterpreted
                }
                return decoded
            }
    }

    func save(_ exemplar: SignExemplar) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(exemplar.lexID)-\(exemplar.id.uuidString).\(fileExtension)")
        let json = try encoder.encode(exemplar)
        let payload = try cryptor?.encrypt(json) ?? json
        try payload.write(to: url, options: [.atomic, .completeFileProtection])
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

    private func decode(_ raw: Data) throws -> SignExemplar {
        let json = try cryptor?.decrypt(raw) ?? raw
        return try decoder.decode(SignExemplar.self, from: json)
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
