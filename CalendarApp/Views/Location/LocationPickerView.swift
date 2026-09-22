import MapKit
import SwiftData
import SwiftUI

struct LocationPickerView: View {
    /// Called with (displayTitle, structuredLocation) -- nil coordinate means
    /// the plain-text fallback (no geocoded match) was kept as typed.
    let onSelect: (String, PickedLocation?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedAddress.label) private var savedAddresses: [SavedAddress]

    @State private var searchService = LocationSearchService()
    @State private var manualText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search for a place or address", text: $manualText)
                        .onChange(of: manualText) { _, newValue in
                            searchService.queryFragment = newValue
                        }
                        .onSubmit {
                            guard !manualText.isEmpty else { return }
                            onSelect(manualText, nil)
                            dismiss()
                        }
                }

                if !searchService.results.isEmpty {
                    Section("Results") {
                        ForEach(searchService.results, id: \.self) { completion in
                            Button {
                                choose(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .foregroundStyle(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    saveAsAddress(completion)
                                } label: {
                                    Label("Save", systemImage: "bookmark.fill")
                                }
                                .tint(AppTheme.ultramarine)
                            }
                        }
                    }
                }

                if !savedAddresses.isEmpty {
                    Section("Saved Addresses") {
                        ForEach(savedAddresses, id: \.id) { address in
                            Button {
                                let payload = PickedLocation(
                                    title: address.label,
                                    latitude: address.latitude,
                                    longitude: address.longitude
                                )
                                onSelect(address.label, payload)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(address.label).foregroundStyle(.primary)
                                    Text(address.addressLine)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { modelContext.delete(savedAddresses[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveAsAddress(_ completion: MKLocalSearchCompletion) {
        Task {
            guard let resolved = await searchService.resolve(completion) else { return }
            let address = SavedAddress(
                label: resolved.title,
                addressLine: resolved.subtitle.isEmpty ? resolved.title : resolved.subtitle,
                latitude: resolved.coordinate.latitude,
                longitude: resolved.coordinate.longitude
            )
            modelContext.insert(address)
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) {
        Task {
            guard let resolved = await searchService.resolve(completion) else {
                onSelect(completion.title, nil)
                dismiss()
                return
            }
            let payload = PickedLocation(
                title: resolved.title,
                latitude: resolved.coordinate.latitude,
                longitude: resolved.coordinate.longitude
            )
            onSelect(resolved.title, payload)
            dismiss()
        }
    }
}

/// Plain-data stand-in for EKStructuredLocation so callers don't need to
/// import EventKit just to receive a picked location's coordinate.
struct PickedLocation {
    let title: String
    let latitude: Double
    let longitude: Double
}
