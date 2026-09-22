import SwiftUI

/// Floating "Undo" toast, overlaid at the app root so it's visible regardless
/// of which tab is active.
struct UndoToastView: View {
    @Environment(UndoManagerService.self) private var undoManager

    var body: some View {
        if let pending = undoManager.pending {
            HStack(spacing: 12) {
                Text(pending.message)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    undoManager.performUndo()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ultramarine)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
