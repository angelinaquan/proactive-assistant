import SwiftUI

/// Privacy controls for ambient listening data: delete items, clear history,
/// view transcript log, and configure retention settings.
struct AmbientPrivacyView: View {
    let itemCount: Int
    let onDeleteToday: () -> Void
    let onDeleteAll: () -> Void

    @State private var showDeleteTodayAlert = false
    @State private var showDeleteAllAlert = false

    var body: some View {
        List {
            Section {
                LabeledContent("Total items", value: "\(self.itemCount)")
            } header: {
                Text("Data")
            }

            Section {
                Button {
                    self.showDeleteTodayAlert = true
                } label: {
                    Label("Delete Today's Items", systemImage: "trash")
                        .foregroundStyle(.red)
                }

                Button {
                    self.showDeleteAllAlert = true
                } label: {
                    Label("Delete All History", systemImage: "trash.fill")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Delete Data")
            } footer: {
                Text("Deleting items here does NOT remove reminders or calendar events that were already created. Use the Undo button on individual items to reverse actions.")
            }

            Section {
                Text("• Raw audio is never stored — only transcripts")
                Text("• Transcripts are processed and deleted within 60 seconds")
                Text("• All data is stored locally on this device")
                Text("• Pause listening instantly with one tap")
            } header: {
                Text("Privacy Information")
            }
        }
        .navigationTitle("Privacy")
        .alert("Delete Today's Items?", isPresented: self.$showDeleteTodayAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                self.onDeleteToday()
            }
        } message: {
            Text("This will remove all ambient items detected today. Created reminders and calendar events will not be affected.")
        }
        .alert("Delete All History?", isPresented: self.$showDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                self.onDeleteAll()
            }
        } message: {
            Text("This will permanently delete all ambient listening history. Created reminders and calendar events will not be affected.")
        }
    }
}
