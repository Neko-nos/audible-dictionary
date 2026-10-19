import AppKit
import SwiftUI

@main
struct AudibleDictionaryApp: App {
  @StateObject private var model = DictionaryModel()

  var body: some Scene {
    Window("Audible Dictionary", id: "dictionary") {
      DictionaryView(model: model, audio: model.audio)
        .frame(minWidth: 780, minHeight: 520)
    }
    .defaultSize(width: 880, height: 620)
    .windowToolbarStyle(.unified)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open Library…", action: model.chooseLibrary).keyboardShortcut("o")
      }
      CommandMenu("History") {
        Button("Back") { model.navigate(-1) }
          .keyboardShortcut("[").disabled(!model.canGoBack)
        Button("Forward") { model.navigate(1) }
          .keyboardShortcut("]").disabled(!model.canGoForward)
      }
      CommandMenu("Audio") {
        Button("Refresh Audio", action: model.refreshAudio)
      }
    }
  }
}

private struct DictionaryView: View {
  @ObservedObject var model: DictionaryModel
  @ObservedObject var audio: AudioPlayer

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 140, ideal: 175, max: 280)
        .toolbar(removing: .sidebarToggle)
    } detail: {
      GeometryReader { geometry in
        // Reserve room for history, title, and text-size controls so search stays visible.
        let searchWidth = min(340, max(120, geometry.size.width - 360))
        VStack(spacing: 0) {
          dictionaryTabs
          Divider()
          if model.library == nil {
            welcome
          } else {
            detail
          }
          if let error = model.error {
            HStack {
              Image(systemName: "exclamationmark.circle")
              Text(error).textSelection(.enabled)
              Spacer()
              Button("Dismiss") { model.error = nil }
            }.font(.callout).padding(10).background(.orange.opacity(0.12))
          }
          if audio.status != "Ready" && audio.status != "Stopped" && audio.status != "Finished" {
            Divider()
            HStack {
              if audio.isGenerating {
                ProgressView().controlSize(.small)
              } else {
                Image(systemName: audio.isPlaying ? "waveform" : "speaker.wave.2")
              }
              Text(audio.status).lineLimit(2)
              Spacer()
            }.font(.caption).padding(.horizontal, 16).padding(.vertical, 9)
          }
        }
        .background(.background)
        .navigationTitle("Dictionary")
        .navigationSubtitle(
          "\(model.results.count == 100 ? "100+" : "\(model.results.count)") \(model.isSpellingSuggestion ? "suggested" : "found")"
        )
        .toolbar {
          ToolbarItemGroup(placement: .navigation) {
            Button {
              model.navigate(-1)
            } label: {
              Image(systemName: "chevron.left")
            }
            .help("Back").disabled(!model.canGoBack)
            Button {
              model.navigate(1)
            } label: {
              Image(systemName: "chevron.right")
            }
            .help("Forward").disabled(!model.canGoForward)
          }
          ToolbarItem(placement: .primaryAction) {
            DictionaryTextSizeControl(textSize: $model.textSize)
              // Keep the joined control clear of the search field's focus ring.
              .padding(.trailing, 12)
          }
          ToolbarItem(placement: .primaryAction) {
            DictionarySearchField(query: $model.query)
              .frame(width: searchWidth)
              // AppKit otherwise retains the launch width when restoring a narrower window.
              .id(searchWidth)
          }
        }
      }
    }
    .task(id: model.query + "\0" + model.source) {
      do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
      await model.search()
    }
    .task(id: model.selection) { await model.select() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
      _ in
      audio.stop()
    }
  }

  private var dictionaryTabs: some View {
    HStack(spacing: 8) {
      dictionaryTab("All", source: "All")
      dictionaryTab("English – Japanese", source: "WISDOM")
      dictionaryTab("Japanese – English", source: "WISDOM_JE")
      dictionaryTab("British English", source: "ODE")
      Spacer()
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .background(.bar)
  }

  private func dictionaryTab(_ title: String, source: String) -> some View {
    Button {
      model.source = source
    } label: {
      Text(title)
        .fontWeight(model.source == source ? .medium : .regular)
        .foregroundStyle(model.source == source ? .primary : .secondary)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background {
          if model.source == source {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(model.source == source ? .isSelected : [])
  }

  private var welcome: some View {
    VStack(spacing: 16) {
      Image(systemName: "book.closed.fill").font(.system(size: 52)).foregroundStyle(.secondary)
      Text("Your English and Japanese dictionaries, with audio").font(.title)
      Text("Open a library imported from your installed WISDOM and ODE dictionaries.")
        .foregroundStyle(.secondary)
      Button("Open Library…", action: model.chooseLibrary).buttonStyle(.borderedProminent)
      Text("First time? Follow the setup steps in the repository’s README.").font(.callout)
        .foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      if model.results.isEmpty {
        if !model.query.isEmpty {
          Text("No results found.")
            .font(.callout).foregroundStyle(.secondary).padding(16)
        }
        Spacer()
      } else {
        if model.isSpellingSuggestion {
          Text("Did you mean?")
            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        List(model.results, selection: $model.selection) { item in
          VStack(alignment: .leading, spacing: 3) {
            Text(item.title).lineLimit(2)
            if model.source == "All" {
              Text(item.dictionaryTitle)
                .font(.caption).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 3).tag(item.id)
        }.listStyle(.sidebar)
      }
    }
    .padding(.top, 40)
  }

  @ViewBuilder private var detail: some View {
    if let entry = model.entry {
      EntryWebView(
        entry: entry, audioFolder: model.audioFolder,
        textSize: model.textSize, matchedTerm: model.selection?.matchedTerm,
        play: model.playExample, playHeadword: model.playHeadword, follow: model.follow)
    } else {
      VStack(spacing: 12) {
        Image(systemName: "text.book.closed").font(.system(size: 40)).foregroundStyle(.tertiary)
        Text("Look up a word. Hear it in context.").font(.title3).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
