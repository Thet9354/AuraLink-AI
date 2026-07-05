//
//  EnrollView.swift
//  AuraLink AI
//
//  Enrollment: create your own phrases (bind any text to a gesture) and record examples for them
//  or the built-in catalog. Recording uses the front camera and the same segmentation as translation.
//

import SwiftUI

struct EnrollView: View {
    @State private var model: EnrollViewModel
    @State private var showingNewPhrase = false
    @State private var newTitle = ""
    @State private var newText = ""
    @State private var query = ""

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

                Section {
                    Button {
                        newTitle = ""; newText = ""; showingNewPhrase = true
                    } label: {
                        Label("New phrase", systemImage: "plus.bubble")
                    }
                    .disabled(model.recordingLexID != nil)
                } footer: {
                    Text("Bind any word or sentence to a gesture — it's spoken aloud when recognized.")
                }

                ForEach(model.matchingCategories(query), id: \.self) { category in
                    Section(sectionTitle(category)) {
                        ForEach(model.entries(in: category, matching: query)) { entry in
                            row(entry, isCustom: category == .custom)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search signs")
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
                    Text("\(model.readyCount)/\(model.totalCount) ready")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .alert("New phrase", isPresented: $showingNewPhrase) {
                TextField("Text to speak (e.g. I need help)", text: $newText)
                TextField("Short label (optional)", text: $newTitle)
                Button("Create") { model.createPhrase(title: newTitle, text: newText) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll record a gesture for this next.")
            }
            .task { await model.refresh() }
        }
    }

    private func sectionTitle(_ category: LexEntry.Category) -> String {
        category == .custom ? "My phrases" : category.rawValue.capitalized
    }

    private func row(_ entry: LexEntry, isCustom: Bool) -> some View {
        let count = model.count(for: entry.id)
        let isRecording = model.recordingLexID == entry.id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.english)
                Text(isCustom ? "custom" : entry.gloss)
                    .font(.caption2).foregroundStyle(.secondary)
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
            if isCustom {
                Button("Delete", role: .destructive) { model.deletePhrase(entry) }
            } else if count > 0 {
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
