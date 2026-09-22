import SwiftUI

/// Full-screen prompt shown until Calendar access is granted. EventKit only
/// shows its own system dialog once -- if the user has already denied, we
/// can't re-prompt, so this deep-links to Settings instead.
struct EventKitAccessGateView: View {
    @Environment(EventStoreManager.self) private var eventStore

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.ultramarine)
            Text("Calendar Access Needed")
                .font(.title2.weight(.semibold))
            Text("This app reads and creates events in your iCloud Calendar so everything shows up here and in Apple's own Calendar app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            if eventStore.accessStatus == .denied {
                Button("Open Settings") {
                    openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
            } else {
                Button("Allow Calendar Access") {
                    Task { await eventStore.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.ultramarine)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// UIApplication.openSettingsURLString is an iOS-only deep link (it has
    /// no registered handler on macOS, so opening it there silently does
    /// nothing) -- Mac Catalyst needs System Settings' own URL scheme instead.
    private func openSystemSettings() {
        #if targetEnvironment(macCatalyst)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            UIApplication.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
