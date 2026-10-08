import SwiftUI
import CaptureCore

@MainActor
struct EditorView: View {
    @ObservedObject var model: EditorModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                ForEach(Tool.allCases, id: \.self) { tool in
                    Button { model.tool = tool } label: {
                        Image(systemName: tool.symbol).font(.system(size: 17)).frame(width: 36, height: 32)
                            .foregroundStyle(model.tool == tool ? Color.white : Color.primary)
                            .background(model.tool == tool ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help(tool.title).accessibilityLabel(tool.title)
                }
                }
                }.frame(height: 36)
                Divider().frame(height: 25).padding(.horizontal, 8)
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.history.canUndo).keyboardShortcut("z", modifiers: .command).help("Undo")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.history.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).help("Redo")
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { model.copy() }.keyboardShortcut("c", modifiers: .command)
                Button("Save As…", systemImage: "square.and.arrow.down") { model.export() }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
            }.padding(12)
            Divider()
            HStack(spacing: 14) {
                if model.tool.usesColor {
                ForEach(Array(InkColor.palette.enumerated()), id: \.offset) { _, color in
                    Button { model.color = color } label: {
                        Circle().fill(Color(nsColor: color.nsColor)).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(model.color == color ? Color.primary : Color.clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityLabel("Annotation color")
                }
                }
                Divider().frame(height: 20)
                if [.rectangle, .ellipse].contains(model.tool) { Toggle("Fill", isOn: $model.filled).toggleStyle(.checkbox) }
                if [.blur, .pixelate].contains(model.tool) {
                    Text(model.tool == .blur ? "Blur radius" : "Block size").font(.caption)
                    Slider(value: $model.effectAmount, in: 2...64, step: 2).frame(width: 130)
                    Text("\(Int(model.effectAmount)) px").font(.caption.monospacedDigit())
                } else if model.tool == .magnify {
                    Text("Magnification").font(.caption)
                    Slider(value: $model.magnification, in: 1.5...5, step: 0.5).frame(width: 130)
                    Text("\(model.magnification, specifier: "%.1f")×").font(.caption)
                } else {
                Text("Width").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.thickness, in: 1...(model.tool == .eraser ? 100 : 16), step: 1).frame(width: 85)
                Text("\(Int(model.thickness))").font(.caption.monospacedDigit()).frame(width: 18)
                Text("Text").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.textSize, in: 12...96, step: 2).frame(width: 85)
                }
                if model.selected != nil { Button("Apply to Selected") { model.applyStyle() }.controlSize(.small) }
                Spacer()
                if model.history.document.crop != nil { Button("Reset Crop") { model.resetCrop() }.controlSize(.small) }
            }.padding(.horizontal, 16).padding(.vertical, 10)
            EditorCanvas(model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(model.message).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.visibleRect.width)) × \(Int(model.visibleRect.height)) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { model.zoom = max(0.3, model.zoom - 0.2) } label: { Image(systemName: "minus.magnifyingglass") }
                Button("Fit") { model.zoom = 1; model.pan = .zero }.controlSize(.small)
                Button { model.zoom = min(3, model.zoom + 0.2) } label: { Image(systemName: "plus.magnifyingglass") }
            }.padding(12)
        }
        .alert("Couldn't complete the edit", isPresented: Binding(get: { model.errorMessage != nil },
                                                                 set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}
