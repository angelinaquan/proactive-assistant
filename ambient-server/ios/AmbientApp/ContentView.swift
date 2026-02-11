import SwiftUI

/// Main app view with timeline, settings, and video chat.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("ambient.enabled") private var ambientEnabled: Bool = false
    @AppStorage("ambient.serverHost") private var serverHost: String = ""
    @AppStorage("ambient.serverPort") private var serverPort: Int = 8200
    @State private var showSettings = false
    @State private var showVideoChat = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Pause button
                HStack {
                    AmbientPauseButton(
                        isListening: self.appModel.ambientListening.isListening,
                        isPaused: self.appModel.ambientListening.isPaused,
                        onToggle: {
                            if self.appModel.ambientListening.isPaused {
                                Task { await self.appModel.ambientListening.resume() }
                            } else if self.appModel.ambientListening.isListening {
                                self.appModel.ambientListening.pause()
                            }
                        })
                    Spacer()
                    if !self.appModel.ambientListening.lastTranscript.isEmpty {
                        Text(self.appModel.ambientListening.lastTranscript)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }.padding(.horizontal).padding(.vertical, 8)

                // Timeline
                AmbientTimelineView(
                    items: self.appModel.ambientStore.items,
                    onKeep: { self.appModel.proactiveExecutor.confirm(actionPlanId: $0) },
                    onUndo: { id in Task { _ = await self.appModel.proactiveExecutor.undo(actionPlanId: id) } },
                    onExecute: { id in Task {
                        if let item = self.appModel.ambientStore.item(byId: id) { await self.appModel.proactiveExecutor.execute(item) }
                    }},
                    onDiscard: { self.appModel.proactiveExecutor.discard(actionPlanId: $0) })
            }
            .navigationTitle("Ambient")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { self.showVideoChat = true } label: { Image(systemName: "video.fill") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { self.showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: self.$showSettings) { SettingsView() }
            .fullScreenCover(isPresented: self.$showVideoChat) { VideoChatView() }
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ambient.enabled") private var ambientEnabled: Bool = false
    @AppStorage("ambient.serverHost") private var serverHost: String = ""
    @AppStorage("ambient.serverPort") private var serverPort: Int = 8200
    @AppStorage("ambient.autoExecute") private var autoExecute: Bool = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    Toggle("Ambient Listening", isOn: self.$ambientEnabled)
                        .onChange(of: self.ambientEnabled) { _, v in
                            self.appModel.updateServerConfig(host: self.serverHost, port: self.serverPort)
                            self.appModel.ambientListening.setEnabled(v)
                        }
                    TextField("Server Host", text: self.$serverHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { self.appModel.updateServerConfig(host: self.serverHost, port: self.serverPort) }
                    HStack {
                        Text("Port"); Spacer()
                        TextField("8200", value: self.$serverPort, format: .number)
                            .multilineTextAlignment(.trailing).frame(width: 80).keyboardType(.numberPad)
                            .onSubmit { self.appModel.updateServerConfig(host: self.serverHost, port: self.serverPort) }
                    }
                    Toggle("Auto-Execute Actions", isOn: self.$autoExecute)
                    Text("High-confidence actions are created immediately. Undo within 30 minutes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Status") {
                    LabeledContent("Status", value: self.appModel.ambientListening.statusText)
                    LabeledContent("Connected", value: self.appModel.ambientListening.isConnected ? "Yes" : "No")
                    LabeledContent("Pending Actions", value: "\(self.appModel.ambientStore.pendingCount)")
                }

                Section {
                    NavigationLink {
                        PrivacyView(
                            itemCount: self.appModel.ambientStore.items.count,
                            onDeleteToday: { self.appModel.ambientStore.deleteAllFromToday() },
                            onDeleteAll: { self.appModel.ambientStore.deleteAll() })
                    } label: { Label("Privacy & Data", systemImage: "shield.lefthalf.filled") }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { self.dismiss() }
                }
            }
        }
    }
}
