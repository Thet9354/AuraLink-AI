//
//  SignRecallScreen.swift
//  AuraLink AI
//
//  "My signs": the user's enrolled signs, each replaying the recorded gesture as an animated
//  skeleton so they can remember which gesture maps to which word or phrase.
//

import SwiftUI

struct SignRecallScreen: View {
    @State private var model: SignRecallViewModel

    init(model: SignRecallViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.enrolled.isEmpty {
                    ContentUnavailableView("No signs yet",
                                           systemImage: "hand.raised",
                                           description: Text("Record gestures in Enroll and they'll appear here to review."))
                } else {
                    List {
                        ForEach(model.enrolled) { entry in
                            NavigationLink {
                                SignReplayView(entry: entry, frames: model.replayFrames(for: entry))
                            } label: {
                                row(entry)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My signs")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.refresh() }
        }
    }

    private func row(_ entry: LexEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.english)
                Text(entry.isCustom ? "custom phrase" : entry.gloss)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(entry.english), replay recorded gesture")
    }
}

/// Loops the recorded skeleton of one sign, fit to view in canonical (normalized) space.
struct SignReplayView: View {
    let entry: LexEntry
    let frames: [SkeletonReplayFrame]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 16) {
            Text(entry.english)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            canvas
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 20))
                .overlay(alignment: .bottom) {
                    if frames.isEmpty {
                        Text("No recording to replay").font(.footnote).foregroundStyle(.secondary).padding()
                    }
                }

            Text("Replaying your recorded gesture")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
        .task { await animate() }
    }

    private var canvas: some View {
        Canvas { context, size in
            guard !frames.isEmpty else { return }
            let frame = frames[index % frames.count]
            let bounds = ExemplarReplay.bounds(frames)
            for hand in frame.hands {
                draw(hand, in: &context, size: size, bounds: bounds)
            }
        }
        .accessibilityHidden(true)
    }

    private func animate() async {
        guard frames.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(70))
            index += 1
            if index % frames.count == 0 {
                try? await Task.sleep(for: .milliseconds(350))   // brief pause between loops
            }
        }
    }

    private func draw(_ joints: [SIMD2<Float>],
                      in context: inout GraphicsContext,
                      size: CGSize,
                      bounds: (min: SIMD2<Float>, max: SIMD2<Float>)?) {
        let pad: CGFloat = 40
        let extent = bounds.map { $0.max - $0.min } ?? SIMD2(1, 1)
        let span = CGFloat(max(extent.x, extent.y, 0.001))
        let scale = (min(size.width, size.height) - 2 * pad) / span
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let midNorm = bounds.map { ($0.min + $0.max) * 0.5 } ?? SIMD2(0, 0)

        func point(_ joint: HandJoint) -> CGPoint {
            let p = joints[joint.rawValue]
            // Center on the skeleton's midpoint; flip Y (canonical is y-up, screen is y-down).
            let dx = CGFloat(p.x - midNorm.x) * scale
            let dy = CGFloat(p.y - midNorm.y) * scale
            return CGPoint(x: center.x + dx, y: center.y - dy)
        }

        var bonePath = Path()
        for (a, b) in HandSkeleton.bones {
            bonePath.move(to: point(a))
            bonePath.addLine(to: point(b))
        }
        context.stroke(bonePath, with: .color(.orange.opacity(0.8)), lineWidth: 3)

        for joint in HandJoint.allCases {
            let p = point(joint)
            let r: CGFloat = joint == .wrist ? 7 : 4.5
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(.orange))
        }
    }
}
