import AppIntents
import SwiftData

// MARK: - Helpers

@MainActor
fileprivate func makeContainer() throws -> ModelContainer {
    let schema = Schema([ListDocument.self, ListItem.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
    return try ModelContainer(for: schema, configurations: [config])
}

@MainActor
fileprivate func fetchOrCreateList(named name: String, modelContext: ModelContext) throws -> ListDocument {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalName = trimmed.isEmpty ? "Inbox" : trimmed

    let descriptor = FetchDescriptor<ListDocument>(
        predicate: #Predicate { $0.isDeleted == false && $0.name == finalName }
    )
    if let existing = try modelContext.fetch(descriptor).first {
        return existing
    }

    let doc = ListDocument(name: finalName, createdAt: Date())
    modelContext.insert(doc)
    try modelContext.save()
    return doc
}

// MARK: - Create List Intent

struct CreateListIntent: AppIntent {
    static var title: LocalizedStringResource = "Create List"
    static var description = IntentDescription("Creates a new list in myLists.")

    @Parameter(title: "List Name")
    var listName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Create list \(\.$listName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = try fetchOrCreateList(named: listName, modelContext: context)
        return .result()
    }
}

// MARK: - Add Item Intent

struct AddItemToListIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Item to List"
    static var description = IntentDescription("Adds an item to a list in myLists.")

    @Parameter(title: "Item")
    var itemText: String

    @Parameter(title: "List", default: "Inbox")
    var listName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$itemText) to \(\.$listName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmedItem = itemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedItem.isEmpty else { return .result() }

        let container = try makeContainer()
        let context = ModelContext(container)

        let doc = try fetchOrCreateList(named: listName, modelContext: context)
        let item = ListItem(text: trimmedItem, document: doc)
        doc.items.append(item)
        doc.updatedAt = Date()

        try context.save()
        return .result()
    }
}

// MARK: - App Shortcuts

struct MyListsShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .lightBlue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddItemToListIntent(),
            phrases: [
                "Add item in \(.applicationName)",
                "In \(.applicationName), add an item",
                "Add to my lists in \(.applicationName)"
            ],
            shortTitle: "Add Item",
            systemImageName: "plus"
        )

        AppShortcut(
            intent: CreateListIntent(),
            phrases: [
                "Create list in \(.applicationName)",
                "In \(.applicationName), create a list",
                "Make a new list in \(.applicationName)"
            ],
            shortTitle: "Create List",
            systemImageName: "doc.badge.plus"
        )
    }
}
