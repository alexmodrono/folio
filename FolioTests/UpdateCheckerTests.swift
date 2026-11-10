import Testing
@testable import Folio

@Suite struct UpdateCheckerTests {
    @Test(arguments: [
        ("1.1", "1.0", true),
        ("1.0.1", "1.0", true),
        ("2.0", "1.9.9", true),
        ("1.10", "1.9", true),
        ("1.0", "1.0", false),
        ("1.0", "1.0.0", false),
        ("0.9", "1.0", false),
        ("1.0-beta", "1.0", false),
        ("1.2.3-beta", "1.2.2", true),
    ])
    func comparesVersionsNumerically(candidate: String, current: String, newer: Bool) {
        #expect(UpdateChecker.isNewer(candidate, than: current) == newer)
    }
}
