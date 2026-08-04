import Foundation

/// Drives "passeio automático": every `intervalNanos`, advances the tour one
/// scene (looping) so a listing can present itself hands-free. The view-model
/// owns one and supplies the advance closure; it re-arms after each scene lands
/// (loop) and stops when toggled off or the view detaches.
///
/// `@MainActor` so the timer closure hops back to the main actor before calling
/// `advance` — no manual `MainActor.run`, and the sleep is a suspension (the UI
/// never stalls).
@MainActor
public final class AutoPlayCoordinator {

    private let advance: () -> Void
    private var task: Task<Void, Never>?
    public private(set) var isActive: Bool = false
    /// Per-scene dwell time. 4 s is long enough to look around, short enough to
    /// keep a multi-room tour moving.
    public var intervalNanos: UInt64 = 4_000_000_000

    public init(advance: @escaping () -> Void) {
        self.advance = advance
    }

    /// Starts (or stops) the loop. Idempotent.
    public func setActive(_ on: Bool) {
        if on {
            isActive = true
            schedule()
        } else {
            isActive = false
            task?.cancel()
            task = nil
        }
    }

    /// Re-arms the timer after a scene has landed so the loop continues.
    public func reschedule() {
        guard isActive else { return }
        schedule()
    }

    private func schedule() {
        task?.cancel()
        task = Task { [intervalNanos, advance] in
            try? await Task.sleep(nanoseconds: intervalNanos)
            guard !Task.isCancelled else { return }
            advance()
        }
    }
}
