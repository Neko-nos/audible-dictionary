import SwiftUI

struct AudioEditorView: View {
  @ObservedObject var editor: AudioEditor

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let recording = editor.recording {
        HStack(alignment: .firstTextBaseline) {
          Text(recording.text).font(.callout).lineLimit(2).textSelection(.enabled)
          Spacer(minLength: 12)
          Text(
            [recording.source, recording.accent?.label].compactMap { $0 }.joined(separator: " · ")
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let clip = editor.clip {
        CropWaveform(editor: editor)
          .frame(height: 72)
        HStack(spacing: 10) {
          Button(action: editor.preview) {
            Image(systemName: editor.isPlaying ? "stop.fill" : "play.fill")
              .frame(width: 18)
          }
          .help(editor.isPlaying ? "Stop" : "Preview crop")
          .accessibilityLabel(editor.isPlaying ? "Stop preview" : "Preview crop")
          timeField("Start", value: $editor.start, range: 0...(editor.end - 1 / clip.sampleRate))
          Text("–").foregroundStyle(.secondary)
          timeField(
            "End", value: $editor.end, range: (editor.start + 1 / clip.sampleRate)...clip.duration)
          Text("\(editor.end - editor.start, specifier: "%.2f") s")
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Menu {
            Button("Reset selection", action: editor.reset).disabled(!editor.hasChanges)
            Button("Restore original", action: editor.restore).disabled(!editor.canRestore)
          } label: {
            Image(systemName: "arrow.uturn.backward")
          }
          .menuStyle(.borderlessButton).fixedSize()
          .help("Reset or restore")
          .accessibilityLabel("Reset or restore")
          Button("Save") { editor.save() }
            .buttonStyle(.borderedProminent).keyboardShortcut("s").disabled(!editor.hasChanges)
        }
      } else if editor.recording == nil {
        HStack {
          Image(systemName: "scissors")
          Text("Select a recording to crop.")
        }.font(.callout).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 64)
      }
      if let error = editor.error {
        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
      }
    }
    .padding(16)
    .background(.bar)
  }

  private func timeField(_ label: String, value: Binding<Double>, range: ClosedRange<Double>)
    -> some View
  {
    TextField(
      label,
      value: Binding(
        get: { value.wrappedValue },
        set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }
      ), format: .number.precision(.fractionLength(3))
    )
    .textFieldStyle(.roundedBorder).frame(width: 66).monospacedDigit()
    .accessibilityLabel("\(label) time in seconds").help("\(label) (seconds)")
  }
}

private struct CropWaveform: View {
  @ObservedObject var editor: AudioEditor

  var body: some View {
    GeometryReader { geometry in
      if let clip = editor.clip {
        let width = geometry.size.width - 16
        let left = width * editor.start / clip.duration
        let right = width * editor.end / clip.duration
        ZStack(alignment: .topLeading) {
          TimelineView(.animation(paused: !editor.isPlaying)) { _ in
            let playhead = editor.isPlaying ? editor.playhead : nil
            Canvas { context, size in
              let height = size.height
              let maximum = max(clip.peaks.max() ?? 0, 0.001)
              let selection = CGRect(x: left + 8, y: 0, width: right - left, height: height)
              context.fill(Path(selection), with: .color(.accentColor.opacity(0.1)))
              var waveform = Path()
              for (index, peak) in clip.peaks.enumerated() {
                let x = 8 + width * (Double(index) + 0.5) / Double(clip.peaks.count)
                let amplitude = max(1, CGFloat(peak / maximum) * (height / 2 - 5))
                waveform.move(to: CGPoint(x: x, y: height / 2 - amplitude))
                waveform.addLine(to: CGPoint(x: x, y: height / 2 + amplitude))
              }
              context.stroke(waveform, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
              context.clip(to: Path(selection))
              context.stroke(waveform, with: .color(.accentColor), lineWidth: 1)
              if let playhead {
                let x = 8 + width * playhead / clip.duration
                context.fill(
                  Path(CGRect(x: x, y: 0, width: 1.5, height: height)),
                  with: .color(.primary))
              }
            }
          }
          handle(
            "Start", value: $editor.start, width: width, duration: clip.duration,
            range: 0...(editor.end - 1 / clip.sampleRate)
          )
          .offset(x: left)
          handle(
            "End", value: $editor.end, width: width, duration: clip.duration,
            range: (editor.start + 1 / clip.sampleRate)...clip.duration
          )
          .offset(x: right)
        }
        .coordinateSpace(name: "waveform")
      }
    }
  }

  private func handle(
    _ label: String, value: Binding<Double>, width: Double, duration: Double,
    range: ClosedRange<Double>
  ) -> some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(Color.accentColor)
      .frame(width: 16)
      .overlay {
        Capsule().fill(.white.opacity(0.85)).frame(width: 2, height: 18)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0, coordinateSpace: .named("waveform"))
          .onChanged { drag in
            value.wrappedValue = min(
              range.upperBound,
              max(
                range.lowerBound,
                (drag.location.x - 8) / width * duration))
          }
      )
      .accessibilityLabel("\(label) of crop")
      .accessibilityValue("\(value.wrappedValue, specifier: "%.3f") seconds")
      .accessibilityAdjustableAction { direction in
        value.wrappedValue = min(
          range.upperBound,
          max(
            range.lowerBound,
            value.wrappedValue + (direction == .increment ? 0.01 : -0.01)))
      }
      .help("\(label) of crop")
  }
}
