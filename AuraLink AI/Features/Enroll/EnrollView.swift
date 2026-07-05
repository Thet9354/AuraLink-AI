//
//  EnrollView.swift
//  AuraLink AI
//
//  Catalog of the ~200-sign vocabulary with per-sign exemplar counts and a record button.
//  Recording uses the front camera and the same segmentation as translation.
//

import SwiftUI

struct EnrollView: View {
    @State private var model: EnrollViewModel

    init(model: EnrollViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                if let statusText = model.statusText {
                    Section {
                        Label(statusText, systemImage: model.recordingLexID != nil ? "record.circle" : "checkmark.circle")
                            .foregroundStyle(model.recordingLexID != nil ? .red : .green)
                    }
                }
                if let lastError = model.lastError {
                    Section {
                        Text(lastError).font(.footnote).foregroundStyle(.red)
                    }
                }

                ForEach(model.categories, id: \.self) { category in
                    Section(category.rawValue.capitalized) {
                        ForEach(model.entries(in: category)) { entry in
                            row(entry)
                        }
                    }
                }
            }
            .navigationTitle("Enroll signs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Clear all signs", role: .destructive) { model.clearAll() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(model.recordingLexID != nil)
                    .accessibilityLabel("Enrollment options")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(model.readyCount)/\(model.lexicon.count) ready")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .task { await model.refresh() }
        }
    }

    private func row(_ entry: LexEntry) -> some View {
        let count = model.count(for: entry.id)
        let isRecording = model.recordingLexID == entry.id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.english)
                Text(entry.gloss).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            countBadge(count)
            Button {
                model.record(entry)
            } label: {
                Image(systemName: isRecording ? "record.circle.fill" : "plus.circle")
                    .foregroundStyle(isRecording ? .red : .accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(model.recordingLexID != nil)
        }
        .swipeActions {
            if count > 0 {
                Button("Clear", role: .destructive) { model.clear(entry) }
            }
        }
    }

    private func countBadge(_ count: Int) -> some View {
        let ready = count >= EnrollViewModel.targetPerSign
        return Text("\(count)/\(EnrollViewModel.targetPerSign)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(ready ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(ready ? Color.green.opacity(0.15) : Color(.tertiarySystemFill), in: Capsule())
    }
}
