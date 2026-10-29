import Foundation
import Testing
@testable import CalendarApp

struct CalendarBridgeRequestTests {
    @Test func requiresExplicitDatesAndStableHandoffID() throws {
        let data = Data(#"{"action":"create","title":"Meeting","start":"2026-11-06T15:00:00-08:00","end":"2026-11-06T15:30:00-08:00","requestID":"E207112F-58B3-4603-853A-193D933F3573","important":true}"#.utf8)
        let request = try JSONDecoder().decode(CalendarBridgeRequest.self, from: data)
        try request.validate()
        #expect(request.important == true)
        #expect(request.startDate != nil)
    }

    @Test(arguments: [
        #"{"action":"create","title":"Meeting","start":"Friday","end":"later"}"#,
        #"{"action":"create","title":" ","start":"2026-11-06T15:00:00-08:00","end":"2026-11-06T15:30:00-08:00"}"#,
        #"{"action":"delete"}"#,
        #"{"action":"events","start":"2026-11-07T00:00:00Z","end":"2026-11-06T00:00:00Z"}"#
    ])
    func rejectsAmbiguousOrIncompleteRequests(json: String) throws {
        let request = try JSONDecoder().decode(CalendarBridgeRequest.self, from: Data(json.utf8))
        #expect(throws: (any Error).self) { try request.validate() }
    }
}
