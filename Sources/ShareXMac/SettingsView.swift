import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        TabView {
            Form {
                Section("Screenshots") {
                    Toggle("Show the cursor", isOn: $model.showCursor)
                    Toggle("Open the editor after capture", isOn: $model.openEditor)
                    Toggle("Copy to clipboard after capture", isOn: $model.copyAfterCapture)
                    Picker("Screenshot delay", selection: $model.screenshotDelay) {
                        ForEach([0, 1, 2, 3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
                    }
                    Text("Original screenshots are always saved before editing.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Auto-capture") {
                    Stepper("Interval: \(model.autoInterval) seconds", value: $model.autoInterval, in: 1...3600)
                    Stepper("Screenshots: \(model.autoCount)", value: $model.autoCount, in: 1...100)
                    Text("Captures the selected region repeatedly. Saved images remain in history when stopped.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Recording") {
                    Toggle("Record system audio", isOn: $model.systemAudio)
                    Toggle("Record microphone", isOn: $model.microphone)
                    Text("MP4 · H.264 · 30 fps · 3-second countdown").font(.caption).foregroundStyle(.secondary)
                    Text("GIF · silent · 10 fps · up to 960 px · maximum 60 seconds").font(.caption).foregroundStyle(.secondary)
                }
                Section("Local library") {
                    LabeledContent("Location", value: model.library.outputFolder.path).font(.caption)
                    Button("Choose Captures Folder…") { model.library.chooseOutputFolder() }
                    Button("Open Captures Folder") { model.revealLibrary() }
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Section("Global hotkeys") {
                    ForEach(Hotkeys.actions, id: \.0) { title, name in
                        KeyboardShortcuts.Recorder(title, name: name)
                            .shortcutValidation { shortcut in
                                if let other = Hotkeys.actions.first(where: { $0.1 != name && $0.1.shortcut == shortcut }) {
                                    return .disallow(reason: "Already assigned to \(other.0).")
                                }
                                return .allow
                            }
                    }
                    Text("Click a shortcut field and press your preferred keys. Shortcuts work while another app is active. The recording shortcut starts and stops a region recording.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Reset Hotkeys") { KeyboardShortcuts.reset(Hotkeys.actions.map(\.1)) }
                }
            }.formStyle(.grouped).tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }.frame(width: 610, height: 650)
    }
}
