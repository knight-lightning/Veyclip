import AppKit
import SwiftUI

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All Captures", screenshots = "Screenshots", videos = "Videos"
    var id: Self { self }
    var symbol: String {
        switch self { case .all: return "square.grid.2x2"; case .screenshots: return "photo"; case .videos: return "video" }
    }
}

@MainActor
struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var filter: HistoryFilter? = .all
    @State private var query = ""
    @State private var trashCandidate: CaptureItem?
    private var visibleItems: [CaptureItem] {
        model.library.items.filter { item in
            let match = filter == .all || filter == nil ||
                (filter == .screenshots && item.kind == .screenshot) || (filter == .videos && item.kind != .screenshot)
            return match && (query.isEmpty || item.filename.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "viewfinder").font(.system(size: 28, weight: .semibold)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ShareX Mac").font(.title3.bold())
                        Text("Capture. Explain. Share.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 22)
                List(HistoryFilter.allCases, selection: $filter) { value in
                    Label(value.rawValue, systemImage: value.symbol).tag(value)
                }.listStyle(.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    SettingsLink { Label("Settings & Hotkeys", systemImage: "slider.horizontal.3") }
                    Button { model.revealLibrary() } label: { Label("Captures Folder", systemImage: "folder") }
                    Link(destination: URL(string: "https://github.com/ShareX/ShareX")!) {
                        Label("Inspired by ShareX", systemImage: "arrow.up.right.square")
                    }.font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain).padding(16)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(filter?.rawValue ?? "All Captures").font(.largeTitle.bold())
                        Text("\(visibleItems.count) captures in your local library").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.recorder.isActive {
                        RecordingStatus(recorder: model.recorder)
                        if model.canCancelCapture { Button("Cancel") { model.cancelCapture() } }
                        Button("Stop", systemImage: "stop.fill") { model.stopRecording() }
                            .tint(.red).buttonStyle(.borderedProminent)
                            .disabled(!model.recorder.canStop || model.isWorking)
                    } else if model.canCancelCapture {
                        Button("Stop Capture", systemImage: "stop.fill") { model.cancelCapture() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Menu {
                            RecordingMenuContents(model: model)
                        } label: { Label("Record", systemImage: "record.circle") }.disabled(!model.canCapture)
                        Menu {
                            ScreenshotMenuContents(model: model)
                        } label: { Label("Capture", systemImage: "camera") }.disabled(!model.canCapture)
                    }
                }.padding(26)
                Divider()
                if visibleItems.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "Your captures start here" : "No matching captures", systemImage: "viewfinder")
                    } description: {
                        Text(query.isEmpty ? "Capture a region, window, or display. Your screenshots and recordings stay on your Mac." : "Try another filename.")
                    } actions: {
                        if query.isEmpty {
                            Button("Capture a Region") { model.takeScreenshot(.region) }
                                .buttonStyle(.borderedProminent).disabled(!model.canCapture)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 18)], spacing: 20) {
                            ForEach(visibleItems) { item in CaptureCard(item: item, model: model, trash: { trashCandidate = item }) }
                        }.padding(26)
                    }
                }
                Divider()
                HStack {
                    Circle().fill(model.recorder.isActive ? .red : .green).frame(width: 6, height: 6)
                    Text(model.status).lineLimit(1).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.isWorking { ProgressView().controlSize(.small) }
                    Text("LOCAL LIBRARY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .searchable(text: $query, prompt: "Search captures")
        .frame(minWidth: 820, minHeight: 560)
        .alert("Couldn't complete the action", isPresented: Binding(get: { model.errorMessage != nil },
                                                                   set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
            Button("Screen Capture Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Move this capture to Trash?", isPresented: Binding(get: { trashCandidate != nil },
                                                                               set: { if !$0 { trashCandidate = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let item = trashCandidate { model.remove(item, trash: true) }
                trashCandidate = nil
            }
        } message: { Text("The original media file will move to the macOS Trash.") }
    }
}

@MainActor
private struct CaptureCard: View {
    let item: CaptureItem
    @ObservedObject var model: AppModel
    let trash: () -> Void
    @State private var thumbnail: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor))
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit().padding(8)
                } else { Image(systemName: item.kind != .screenshot ? "video" : "photo").font(.largeTitle).foregroundStyle(.secondary) }
                if item.kind != .screenshot {
                    Image(systemName: "play.fill").font(.caption).padding(8).background(.ultraThinMaterial, in: Circle()).padding(12)
                }
            }.frame(height: 158)
            Text(item.filename).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
            HStack {
                Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                Spacer()
                Text(item.kind == .screenshot ? "PNG" : (item.kind == .gif ? "GIF" : "MP4"))
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.edit(item) }
        .contextMenu {
            Button(item.kind != .screenshot ? "Open Recording" : "Edit Screenshot") { model.edit(item) }
            Button("Copy") { model.copy(item) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.library.url(for: item)]) }
            Divider()
            Button("Remove from History") { model.remove(item, trash: false) }
            Button("Move to Trash…", role: .destructive, action: trash)
        }
        .task(id: item.id) { thumbnail = model.library.thumbnail(for: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.edit(item) }
    }
}
