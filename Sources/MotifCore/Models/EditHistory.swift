import Foundation

/// Small bounded undo/redo stack for editor state. Snapshots the whole
/// parameter value — parameter structs are small so this is cheap.
///
/// Discrete edits go through `push(_:)`. Continuous gestures (drag, slider
/// scrub) should call `beginStroke()`, `updateInPlace(_:)` repeatedly, then
/// `endStroke()` so the whole gesture becomes a single undo step.
public struct EditHistory<T: Equatable & Sendable>: Sendable {
    public private(set) var current: T
    private var past: [T] = []
    private var future: [T] = []
    private var strokeBase: T?
    public let limit: Int

    public init(_ initial: T, limit: Int = 200) {
        self.current = initial
        self.limit = limit
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Records a new state. No-ops when the state is unchanged, so callers can
    /// push on every commit without exploding the stack.
    public mutating func push(_ newValue: T) {
        guard newValue != current else { return }
        past.append(current)
        trimIfNeeded()
        current = newValue
        future.removeAll()
    }

    public mutating func beginStroke() {
        if strokeBase == nil { strokeBase = current }
    }

    /// Mutates the current state without recording history (gesture in-flight).
    public mutating func updateInPlace(_ newValue: T) {
        current = newValue
    }

    /// Ends a stroke, recording the pre-gesture state as one undo step.
    public mutating func endStroke() {
        defer { strokeBase = nil }
        guard let base = strokeBase, base != current else { return }
        past.append(base)
        trimIfNeeded()
        future.removeAll()
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = past.popLast() else { return false }
        future.append(current)
        current = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append(current)
        current = next
        return true
    }

    /// Records current state then replaces it (used by "Reset changes").
    public mutating func reset(to value: T) {
        push(value)
    }

    private mutating func trimIfNeeded() {
        if past.count > limit { past.removeFirst(past.count - limit) }
    }
}
