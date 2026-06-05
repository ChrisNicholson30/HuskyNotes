//
//  TodoListView.swift
//  HuskyNotes
//
//  The "To-Do" section: a standalone quick-to-do list, separate from notes.
//  Jot a task, tick it off, edit it inline, swipe to delete, drag to reorder.
//  Backed by the `TodoItem` model — nothing here reads or writes note bodies.
//
//  Shown by `RootView` in place of `NoteListView` when the `.todo` smart list
//  is selected.
//

import SwiftUI
import SwiftData

/// A standalone list of quick to-dos (add / check / edit / delete / reorder).
struct TodoListView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeStore.self) private var themeStore
    private var theme: Theme { themeStore.active }

    /// All quick to-dos, in their manual order.
    @Query(sort: \TodoItem.sortOrder, order: .forward) private var todos: [TodoItem]

    /// Text for the "add" field.
    @State private var newText = ""

    /// Keeps the add field focused so several to-dos can be typed in a row.
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        List {
            Section {
                addRow
                ForEach(todos) { todo in
                    row(todo)
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            } footer: {
                Text("Quick to-dos live here — separate from your notes.")
                    .foregroundStyle(theme.textSecondary.swiftUIColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.background.swiftUIColor)
        .tint(theme.accent.swiftUIColor)
        .navigationTitle(SmartList.todo.title)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                if !todos.isEmpty { EditButton() }
            }
            #endif
            if todos.contains(where: \.isDone) {
                ToolbarItem {
                    Button { clearCompleted() } label: {
                        Label("Clear Completed", systemImage: "trash")
                    }
                    .tint(theme.accent.swiftUIColor)
                }
            }
        }
    }

    // MARK: Rows

    /// The input row that appends a new to-do on submit.
    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(theme.accent.swiftUIColor)
            TextField("Add a to-do", text: $newText)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit(add)
                .foregroundStyle(theme.textPrimary.swiftUIColor)
        }
        .listRowBackground(theme.surface.swiftUIColor)
    }

    /// A single to-do: a toggle plus its inline-editable text.
    private func row(_ todo: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                toggle(todo)
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle((todo.isDone ? theme.accent : theme.textSecondary).swiftUIColor)
            }
            .buttonStyle(.plain)

            TextField("To-do", text: textBinding(todo))
                .strikethrough(todo.isDone, color: theme.textSecondary.swiftUIColor)
                .foregroundStyle((todo.isDone ? theme.textSecondary : theme.textPrimary).swiftUIColor)
        }
        .listRowBackground(theme.surface.swiftUIColor)
    }

    // MARK: Actions

    /// A binding to a to-do's text that writes straight back to the model.
    private func textBinding(_ todo: TodoItem) -> Binding<String> {
        Binding(get: { todo.text }, set: { todo.text = $0 })
    }

    /// Appends a new to-do from the add field and keeps the field focused.
    private func add() {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (todos.map(\.sortOrder).max() ?? 0) + 1
        modelContext.insert(TodoItem(text: trimmed, sortOrder: nextOrder))
        newText = ""
        addFieldFocused = true
    }

    /// Toggles a to-do's completion, stamping/clearing `completedAt`.
    private func toggle(_ todo: TodoItem) {
        todo.isDone.toggle()
        todo.completedAt = todo.isDone ? Date() : nil
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(todos[index]) }
    }

    /// Reorders to-dos by rewriting their `sortOrder` to the new positions.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = todos
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() { item.sortOrder = index }
    }

    private func clearCompleted() {
        for todo in todos where todo.isDone { modelContext.delete(todo) }
    }
}
