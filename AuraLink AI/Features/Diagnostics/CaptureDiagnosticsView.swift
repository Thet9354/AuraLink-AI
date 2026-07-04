//
//  CaptureDiagnosticsView.swift
//  AuraLink AI
//
//  Phase 1 on-device verification UI. Runs the capture self-test and shows measured fps, dropped
//  frames, and audio samples captured.
//

import SwiftUI

struct CaptureDiagnosticsView: View {
    @State private var model: CaptureDiagnosticsViewModel

    init(model: CaptureDiagnosticsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Capture self-test") {
                    Button {
                        model.run()
                    } label: {
                        Label(model.isRunning ? "Running…" : "Run 5-second test",
                              systemImage: "waveform.and.person.filled")
                    }
                    .disabled(model.isRunning)
                }

                if let report = model.report {
                    Section("Video") {
                        row("Measured fps", String(format: "%.1f", report.videoFps))
                        row("Delivered frames", "\(report.delivered)")
                        row("Dropped frames", "\(report.dropped)")
                    }
                    Section("Audio") {
                        row("Samples captured", "\(report.audioSamples)")
                    }
                    Section {
                        Text(gateVerdict(report))
                            .font(.footnote)
                            .foregroundStyle(report.videoFps >= 55 ? .green : .orange)
                    }
                }

                if let errorText = model.errorText {
                    Section("Error") {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Section {
                        Text("The camera is unavailable in the Simulator — run this on a device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func gateVerdict(_ report: Report) -> String {
        report.videoFps >= 55
            ? "Gate PASS: sustained ~60 fps capture."
            : "Below 60 fps target — check device format / thermal state."
    }

    private typealias Report = CaptureDiagnosticsViewModel.Report
}
