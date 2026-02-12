import SwiftUI

/// Privacy controls: delete items, export data, view info.
struct PrivacyView: View {
    let itemCount: Int
    let items: [AmbientActionItem]
    let onDeleteToday: () -> Void
    let onDeleteAll: () -> Void
    @State private var showDeleteTodayAlert = false
    @State private var showDeleteAllAlert = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section("Data") {
                LabeledContent("Total items", value: "\(self.itemCount)")
            }

            Section("Export") {
                Button {
                    self.exportData()
                } label: {
                    Label("Export All Data", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Exports all action items as a JSON file that can be shared or saved.")
            }

            Section("Delete Data") {
                Button { self.showDeleteTodayAlert = true } label: {
                    Label("Delete Today's Items", systemImage: "trash").foregroundStyle(.red)
                }
                Button { self.showDeleteAllAlert = true } label: {
                    Label("Delete All History", systemImage: "trash.fill").foregroundStyle(.red)
                }
            } footer: {
                Text("Deleting items does NOT remove reminders or calendar events already created. Use Undo on individual items to reverse actions.")
            }

            Section("Privacy") {
                Text("• Raw audio is never stored")
                Text("• Transcripts auto-deleted after 60 seconds on server")
                Text("• All data stored locally on device")
                Text("• Pause listening instantly with one tap")
            }
        }
        .navigationTitle("Privacy")
        .alert("Delete Today's Items?", isPresented: self.$showDeleteTodayAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { self.onDeleteToday() }
        }
        .alert("Delete All History?", isPresented: self.$showDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) { self.onDeleteAll() }
        }
        .sheet(isPresented: self.$showExportSheet) {
            if let url = self.exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportData() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self.items)
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent("ambient-export-\(Date().timeIntervalSince1970).json")
            try data.write(to: fileURL)
            self.exportURL = fileURL
            self.showExportSheet = true
        } catch {
            // Silently fail — could add error alert
        }
    }
}

/// UIKit share sheet wrapper for SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: self.items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
