import Foundation

/// Live Claude Code session ids with last-seen times.
public final class SessionTracker {
    private var seen: [String: TimeInterval] = [:]
    public init() {}
    public var isEmpty: Bool { seen.isEmpty }
    public var count: Int { seen.count }
    public func touch(_ id: String, now: TimeInterval) { seen[id] = now }
    public func remove(_ id: String) { seen[id] = nil }
    public func removeAll() { seen.removeAll() }

    /// Drops entries silent for longer than `staleAfter`. True if this emptied a non-empty set.
    public func sweep(now: TimeInterval, staleAfter: TimeInterval) -> Bool {
        let wasEmpty = seen.isEmpty
        seen = seen.filter { now - $0.value < staleAfter }
        if !wasEmpty && seen.isEmpty { dlog("sessions expired") }
        return !wasEmpty && seen.isEmpty
    }
}
