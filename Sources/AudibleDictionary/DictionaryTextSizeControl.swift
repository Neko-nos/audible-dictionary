import AppKit
import SwiftUI

struct DictionaryTextSizeControl: NSViewRepresentable {
  @Binding var textSize: Double

  func makeCoordinator() -> Coordinator { Coordinator(textSize: $textSize) }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      images: [
        NSImage(
          systemSymbolName: "textformat.size.smaller", accessibilityDescription: "Make text smaller"
        )!,
        NSImage(
          systemSymbolName: "textformat.size.larger", accessibilityDescription: "Make text larger")!,
      ],
      trackingMode: .momentary, target: context.coordinator,
      action: #selector(Coordinator.changeSize(_:)))
    // Automatic toolbar styling separates the segments on macOS Tahoe.
    control.segmentStyle = .texturedSquare
    control.setToolTip("Make text smaller", forSegment: 0)
    control.setToolTip("Make text larger", forSegment: 1)
    return control
  }

  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.textSize = $textSize
    control.setEnabled(textSize > 12, forSegment: 0)
    control.setEnabled(textSize < 30, forSegment: 1)
  }

  @MainActor final class Coordinator: NSObject {
    var textSize: Binding<Double>

    init(textSize: Binding<Double>) { self.textSize = textSize }

    @objc func changeSize(_ control: NSSegmentedControl) {
      textSize.wrappedValue += control.selectedSegment == 0 ? -1 : 1
    }
  }
}
