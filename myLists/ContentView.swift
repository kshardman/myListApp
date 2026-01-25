//
//  ContentView.swift
//  my List Apps
//
//  Created by Keith Sharman on 1/22/26.
//
//
//


import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var undoCenter: UndoCenter

    @Query(
        filter: #Predicate<ListDocument> { $0.isDeleted == false },
        sort: [SortDescriptor(\ListDocument.updatedAt, order: .reverse)]
    )
    private var docs: [ListDocument]

    @State private var showingShare: Bool = false
    @State private var shareItems: [Any] = []
    @State private var showingSettings: Bool = false

    // New-list UX
    @State private var showingNewListSheet: Bool = false
    @State private var draftNewListName: String = ""

    var body: some View {
        NavigationStack {
            List {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 28, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("my List App")
                            .font(.headline)
                        Text("Quick lists with Undo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .listRowSeparator(.hidden)

                ForEach(docs) { doc in
                    NavigationLink(value: doc) {
                        Text(doc.name)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            softDeleteList(doc)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button {
                            shareList(doc)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            draftNewListName = ""
                            showingNewListSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .padding(8)
                        }
                        .accessibilityLabel("New list")

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .padding(8)
                        }
                        .accessibilityLabel("Settings")
                    }
                }
            }
            .navigationDestination(for: ListDocument.self) { doc in
                ListDetailView(document: doc)
            }
            .overlay(alignment: .bottom) {
                UndoBanner()
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(activityItems: shareItems)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingNewListSheet) {
                NewListSheet(
                    name: $draftNewListName,
                    onCancel: { showingNewListSheet = false },
                    onSave: {
                        createList(named: draftNewListName)
                        showingNewListSheet = false
                    }
                )
            }
        }
    }

    private func defaultNameForNewList() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date())
    }

    private func createList(named proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? defaultNameForNewList() : trimmed
        let unique = makeUniqueListName(baseName)

        let doc = ListDocument(name: unique, createdAt: Date())
        modelContext.insert(doc)
        doc.updatedAt = Date()

        try? modelContext.save()
        draftNewListName = ""
    }

    private func makeUniqueListName(_ base: String) -> String {
        let existing = Set(docs.map { $0.name.lowercased() })
        if !existing.contains(base.lowercased()) { return base }

        var i = 2
        while true {
            let candidate = "\(base) (\(i))"
            if !existing.contains(candidate.lowercased()) { return candidate }
            i += 1
        }
    }

    private func softDeleteList(_ doc: ListDocument) {
        doc.isDeleted = true
        doc.deletedAt = Date()
        doc.updatedAt = Date()
        try? modelContext.save()

        let pending = UndoCenter.PendingUndo(
            kind: .list(doc.id),
            message: "List deleted",
            expiresAt: Date().addingTimeInterval(5)
        )

        undoCenter.setPending(pending, finalize: { [weak modelContext] in
            guard let modelContext else { return }
            finalizeExpiredDeletes(modelContext: modelContext)
        })
    }

    private func shareList(_ doc: ListDocument) {
        let items = doc.items.filter { !$0.isDeleted }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var lines: [String] = []
        lines.append(doc.name)
        lines.append(df.string(from: Date()))
        lines.append("")

        for item in items {
            let mark = item.isDone ? "[x]" : "[ ]"
            lines.append("\(mark) \(item.text)")
        }

        let text = lines.joined(separator: "\n")

        // Write to temp file
        let safeName = doc.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).txt")

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            shareItems = [url]
            showingShare = true
        } catch {
            // fallback: share plain text if file write fails
            shareItems = [text]
            showingShare = true
        }
    }
    

    private func finalizeExpiredDeletes(modelContext: ModelContext) {
        let cutoff = Date().addingTimeInterval(-5)

        let listDescriptor = FetchDescriptor<ListDocument>(
            predicate: #Predicate { doc in
                doc.isDeleted == true && doc.deletedAt != nil && doc.deletedAt! <= cutoff
            }
        )
        if let lists = try? modelContext.fetch(listDescriptor) {
            for doc in lists { modelContext.delete(doc) }
        }

        let itemDescriptor = FetchDescriptor<ListItem>(
            predicate: #Predicate { item in
                item.isDeleted == true && item.deletedAt != nil && item.deletedAt! <= cutoff
            }
        )
        if let items = try? modelContext.fetch(itemDescriptor) {
            for item in items { modelContext.delete(item) }
        }

        try? modelContext.save()
    }
}

// MARK: - New List Sheet

private struct NewListSheet: View {
    @Binding var name: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("List name (optional)", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { onSave() }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave() }
                }
            }
            .onAppear {
                // Focus after the sheet animates in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isNameFocused = true
                }
            }
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    private var versionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
    }

    private var buildString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    LabeledContent("Version", value: versionString)
                    LabeledContent("Build", value: buildString)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
