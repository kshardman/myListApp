//
//  Models.swift
//  myLists
//
//  Created by Keith Sharman on 1/22/26.
//
import Foundation
import SwiftData

@Model
final class ListDocument {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ListItem.document)
    var items: [ListItem]

    init(name: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isDeleted = false
        self.deletedAt = nil
        self.items = []
    }
}

@Model
final class ListItem {
    var id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var isDone: Bool

    var isDeleted: Bool
    var deletedAt: Date?

    // Persistent manual ordering within a list
    var sortIndex: Int = 0

    @Relationship
    var document: ListDocument?

    init(text: String, document: ListDocument, createdAt: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.isDone = false
        self.isDeleted = false
        self.deletedAt = nil
        self.document = document
    }
}
