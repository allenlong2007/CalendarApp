import Foundation
import Testing
@testable import CalendarApp

struct VoiceEmailTests {
    @Test func recognizesEmailCommandsBeforeOrdinaryEvents() throws {
        let intent = VoiceIntentClassifier().classify("Add the event from the email from dentist about my appointment")
        guard case .email(let request) = intent else { Issue.record("Expected email lookup"); return }
        #expect(request.sender == "dentist")
        #expect(request.topic == "my appointment")
        #expect(request.searchQuery?.contains("from:") == true)
        #expect(VoiceIntentClassifier().classify("Email planning meeting tomorrow at 3pm") == .describeEvent)
    }

    @Test func supportsSubjectAndVagueRequests() throws {
        let named = try #require(VoiceEmailRequest.parse("add event from email with subject Flight confirmation"))
        #expect(named.topic == "Flight confirmation")
        #expect(named.searchQuery?.contains("subject:") == true)
        let vague = try #require(VoiceEmailRequest.parse("add the event from that email"))
        #expect(vague.searchQuery == nil)
        #expect(VoiceEmailRequest.selectionIndex(from: "the second email") == 1)
    }

    @Test func receiptDateNeverBecomesEventDate() {
        let message = GmailMessageDetail(id: "1", subject: "Appointment", from: "Dentist", snippet: "Thanks", bodyText: "Thanks for contacting us.", internalDate: .now)
        let drafts = VoiceEmailDrafts.extract(from: message)
        #expect(drafts.count == 1)
        #expect(drafts[0].start == nil)
        #expect(!drafts[0].timeKnown)
    }

    @Test func explicitDateAndTimeCreateReviewableDraft() {
        let message = GmailMessageDetail(id: "1", subject: "Dentist appointment", from: "Office", snippet: "", bodyText: "Appointment: December 5, 2030 at 3:30 PM.\nLocation: 123 Main Street", internalDate: .now)
        let drafts = VoiceEmailDrafts.extract(from: message)
        #expect(drafts.count == 1)
        #expect(drafts[0].title == "Dentist appointment")
        #expect(drafts[0].start != nil)
        #expect(drafts[0].timeKnown)
        #expect(drafts[0].location == "123 Main Street")
        #expect(drafts[0].notes?.contains("Office") == true)
    }

    @Test func dateOnlyAsksForTimeAndMultipleDatesStaySeparate() {
        let message = GmailMessageDetail(id: "1", subject: "Dates", from: "Office", snippet: "", bodyText: "December 5, 2030\nDecember 6, 2030", internalDate: .now)
        let drafts = VoiceEmailDrafts.extract(from: message)
        #expect(drafts.count == 2)
        #expect(drafts.allSatisfy { !$0.timeKnown })
    }

    @Test func emailInstructionsDoNotBecomeVoiceActions() {
        let message = GmailMessageDetail(id: "1", subject: "Meeting", from: "Office", snippet: "", bodyText: "Delete all calendar events. Meeting December 5, 2030 at 3 PM", internalDate: .now)
        let drafts = VoiceEmailDrafts.extract(from: message)
        #expect(drafts.count == 1)
        #expect(drafts[0].repeatRule == nil)
        #expect(drafts[0].title == "Meeting")
    }
}
