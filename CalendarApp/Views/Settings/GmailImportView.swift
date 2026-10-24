import EventKit
import SwiftUI
import UIKit

struct GmailImportView: View {
    @Environment(EventStoreManager.self) private var eventStore
    @Environment(\.dismiss) private var dismiss

    @State private var oauth = GoogleOAuthService.shared
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
                    VStack(spacing: 0) {
                        accountsView
                        resultsView
                    }
                }
            }
            .navigationTitle("Import from Gmail")
            .background(GmailSignInAnchor { oauth.presentationWindow = $0 })
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
            .onChange(of: oauth.accounts) { _, _ in
                candidates = []
                selectedIDs = []
            }
            .onDisappear { oauth.cancelSignIn() }
        }
    }

    private var accountsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(oauth.accounts, id: \.self) { account in
                HStack {
                    Text(account).font(.subheadline).lineLimit(1)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        do { try oauth.signOut(account: account) }
                        catch { errorMessage = error.localizedDescription }
                        candidates = []
                        selectedIDs = []
                    }.font(.caption).disabled(isLoading)
                }
            }
            Button("Add Gmail Account") { Task { await signIn() } }
                .disabled(isLoading)
            Text("Voice searches all connected inboxes. Each account needs its own Google consent.")
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }.padding()
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
                .disabled(isLoading)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
                if isLoading {
                    ProgressView("Waiting for Google sign-in…")
                    Button("Cancel Sign-In") { oauth.cancelSignIn() }
                }
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
                                    Text(candidate.from).font(.caption).foregroundStyle(.secondary)
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
        isLoading = true
        defer { isLoading = false }
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
        let scannedAccounts = oauth.accounts
        var found: [GmailEventCandidate] = []
        var failed: [String] = []
        for account in scannedAccounts {
            do {
                let token = try await oauth.validAccessToken(account: account)
                let matches = try await GmailEventExtractor.extractCandidates(accessToken: token)
                found.append(contentsOf: matches.map { candidate in
                    GmailEventCandidate(id: account + ":" + candidate.id, subject: candidate.subject,
                        from: candidate.from + " · Inbox: " + account, detectedDate: candidate.detectedDate,
                        sourceSnippet: candidate.sourceSnippet)
                })
            } catch { failed.append(account) }
        }
        guard oauth.accounts == scannedAccounts else { return }
        candidates = found
        selectedIDs = Set(found.filter { $0.detectedDate != nil }.map(\.id))
        if !failed.isEmpty { errorMessage = "Reconnect: \(failed.joined(separator: ", "))" }
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

/// Catalyst sheets can have a different native window from the calendar.
/// Present authentication from the window containing the Connect button.
private struct GmailSignInAnchor: UIViewRepresentable {
    let resolve: (UIWindow) -> Void
    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.resolve = resolve
        return view
    }
    func updateUIView(_ uiView: AnchorView, context: Context) { uiView.resolve = resolve }
    final class AnchorView: UIView {
        var resolve: ((UIWindow) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { resolve?(window) }
        }
    }
}
