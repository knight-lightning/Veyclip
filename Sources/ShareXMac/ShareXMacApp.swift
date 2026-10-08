import AppKit
import SwiftUI

@main
@MainActor
struct ShareXMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        WindowGroup("ShareX Mac", id: "history") {
            HistoryView(model: model)
        }
        .defaultSize(width: 1120, height: 780)
        Settings { SettingsView(model: model) }
        MenuBarExtra {
            CaptureMenu(model: model)
        } label: {
            Image(systemName: model.recorder.isActive ? "record.circle.fill" : "viewfinder")
                .symbolRenderingMode(.palette)
                .foregroundStyle(model.recorder.isActive ? Color.red : Color.primary)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.isWorking || model.recorder.isActive else { return .terminateNow }
        if model.recorder.canStop && !model.isWorking {
            let alert = NSAlert()
            alert.messageText = "Stop and save your recording before quitting?"
            alert.addButton(withTitle: "Stop and Quit")
            alert.addButton(withTitle: "Keep Recording")
            if alert.runModal() == .alertFirstButtonReturn { model.stopRecording(quitAfter: true) }
        } else {
            let alert = NSAlert()
            alert.messageText = "A capture is still being prepared or saved."
            alert.informativeText = "Finish or cancel the selection, or wait for the recording to finish saving, then quit."
            alert.runModal()
        }
        return .terminateCancel
    }
}

@MainActor
private struct CaptureMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if model.recorder.isActive {
            RecordingStatus(recorder: model.recorder)
            if model.canCancelCapture { Button("Cancel Recording") { model.cancelCapture() } }
            Button("Stop Recording") { model.stopRecording() }
                .disabled(!model.recorder.canStop || model.isWorking)
        } else {
            if model.canCancelCapture { Button("Stop Capture") { model.cancelCapture() } }
            Menu("Capture") { ScreenshotMenuContents(model: model) }.disabled(!model.canCapture)
            RecordingMenuContents(model: model)
        }
        Divider()
        Button("Show History") { openWindow(id: "history"); NSApp.activate(ignoringOtherApps: true) }
        SettingsLink { Text("Settings…") }
        Button("Open Captures Folder") { model.revealLibrary() }
        Divider()
        Button("Quit ShareX Mac") { NSApp.terminate(nil) }
    }
}

@MainActor
struct ScreenshotMenuContents: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ForEach(CaptureMode.allCases) { mode in
            Button(mode.rawValue) { model.takeScreenshot(mode) }
        }
        Button("Last Region") { model.takeScreenshot(.region, repeatLast: true) }.disabled(!model.canRepeat)
        Divider()
        Button("Scrolling Capture…") { model.startScrollingCapture() }
        Button("Auto-capture…") { model.startAutoCapture() }
        Divider()
        Toggle("Show Cursor", isOn: $model.showCursor)
        Menu("Screenshot Delay: \(model.screenshotDelay) s") {
            Picker("Delay", selection: $model.screenshotDelay) {
                ForEach([0, 1, 2, 3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
            }
        }
    }
}

@MainActor
struct RecordingMenuContents: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Menu("Screen Recording (MP4)") {
            ForEach(CaptureMode.recordingModes) { mode in
                Button(mode.rawValue) { model.toggleRecording(mode) }
            }
        }.disabled(!model.canCapture)
        Menu("Screen Recording (GIF)") {
            ForEach(CaptureMode.recordingModes) { mode in
                Button(mode.rawValue) { model.toggleRecording(mode, gif: true) }
            }
        }.disabled(!model.canCapture)
    }
}

@MainActor
struct RecordingStatus: View {
    @ObservedObject var recorder: RecordingController
    var body: some View {
        switch recorder.phase {
        case .idle: EmptyView()
        case .countdown(let seconds): Label("Starting in \(seconds)…", systemImage: "timer")
        case .starting: Label("Preparing recording…", systemImage: "record.circle")
        case .stopping: Label("Saving recording…", systemImage: "square.and.arrow.down")
        case .recording:
            if let date = recorder.startedAt {
                Label { Text(date, style: .timer).monospacedDigit() } icon: {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
            }
        }
    }
}
