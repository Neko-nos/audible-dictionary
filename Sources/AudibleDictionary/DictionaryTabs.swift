import SwiftUI

struct DictionaryTabs: View {
  @ObservedObject var model: DictionaryModel

  var body: some View {
    HStack(spacing: 8) {
      ForEach(model.dictionaryOrder, id: \.self) { source in
        DictionaryTabButton(source: source, model: model)
      }
      Spacer()
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(.bar)
  }
}

private struct DictionaryTabButton: View {
  let source: String
  @ObservedObject var model: DictionaryModel
  @State private var isTargeted = false

  private var isSelected: Bool { model.source == source }

  private var title: String {
    switch source {
    case "WISDOM": "English – Japanese"
    case "WISDOM_JE": "Japanese – English"
    case "ODE": "British English"
    default: "All"
    }
  }

  var body: some View {
    Button {
      model.source = source
    } label: {
      Text(title)
        .fontWeight(isSelected ? .medium : .regular)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay {
      if isTargeted {
        RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2)
          .allowsHitTesting(false)
      }
    }
    .draggable(source)
    .dropDestination(for: String.self) { sources, _ in
      guard let dragged = sources.first else { return false }
      return withAnimation { model.moveDictionary(dragged, to: source) }
    } isTargeted: {
      isTargeted = $0
    }
    .help("Drag onto another tab to change the dictionary order.")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
