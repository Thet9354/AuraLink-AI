//
//  DispatchQueueExecutor.swift
//  AuraLink AI
//
//  A custom `SerialExecutor` backing an actor with a dedicated `DispatchQueue`. The `CaptureActor`
//  uses this so its isolated code (session configuration and the blocking `startRunning()` /
//  `stopRunning()` calls) runs on a dedicated `userInteractive` queue rather than borrowing a
//  Swift cooperative-pool thread — those blocking AVFoundation calls must not starve the shared pool.
//

import Dispatch

nonisolated final class DispatchQueueExecutor: SerialExecutor {
    private let queue: DispatchQueue

    init(label: String, qos: DispatchQoS) {
        queue = DispatchQueue(label: label, qos: qos)
    }

    func enqueue(_ job: consuming ExecutorJob) {
        // A `consuming ExecutorJob` is non-copyable and cannot be captured by an escaping closure,
        // so convert to `UnownedJob` for the deferred hop onto our queue.
        let unowned = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async {
            unowned.runSynchronously(on: executor)
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
