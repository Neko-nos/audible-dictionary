import AppKit
import SwiftUI

struct DictionarySearchField: NSViewRepresentable {
  @Binding var query: String

  func makeCoordinator() -> Coordinator { Coordinator(query: $query) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = InitiallyFocusedSearchField()
    field.placeholderString = "Search"
    field.cell?.isScrollable = true
    field.delegate = context.coordinator
    field.setAccessibilityLabel("Search dictionary")
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.query = $query
    if field.stringValue != query { field.stringValue = query }
  }

  @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
    var query: Binding<String>

    init(query: Binding<String>) { self.query = query }

    func controlTextDidChange(_ notification: Notification) {
      if let field = notification.object as? NSSearchField {
        query.wrappedValue = field.stringValue
      }
    }
  }
}

private final class InitiallyFocusedSearchField: NSSearchField {
  private var hasFocused = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // The toolbar must lay out the field before AppKit creates its editor.
    DispatchQueue.main.async { [weak self] in
      guard let self, !hasFocused, let window else { return }
      // AppKit can reattach toolbar views while resizing the window.
      hasFocused = window.makeFirstResponder(self)
    }
  }
}
