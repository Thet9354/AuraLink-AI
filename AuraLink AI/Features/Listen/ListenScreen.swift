//
//  ListenScreen.swift
//  AuraLink AI
//
//  Ambient-audio mode: live speech captions, sound-event alerts, and a prosody meter that mirrors
//  the haptic intensity/sharpness the user feels on the Taptic engine.
//

import SwiftUI

struct ListenScreen: View {
    @State private var model: ListenViewModel

    init(model: ListenViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                events
                Spacer()
                caption
                Spacer()
                prosodyMeter
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Listen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var events: some View {
        if !model.recentEvents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.recentEvents) { event in
                        eventChip(event)
                    }
                }
            }
        }
    }

    private func eventChip(_ event: SoundEvent) -> some View {
        let color: Color = switch event.urgency {
        case .alert: .red
        case .warn: .orange
        case .info: .secondary
        }
        return Label(event.displayName, systemImage: icon(for: event.category))
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel("\(event.displayName), \(urgencyWord(event.urgency))")
    }

    @ViewBuilder
    private var caption: some View {
        if let caption = model.caption {
            Text(caption.plainText)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(caption.spans.first?.weight == .tentative ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .accessibilityLabel(caption.plainText)
        } else if let errorText = model.errorText {
            Text(errorText).font(.footnote).foregroundStyle(.red)
        } else {
            Text(model.isRunning ? "Listening…" : "Starting…")
                .font(.title3).foregroundStyle(.secondary)
        }
    }

    private var prosodyMeter: some View {
        let params = model.prosody?.parameters ?? .silent
        return VStack(spacing: 10) {
            meterRow("Loudness", value: params.intensity, systemImage: "speaker.wave.3", tint: .blue)
            meterRow("Pitch", value: params.sharpness, systemImage: "waveform.path", tint: .purple)
            if let f0 = model.prosody?.f0Hz, model.prosody?.voiced == true {
                Text(String(format: "%.0f Hz", f0))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    private func meterRow(_ label: String, value: Float, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).frame(width: 24)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat(value)))
                }
            }
            .frame(height: 10)
        }
    }

    private func icon(for category: SoundCategory) -> String {
        switch category {
        case .alarm, .siren: "bell.fill"
        case .vehicleHorn: "car.fill"
        case .doorbell, .knock: "door.left.hand.open"
        case .phone: "phone.fill"
        case .babyCry: "figure.and.child.holdinghands"
        case .shout: "exclamationmark.bubble.fill"
        case .glassBreak: "burst.fill"
        case .dogBark: "pawprint.fill"
        case .speech: "text.bubble.fill"
        case .applause: "hands.clap.fill"
        case .water: "drop.fill"
        case .footsteps: "figure.walk"
        case .other: "waveform"
        }
    }

    private func urgencyWord(_ urgency: SoundUrgency) -> String {
        switch urgency {
        case .alert: "alert"
        case .warn: "warning"
        case .info: "notice"
        }
    }
}
