import AppKit
import DictionaryCore
import SwiftUI

@main
struct AudibleDictionaryApp: App {
  @StateObject private var model = DictionaryModel()

  var body: some Scene {
    Window("Audible Dictionary", id: "dictionary") {
      DictionaryView(model: model, audio: model.audio)
        .frame(minWidth: 780, minHeight: 520)
    }
    .defaultSize(width: 1060, height: 760)
    .commands {
      CommandGroup(after: .newItem) {
        Button("Open Library…", action: model.chooseLibrary).keyboardShortcut("o")
      }
      CommandMenu("Audio") {
        Button("Refresh Audio", action: model.refreshAudio)
        Button("Stop", action: model.audio.stop).keyboardShortcut(".")
      }
    }
  }
}

private struct DictionaryView: View {
  @ObservedObject var model: DictionaryModel
  @ObservedObject var audio: AudioPlayer
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "book.closed").font(.title2).foregroundStyle(.tint)
        TextField("Search English words", text: $model.query)
          .textFieldStyle(.roundedBorder).font(.title3)
          .focused($searchFocused)
        Picker("Dictionary", selection: $model.source) {
          Text("All").tag("All")
          Text("WISDOM").tag("WISDOM")
          Text("ODE").tag("ODE")
        }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
      }.padding(16)
      Divider()
      if model.library == nil {
        welcome
      } else {
        HSplitView {
          sidebar.frame(minWidth: 205, idealWidth: 235, maxWidth: 320)
          detail.frame(minWidth: 520, maxWidth: .infinity)
        }
      }
      if let error = model.error {
        HStack {
          Image(systemName: "exclamationmark.circle")
          Text(error).textSelection(.enabled)
          Spacer()
          Button("Dismiss") { model.error = nil }
        }.font(.callout).padding(10).background(.orange.opacity(0.12))
      }
      Divider()
      HStack {
        if audio.isGenerating {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: audio.isPlaying ? "waveform" : "speaker.wave.2")
        }
        Text(audio.status).lineLimit(2)
        Spacer()
        Button("Stop", action: audio.stop).disabled(!audio.isPlaying && !audio.isGenerating)
      }.font(.caption).padding(.horizontal, 16).padding(.vertical, 9)
    }
    .tint(Color(red: 0.13, green: 0.43, blue: 0.33))
    .task(id: model.query + "\0" + model.source) {
      do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
      await model.search()
    }
    .task(id: model.selection) { await model.select() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) {
      _ in
      audio.stop()
    }
    .defaultFocus($searchFocused, true)
  }

  private var welcome: some View {
    VStack(spacing: 16) {
      Image(systemName: "book.closed.fill").font(.system(size: 52)).foregroundStyle(.tint)
      Text("Your English dictionary, with audio").font(.title)
      Text("Open a library imported from your installed WISDOM and ODE dictionaries.")
        .foregroundStyle(.secondary)
      Button("Open Library…", action: model.chooseLibrary).buttonStyle(.borderedProminent)
      Text("First time? Follow the setup steps in the repository’s README.").font(.callout)
        .foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("RESULTS").font(.caption.weight(.semibold)).tracking(1.2)
        Spacer()
        Text(model.results.count == 100 ? "100+" : "\(model.results.count)").font(.caption)
      }.foregroundStyle(.secondary).padding(14)
      if model.results.isEmpty {
        Text(
          model.query.isEmpty
            ? "Type a word to start." : "No matches. Try the headword or the beginning of a word."
        )
        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 14)
        Spacer()
      } else {
        if model.isSpellingSuggestion {
          Text("Did you mean?")
            .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        List(model.results, selection: $model.selection) { item in
          VStack(alignment: .leading, spacing: 4) {
            Text(item.title).font(.system(size: 17, design: .serif)).lineLimit(2)
            Text(item.source).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
          }.padding(.vertical, 5).tag(item.id)
        }.listStyle(.sidebar)
      }
    }.background(.quaternary.opacity(0.35))
  }

  @ViewBuilder private var detail: some View {
    if let entry = model.entry {
      let audioFolder = model.audioFolder
      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text(entry.summary.headword).font(.system(size: 31, weight: .semibold, design: .serif))
              .textSelection(.enabled)
            Text(entry.summary.source).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
          }
          HStack(spacing: 8) {
            ForEach(Accent.allCases) { accent in
              Button {
                audio.play(
                  id: entry.summary.audioID, source: entry.summary.source, accent: accent,
                  folder: audioFolder, text: entry.summary.headword)
              } label: {
                Label(accent.label, systemImage: "speaker.wave.2")
              }.controlSize(.small)
            }
            Spacer()
          }
          HStack {
            Text("\(entry.examples.count) examples")
            Spacer()
            Button("Refresh audio", action: model.refreshAudio).buttonStyle(.link)
          }.font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 24).padding(.vertical, 18)
        Divider()
        EntryWebView(
          entry: entry, audioFolder: audioFolder, matchedTerm: model.selection?.matchedTerm,
          play: model.playExample, follow: model.follow)
      }
    } else {
      VStack(spacing: 12) {
        Image(systemName: "text.book.closed").font(.system(size: 40)).foregroundStyle(.tertiary)
        Text("Look up a word. Hear it in context.").font(.title3).foregroundStyle(.secondary)
        Text("WISDOM · English–Japanese     ODE · English")
          .font(.callout).foregroundStyle(.tertiary)
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
