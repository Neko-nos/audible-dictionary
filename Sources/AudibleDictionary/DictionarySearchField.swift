import AppKit
import SwiftUI

struct DictionarySearchField: NSViewRepresentable {
  @Binding var query: String

  func makeCoordinator() -> Coordinator { Coordinator(query: $query) }

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Search"
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
