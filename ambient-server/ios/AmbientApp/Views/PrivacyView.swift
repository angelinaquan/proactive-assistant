import SwiftUI

/// Privacy controls: delete items, view info.
struct PrivacyView: View {
    let itemCount: Int
    let onDeleteToday: () -> Void
    let onDeleteAll: () -> Void
    @State private var showDeleteTodayAlert = false
    @State private var showDeleteAllAlert = false

    var body: some View {
        List {
            Section("Data") { LabeledContent("Total items", value: "\(self.itemCount)") }
            Section("Delete Data") {
                Button { self.showDeleteTodayAlert = true } label: { Label("Delete Today's Items", systemImage: "trash").foregroundStyle(.red) }
                Button { self.showDeleteAllAlert = true } label: { Label("Delete All History", systemImage: "trash.fill").foregroundStyle(.red) }
            } footer: {
                Text("Deleting items does NOT remove reminders or calendar events already created. Use Undo on individual items to reverse actions.")
            }
            Section("Privacy") {
                Text("• Raw audio is never stored"); Text("• Transcripts processed and deleted within 60s")
                Text("• All data stored locally on device"); Text("• Pause listening instantly with one tap")
            }
        }.navigationTitle("Privacy")
            .alert("Delete Today's Items?", isPresented: self.$showDeleteTodayAlert) {
                Button("Cancel", role: .cancel) {}; Button("Delete", role: .destructive) { self.onDeleteToday() }
            }
            .alert("Delete All History?", isPresented: self.$showDeleteAllAlert) {
                Button("Cancel", role: .cancel) {}; Button("Delete All", role: .destructive) { self.onDeleteAll() }
            }
    }
}
