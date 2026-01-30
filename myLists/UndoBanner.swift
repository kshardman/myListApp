// UndoBanner
// 1/22/2026

import SwiftUI

struct UndoBanner: View {
    @EnvironmentObject private var undoCenter: UndoCenter

    var body: some View {
        if let pending = undoCenter.pending {
            HStack(spacing: 12) {
                Text(pending.message)
                Spacer()

                Button {
                    // Dismiss without undoing.
                    undoCenter.clearPending()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
