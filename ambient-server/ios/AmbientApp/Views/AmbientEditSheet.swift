import SwiftUI

/// Sheet for editing an action plan's title, deadline, and notes before confirming.
struct AmbientEditSheet: View {
    let item: AmbientActionItem
    let onSave: (String, String, String) -> Void // (title, deadline, notes)
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var deadline: String
    @State private var notes: String

    init(item: AmbientActionItem, onSave: @escaping (String, String, String) -> Void) {
        self.item = item
        self.onSave = onSave
        self._title = State(initialValue: item.actionParams["title"]?.stringValue ?? item.actionDescription)
        self._deadline = State(initialValue: item.deadline ?? "")
        self._notes = State(initialValue: item.actionParams["notes"]?.stringValue ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Action") {
                    TextField("Title", text: self.$title)
                    TextField("Deadline", text: self.$deadline)
                        .textInputAutocapitalization(.never)
                }
                Section("Notes") {
                    TextEditor(text: self.$notes)
                        .frame(minHeight: 80)
                }
                Section {
                    Text("Original: \(self.item.actionDescription)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !self.item.sourceTranscript.isEmpty {
                        Text("Heard: \"\(self.item.sourceTranscript)\"")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Edit Action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { self.dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        self.onSave(self.title, self.deadline, self.notes)
                        self.dismiss()
                    }
                    .disabled(self.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
