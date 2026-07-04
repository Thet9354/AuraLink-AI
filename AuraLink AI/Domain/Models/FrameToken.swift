//
//  FrameToken.swift
//  AuraLink AI
//
//  The single audited `@unchecked Sendable` in the system.
//
//  Wraps a retained `CVPixelBuffer` from the capture pipeline so it can cross actor boundaries
//  without copying (a 1080p frame at 60 fps is a memory-bandwidth catastrophe to copy). Safety is
//  guaranteed by CONVENTION, not by the type system: a `FrameToken` has single-ownership
//  transfer-by-handoff semantics — it is moved through the `LatestSlot` / `AsyncStream` channels
//  and never aliased. CoreVideo buffers are internally safe for concurrent read; we enforce
//  single-writer by only ever reading the pixels inside the one actor that currently holds the token.
//
//  Retaining the `CVPixelBuffer` keeps it out of the capture pool until the token is released, so
//  the pool cannot recycle memory we are still reading. With a latest-value channel only one token
//  is in flight, so pool pressure stays bounded.
//

import CoreVideo
import CoreMedia

nonisolated struct FrameToken: @unchecked Sendable {
    /// The retained pixel buffer. Lock with `CVPixelBufferLockBaseAddress(.readOnly)` before
    /// reading base addresses; unlock on scope exit.
    let pixelBuffer: CVPixelBuffer
    /// Presentation timestamp from the sample buffer, on the shared capture clock.
    let pts: CMTime
    /// Monotonic capture sequence number, for ordering/diagnostics.
    let seq: UInt64
}
