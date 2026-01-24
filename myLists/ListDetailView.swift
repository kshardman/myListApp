import SwiftUI
import SwiftData
import UIKit

struct ListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var undoCenter: UndoCenter

    @Bindable var document: ListDocument

    @State private var editMode: EditMode = .inactive

    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    
    // Tail behavior
    @State private var pendingScrollToItemID: UUID?
    
    @State private var isEditingItem: Bool = false
    @State private var editingItemID: UUID? = nil
    @State private var editItemText: String = ""
    @State private var showingAddOverlay: Bool = false
    @State private var overlayItemText: String = ""
    @FocusState private var isOverlayFieldFocused: Bool
    

    private var visibleItems: [ListItem] {
        document.items
            .filter { !$0.isDeleted }
            .sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(visibleItems) { item in
                        HStack(spacing: 12) {
                            Button {
                                toggleDone(item)
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)

                            Text(item.text)
                                .strikethrough(item.isDone, color: .secondary)
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                        }
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissKeyboard()
                            editingItemID = item.id
                            editItemText = item.text
                            isEditingItem = true
                        }
                    }
                    .onDelete(perform: deleteItems)
                    .onMove(perform: moveItems)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
                if editMode == .active { editMode = .inactive }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                dismissKeyboard()
                editMode = .active
            }
            .environment(\.editMode, $editMode)
            .onChange(of: pendingScrollToItemID) { _, newValue in
                guard let id = newValue else { return }
                withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                pendingScrollToItemID = nil
            }
            .task {
                let vis = visibleItems
                guard vis.count > 1 else { return }
                let allZero = vis.allSatisfy { $0.sortIndex == 0 }
                guard allZero else { return }

                // Seed sortIndex by createdAt to preserve your existing order.
                let seeded = vis.sorted { $0.createdAt < $1.createdAt }
                for (idx, item) in seeded.enumerated() {
                    item.sortIndex = idx
                    item.updatedAt = Date()
                }
                document.updatedAt = Date()
                try? modelContext.save()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(document.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            // Open centered overlay
                            dismissKeyboard()
                            overlayItemText = ""
                            showingAddOverlay = true
                        } label: {
                            Image(systemName: "plus")
                        }

                        Button {
                            deleteDoneItems()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .accessibilityLabel("Delete completed")

                        Button("Rename") {
                            draftName = document.name
                            isRenaming = true
                        }
                    }
                }
            }
            .alert("Rename list", isPresented: $isRenaming) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { }
                Button("Save") { renameList() }
            }
            .alert("Edit item", isPresented: $isEditingItem) {
                TextField("Item", text: $editItemText)
                Button("Cancel", role: .cancel) { editingItemID = nil }
                Button("Save") { saveEditedItem() }
            }
            .overlay(alignment: .bottom) {
                UndoBanner()
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            .overlay {
                if showingAddOverlay {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture {
                                showingAddOverlay = false
                                dismissKeyboard()
                            }

                        VStack(spacing: 12) {
                            Text("New Item")
                                .font(.headline)

                            TextField("Enter item…", text: $overlayItemText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isOverlayFieldFocused)
                                .submitLabel(.done)
                                .onSubmit { saveOverlayItem(keepOpen: true) }

                            HStack {
                                Button("Done", role: .cancel) {
                                    showingAddOverlay = false
                                    dismissKeyboard()
                                }
                                Spacer()
                                Button("Add") {
                                    saveOverlayItem(keepOpen: true)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 420)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 24)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isOverlayFieldFocused = true
                        }
                    }
                }
            }
        }
    }

    private func toggleDone(_ item: ListItem) {
        item.isDone.toggle()
        item.updatedAt = Date()
        document.updatedAt = Date()
        try? modelContext.save()
    }

    private func renameList() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.name = trimmed
        document.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteDoneItems() {
        // Exit reorder mode if active
        editMode = .inactive
        dismissKeyboard()

        let doneItems = document.items.filter { !$0.isDeleted && $0.isDone }
        guard !doneItems.isEmpty else { return }

        // Capture IDs for undo before mutating
        let ids = doneItems.map { $0.id }

        for item in doneItems {
            // Remove from relationship so row disappears immediately
            if let idx = document.items.firstIndex(where: { $0.id == item.id }) {
                document.items.remove(at: idx)
            }
            item.isDeleted = true
            item.deletedAt = Date()
            item.updatedAt = Date()
        }

        document.updatedAt = Date()
        try? modelContext.save()

        let pending = UndoCenter.PendingUndo(
            kind: .bulkItems(ids, document.id),
            message: "Deleted \(ids.count) completed",
            expiresAt: Date().addingTimeInterval(3)
        )

        undoCenter.setPending(pending, finalize: { [weak modelContext] in
            guard let modelContext else { return }
            finalizeExpiredDeletes(modelContext: modelContext)
        })
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            guard index >= 0 && index < visibleItems.count else { continue }
            softDeleteItem(visibleItems[index])
        }
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var items = visibleItems
        items.move(fromOffsets: source, toOffset: destination)

        for (index, item) in items.enumerated() {
            item.sortIndex = index
            item.updatedAt = Date()
        }

        document.updatedAt = Date()
        try? modelContext.save()
    }

    private func softDeleteItem(_ item: ListItem) {
        // Remove from relationship so row disappears immediately
        if let idx = document.items.firstIndex(where: { $0.id == item.id }) {
            document.items.remove(at: idx)
        }

        item.isDeleted = true
        item.deletedAt = Date()
        item.updatedAt = Date()
        document.updatedAt = Date()
        try? modelContext.save()

        let pending = UndoCenter.PendingUndo(
            kind: .item(item.id, document.id),
            message: "Item deleted",
            expiresAt: Date().addingTimeInterval(3)
        )

        undoCenter.setPending(pending, finalize: { [weak modelContext] in
            guard let modelContext else { return }
            finalizeExpiredDeletes(modelContext: modelContext)
        })
    }

    private func finalizeExpiredDeletes(modelContext: ModelContext) {
        let cutoff = Date().addingTimeInterval(-3)

        let descriptor = FetchDescriptor<ListItem>(
            predicate: #Predicate { x in
                x.isDeleted == true && x.deletedAt != nil && x.deletedAt! <= cutoff
            }
        )
        if let items = try? modelContext.fetch(descriptor) {
            for x in items { modelContext.delete(x) }
        }
        try? modelContext.save()
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
    
private func saveOverlayItem(keepOpen: Bool = false) {
    let trimmed = overlayItemText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let item = ListItem(text: trimmed, document: document)
    let newItemID = item.id

    let nextIndex = (document.items.map { $0.sortIndex }.max() ?? -1) + 1
    item.sortIndex = nextIndex

    document.items.append(item)
    document.updatedAt = Date()
    try? modelContext.save()

    // ready for next entry
    overlayItemText = ""

    if keepOpen {
        // keep overlay + keyboard up
        DispatchQueue.main.async { isOverlayFieldFocused = true }
    } else {
        showingAddOverlay = false
        dismissKeyboard()
    }

    // show the item you just added
    pendingScrollToItemID = newItemID
}

    private func saveEditedItem() {
        guard let id = editingItemID else { return }
        let trimmed = editItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            editingItemID = nil
            return
        }

        if let item = document.items.first(where: { $0.id == id }) {
            item.text = trimmed
            item.updatedAt = Date()
            document.updatedAt = Date()
            try? modelContext.save()
        }

        editingItemID = nil
    }
}
