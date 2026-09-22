import EventKit
import SwiftUI

struct GmailImportView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.dismiss) private var dismiss

    @State private var oauth = GoogleOAuthService()
    @State private var isLoading = false
    @State private var candidates: [GmailEventCandidate] = []
    @State private var selectedIDs: Set<String> = []
    @State private var selectedCalendarIdentifier: String?
    @State private var errorMessage: String?

    private var writableCalendars: [EKCalendar] {
        eventStore.calendars.filter(\.allowsContentModifications)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !GoogleOAuthConfig.isConfigured {
                    notConfiguredView
                } else if !oauth.isSignedIn {
                    signInView
                } else {
                    resultsView
                }
            }
            .navigationTitle("Import from Gmail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if selectedCalendarIdentifier == nil {
                    selectedCalendarIdentifier = eventStore.store.defaultCalendarForNewEvents?.calendarIdentifier
                        ?? writableCalendars.first?.calendarIdentifier
                }
            }
        }
    }

    private var notConfiguredView: some View {
        ContentUnavailableView {
            Label("Gmail Import Isn't Set Up Yet", systemImage: "envelope.badge")
        } description: {
            Text("Add a Google OAuth client ID in GoogleOAuthConfig.swift to enable this — create one in Google Cloud Console under APIs & Services > Credentials, as an \"iOS\" app OAuth client using this app's bundle identifier.")
        }
    }

    private var signInView: some View {
        ContentUnavailableView {
            Label("Connect Gmail", systemImage: "envelope")
        } description: {
            Text("Scans recent email for reservations, confirmations, and invitations you can add as events. Nothing is added without your review.")
        } actions: {
            VStack(spacing: 8) {
                Button("Connect Gmail") {
                    Task { await signIn() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private var resultsView: some View {
        if isLoading {
            ProgressView("Scanning…")
        } else if candidates.isEmpty {
            ContentUnavailableView {
                Label("Scan Your Inbox", systemImage: "magnifyingglass")
            } actions: {
                VStack(spacing: 8) {
                    Button("Scan for Events") { Task { await scan() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.ultramarine)
                    Button("Disconnect Gmail", role: .destructive) { oauth.signOut() }
                        .font(.caption)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        } else {
            List {
                Section("Add to Calendar") {
                    Picker("Calendar", selection: $selectedCalendarIdentifier) {
                        ForEach(writableCalendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(Optional(calendar.calendarIdentifier))
                        }
                    }
                }
                Section("Found in Gmail") {
                    ForEach(candidates) { candidate in
                        Button {
                            toggle(candidate.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(candidate.id) ? AppTheme.ultramarine : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.subject)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if let date = candidate.detectedDate {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No date detected")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Add \(selectedIDs.count) Event\(selectedIDs.count == 1 ? "" : "s")") {
                    addSelected()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
                .disabled(selectedIDs.isEmpty || selectedCalendarIdentifier == nil)
                .padding()
            }
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func signIn() async {
        errorMessage = nil
        do {
            try await oauth.signIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scan() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await oauth.validAccessToken()
            let found = try await GmailEventExtractor.extractCandidates(accessToken: token)
            candidates = found
            selectedIDs = Set(found.filter { $0.detectedDate != nil }.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSelected() {
        guard let calendar = writableCalendars.first(where: { $0.calendarIdentifier == selectedCalendarIdentifier }) else { return }
        for candidate in candidates where selectedIDs.contains(candidate.id) {
            guard let date = candidate.detectedDate else { continue }
            _ = try? eventStore.createEvent(
                title: candidate.subject,
                startDate: date,
                endDate: date.addingTimeInterval(3600),
                isAllDay: false,
                calendar: calendar,
                notes: "Imported from Gmail: \(candidate.from)\n\n\(candidate.sourceSnippet)"
            )
        }
        dismiss()
    }
}
