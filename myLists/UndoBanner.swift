// UndoBanner
// 1/22/2026

import SwiftUI
import SwiftData

struct UndoBanner: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var undoCenter: UndoCenter

    var body: some View {
        if let pending = undoCenter.pending {
            HStack(spacing: 12) {
                Text(pending.message)
                Spacer()
                Button("Undo") { undo(pending) }
                    .buttonStyle(.borderedProminent)

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
        }
    }

    private func undo(_ pending: UndoCenter.PendingUndo) {
        switch pending.kind {
        case .list(let id):
            if let doc = try? modelContext.fetch(
                FetchDescriptor<ListDocument>(predicate: #Predicate { $0.id == id })
            ).first {
                doc.isDeleted = false
                doc.deletedAt = nil
                doc.updatedAt = Date()
                try? modelContext.save()
            }

        case .item(let itemID, let listID):
            let itemDescriptor = FetchDescriptor<ListItem>(predicate: #Predicate { $0.id == itemID })
            let docDescriptor = FetchDescriptor<ListDocument>(predicate: #Predicate { $0.id == listID })

            if let item = try? modelContext.fetch(itemDescriptor).first {
                item.isDeleted = false
                item.deletedAt = nil
                item.updatedAt = Date()
                item.isDone = false

                if let doc = try? modelContext.fetch(docDescriptor).first {
                    // Move to end
                    if let existing = doc.items.firstIndex(where: { $0.id == item.id }) {
                        doc.items.remove(at: existing)
                    }
                    doc.items.append(item)
                    doc.updatedAt = Date()
                }

                try? modelContext.save()
            }
        case .bulkItems(let itemIDs, let listID):
            let docDescriptor = FetchDescriptor<ListDocument>(predicate: #Predicate { $0.id == listID })
            guard let doc = try? modelContext.fetch(docDescriptor).first else { break }

            for itemID in itemIDs {
                let itemDescriptor = FetchDescriptor<ListItem>(predicate: #Predicate { $0.id == itemID })
                if let item = try? modelContext.fetch(itemDescriptor).first {
                    item.isDeleted = false
                    item.deletedAt = nil
                    item.updatedAt = Date()
                    item.isDone = false

                    if !doc.items.contains(where: { $0.id == item.id }) {
                        doc.items.append(item)
                    }
                }
            }

            doc.updatedAt = Date()
            try? modelContext.save()
        }

        undoCenter.clearPending()
    }
}
