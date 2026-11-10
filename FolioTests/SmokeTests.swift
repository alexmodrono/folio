import Testing
@testable import Folio

@Suite struct SmokeTests {
    @Test func hostAppLoads() {
        #expect(ChatGPTSession.home.host == "chatgpt.com")
    }
}
