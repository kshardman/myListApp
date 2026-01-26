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
    
    @State private var showingEditOverlay: Bool = false
    @State private var editingItemID: UUID? = nil
    @State private var editItemText: String = ""
    @FocusState private var isEditOverlayFieldFocused: Bool
    @State private var showingAddOverlay: Bool = false
    @State private var overlayItemText: String = ""
    @FocusState private var isOverlayFieldFocused: Bool

    // MARK: - Indent (1 level)
    private let indentStep: CGFloat = 24

    private func indentKey(for itemID: UUID) -> String {
        "indent_\(document.id.uuidString)_\(itemID.uuidString)"
    }

    private func indentLevel(for item: ListItem) -> Int {
        UserDefaults.standard.integer(forKey: indentKey(for: item.id))
    }

    private func setIndentLevel(_ level: Int, for item: ListItem) {
        let clamped = max(0, min(1, level))
        UserDefaults.standard.set(clamped, forKey: indentKey(for: item.id))
    }

    private func toggleIndent(_ item: ListItem) {
        let current = indentLevel(for: item)
        setIndentLevel(current == 0 ? 1 : 0, for: item)
        // Force SwiftUI refresh
        item.updatedAt = Date()
        document.updatedAt = Date()
        try? modelContext.save()
    }
    

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
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Button {
                                toggleDone(item)
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                            }
                            .buttonStyle(.plain)

                            Text(item.text)
                                .strikethrough(item.isDone, color: .secondary)
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, CGFloat(indentLevel(for: item)) * indentStep)
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissKeyboard()
                            editingItemID = item.id
                            editItemText = item.text
                            showingEditOverlay = true
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                toggleIndent(item)
                            } label: {
                                if indentLevel(for: item) == 0 {
                                    Label("Indent", systemImage: "arrow.right.to.line")
                                } else {
                                    Label("Outdent", systemImage: "arrow.left.to.line")
                                }
                            }
                            .tint(.gray)
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
                    Button {
                        draftName = document.name
                        isRenaming = true
                    } label: {
                        Text(document.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Rename list")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        Button {
                            // Open centered overlay
                            dismissKeyboard()
                            overlayItemText = ""
                            showingAddOverlay = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .padding(8)
                        }

                        Button {
                            deleteDoneItems()
                        } label: {
                            Image(systemName: "trash")
                                .padding(8)
                        }
                        .accessibilityLabel("Delete completed")
                    }
                }
            }
            .alert("Rename list", isPresented: $isRenaming) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { }
                Button("Save") { renameList() }
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

                            ZStack(alignment: .topLeading) {
                                if overlayItemText.isEmpty {
                                    Text("Enter item…")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }

                                TextEditor(text: $overlayItemText)
                                    .focused($isOverlayFieldFocused)
                                    .frame(minHeight: 96, maxHeight: 180)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 6)
                            }
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            HStack {
                                Button("Done", role: .cancel) {
                                    showingAddOverlay = false
                                    dismissKeyboard()
                                }
                                Spacer()
                                Button("Add") {
                                    saveOverlayItem(keepOpen: false)
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
                if showingEditOverlay {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture {
                                showingEditOverlay = false
                                dismissKeyboard()
                            }

                        VStack(spacing: 12) {
                            Text("Edit Item")
                                .font(.headline)

                            ZStack(alignment: .topLeading) {
                                if editItemText.isEmpty {
                                    Text("Item…")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                }

                                TextEditor(text: $editItemText)
                                    .focused($isEditOverlayFieldFocused)
                                    .frame(minHeight: 120, maxHeight: 240)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 6)
                            }
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            HStack {
                                Button("Done", role: .cancel) {
                                    showingEditOverlay = false
                                    dismissKeyboard()
                                }
                                Spacer()
                                Button("Save") {
                                    saveEditedItem()
                                    showingEditOverlay = false
                                    dismissKeyboard()
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
                            isEditOverlayFieldFocused = true
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

        // Clear indent on items being deleted so an undo comes back clean
        for id in ids { UserDefaults.standard.removeObject(forKey: indentKey(for: id)) }

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
            message: "\(ids.count) items deleted",
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

        // Clear indent so undo restores without nesting
        UserDefaults.standard.removeObject(forKey: indentKey(for: item.id))

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
