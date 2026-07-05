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
                    Section("Pose (capture → pose)") {
                        row("Frames processed", "\(report.vision.framesProcessed)")
                        row("Latency p50", String(format: "%.1f ms", report.vision.latencyP50Ms))
                        row("Latency p95", String(format: "%.1f ms", report.vision.latencyP95Ms))
                        row("Latency max", String(format: "%.1f ms", report.vision.latencyMaxMs))
                        row("Frames with hands", String(format: "%.0f%%", report.vision.detectionRate * 100))
                    }
                    Section {
                        let fpsOK = report.videoFps >= 55
                        let poseOK = report.vision.framesProcessed > 0 && report.vision.latencyP95Ms <= 40
                        Text(gateVerdict(report))
                            .font(.footnote)
                            .foregroundStyle(fpsOK && poseOK ? .green : .orange)
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
        let fpsOK = report.videoFps >= 55
        // PERF.md capture→pose gate: ≤ 25 ms p95 (A17) / ≤ 40 ms p95 (A14 floor).
        let poseOK = report.vision.framesProcessed > 0 && report.vision.latencyP95Ms <= 40
        switch (fpsOK, poseOK) {
        case (true, true): return "Gate PASS: ~60 fps capture, pose p95 within the 40 ms floor."
        case (true, false): return "Capture OK; pose p95 above 40 ms — check thermal state / lighting."
        case (false, true): return "Pose OK; below 60 fps capture — check device format / thermal state."
        case (false, false): return "Below targets — check thermal state, lighting, and device format."
        }
    }

    private typealias Report = CaptureDiagnosticsViewModel.Report
}
