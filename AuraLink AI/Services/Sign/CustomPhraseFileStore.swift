//
//  CustomPhraseFileStore.swift
//  AuraLink AI
//
//  One-file-per-phrase store in the documents directory, AES-GCM encrypted at rest when a cryptor
//  is supplied (mirrors ExemplarFileStore). Nothing on disk reveals a user's personal phrases.
//

import Foundation

actor CustomPhraseFileStore: CustomPhraseStoring {

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
            self.directory = docs.appendingPathComponent("Phrases", isDirectory: true)
        }
        self.cryptor = cryptor
    }

    func loadAll() throws -> [CustomPhrase] {
        try ensureDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == fileExtension }
            .compactMap { url -> CustomPhrase? in
                guard let raw = try? Data(contentsOf: url),
                      let json = try? (cryptor?.decrypt(raw) ?? raw),
                      let phrase = try? decoder.decode(CustomPhrase.self, from: json) else {
                    return nil
                }
                return phrase
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ phrase: CustomPhrase) throws {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(phrase.id).\(fileExtension)")
        let json = try encoder.encode(phrase)
        let payload = try cryptor?.encrypt(json) ?? json
        try payload.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func remove(id: String) throws {
        try ensureDirectory()
        for ext in ["json", "sealed"] {
            let url = directory.appendingPathComponent("\(id).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
