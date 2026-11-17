//
//  ObservationSupport.swift
//  Tweetintosh - Headless Data-driven Client
//

import Foundation
import Combine
import Observation

// Runs `perform` on the main queue whenever a property that `read` touches changes, for as long as the returned
// cancellable is kept. An @Observable object has no `objectWillChange` to subscribe to, and `withObservationTracking`
// fires only once and before the new value is stored, so this re-arms it after each change and defers `perform` until
// the value has landed. Changes that arrive together are delivered as one call.
func observeChanges(of read: @escaping () -> Void, perform: @escaping () -> Void) -> AnyCancellable {
    let loop = ObservationLoop(read: read, perform: perform)
    loop.track()
    return AnyCancellable { loop.cancel() }
}

// Only ever touched on the main queue: armed there, and re-armed from the main-queue hop each change is delivered on.
private final class ObservationLoop: @unchecked Sendable {
    private let read: () -> Void
    private let perform: () -> Void
    private var isCancelled = false

    init(read: @escaping () -> Void, perform: @escaping () -> Void) {
        self.read = read
        self.perform = perform
    }

    func track() {
        guard !isCancelled else { return }
        withObservationTracking(read) { [weak self] in
            DispatchQueue.main.async { self?.deliver() }
        }
    }

    private func deliver() {
        guard !isCancelled else { return }
        track()
        perform()
    }

    func cancel() {
        isCancelled = true
    }
}
