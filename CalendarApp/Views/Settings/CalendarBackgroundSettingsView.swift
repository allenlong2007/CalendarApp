import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CalendarBackgroundSettingsView: View {
    @Environment(CalendarBackgroundStore.self) private var background
    @State private var photo: PhotosPickerItem?
    @State private var showingFiles = false
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var background = background
        Form {
            Section {
                CalendarBackgroundView()
                    .overlay(alignment: .bottomLeading) {
                        Label("Your calendar background", systemImage: "calendar")
                            .font(.headline)
                            .padding()
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
                Toggle("Show background image", isOn: $background.isEnabled)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Image opacity")
                        Spacer()
                        Text(background.opacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $background.opacity, in: 0.08...0.30, step: 0.01)
                        .accessibilityLabel("Image opacity")
                        .accessibilityValue(background.opacity.formatted(.percent.precision(.fractionLength(0))))
                }
                .disabled(!background.isEnabled)
            } footer: {
                Text("The image fills the calendar without stretching. Edges crop as the window changes. Lower opacity keeps events easier to read.")
            }

            Section("Choose an image") {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showingFiles = true
                } label: {
                    Label("Choose from Files", systemImage: "folder")
                }
                if background.hasCustomImage {
                    Button("Use Included Cloud Image") {
                        do { try background.useIncludedImage() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
                if importing {
                    HStack {
                        ProgressView()
                        Text("Preparing image…")
                    }
                }
            }
            .disabled(importing)

            Section {
                Text("Your image and appearance settings are saved on this device.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calendar Background")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { await importImage { try await background.importImage(url: url) } }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .task(id: photo) {
            guard let selected = photo else { return }
            await importImage {
                guard let data = try await selected.loadTransferable(type: Data.self) else {
                    throw BackgroundImageError.invalidImage
                }
                try await background.importImage(data: data)
            }
            photo = nil
        }
        .alert("Couldn’t Change Background", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func importImage(_ operation: () async throws -> Void) async {
        importing = true
        defer { importing = false }
        do { try await operation() }
        catch is CancellationError { }
        catch { errorMessage = error.localizedDescription }
    }
}
