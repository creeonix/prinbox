/// Counts hook calls in main-actor tests.
@MainActor
final class Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
