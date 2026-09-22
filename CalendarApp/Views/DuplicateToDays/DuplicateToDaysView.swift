import SwiftUI

/// Lets the user pick one or more other days to duplicate an existing event
/// onto (same time-of-day and duration, shifted to each picked date).
struct DuplicateToDaysView: View {
    let onConfirm: (Set<DateComponents>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDates: Set<DateComponents> = []

    var body: some View {
        NavigationStack {
            MultiDatePicker("Duplicate to", selection: $selectedDates)
                .navigationTitle("Duplicate to Other Days")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Duplicate") {
                            onConfirm(selectedDates)
                            dismiss()
                        }
                        .disabled(selectedDates.isEmpty)
                    }
                }
        }
    }
}
