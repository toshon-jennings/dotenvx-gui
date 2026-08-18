import AppKit
import SwiftUI

private enum Palette {
  static let desk = Color(red: 0.89, green: 0.85, blue: 0.76)
  static let paper = Color(red: 0.97, green: 0.95, blue: 0.89)
  static let ink = Color(red: 0.15, green: 0.14, blue: 0.12)
  static let rule = Color(red: 0.57, green: 0.52, blue: 0.43)
  static let wax = Color(red: 0.18, green: 0.36, blue: 0.26)
  static let caution = Color(red: 0.54, green: 0.35, blue: 0.03)
  static let redline = Color(red: 0.64, green: 0.17, blue: 0.12)
  static let lamplightDesk = Color(red: 0.16, green: 0.13, blue: 0.10)
  static let lamplightPaper = Color(red: 0.23, green: 0.19, blue: 0.14)
  static let lamplightInk = Color(red: 0.91, green: 0.85, blue: 0.72)
}

struct ContentView: View {
  @ObservedObject var model: AppModel
  @AppStorage("dotenvx-gui-theme-native") private var lamplight = false
  @State private var showingAdd = false
  @State private var showingRun = false
  @State private var showingHelp = false
  @State private var confirmingDecrypt = false
  @State private var outputExpanded = false

  private var desk: Color { lamplight ? Palette.lamplightDesk : Palette.desk }
  private var paper: Color { lamplight ? Palette.lamplightPaper : Palette.paper }
  private var ink: Color { lamplight ? Palette.lamplightInk : Palette.ink }

  var body: some View {
    HSplitView {
      sidebar
        .frame(minWidth: 230, idealWidth: 260, maxWidth: 310)
      mainDocument
        .frame(minWidth: 650)
    }
    .background(desk)
    .preferredColorScheme(lamplight ? .dark : .light)
    .sheet(isPresented: $showingAdd) {
      AddVariableSheet { key, value in model.setValue(key: key, value: value) }
        .environment(\.colorScheme, lamplight ? .dark : .light)
    }
    .sheet(isPresented: $showingRun) {
      RunCommandSheet {
        model.run($0)
        outputExpanded = true
      }
      .environment(\.colorScheme, lamplight ? .dark : .light)
    }
    .sheet(isPresented: $showingHelp) {
      GuideView()
        .environment(\.colorScheme, lamplight ? .dark : .light)
    }
    .alert(
      "Decrypt \(model.selectedFile?.lastPathComponent ?? "file")?", isPresented: $confirmingDecrypt
    ) {
      Button("Cancel", role: .cancel) {}
      Button("Decrypt", role: .destructive) { model.decryptSelected() }
    } message: {
      Text("This writes secret values to disk as plaintext until you encrypt the file again.")
    }
    .alert(
      "Operation failed",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
    .onReceive(NotificationCenter.default.publisher(for: .showDotenvxGuide)) { _ in
      showingHelp = true
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        Image(systemName: "checkmark.seal.fill")
          .foregroundStyle(Palette.wax)
          .font(.title2)
        Text("dotenvx")
          .font(.system(.title3, design: .serif, weight: .semibold))
        Text("GUI")
          .font(.system(.caption2, design: .monospaced, weight: .semibold))
          .padding(.horizontal, 5)
          .padding(.vertical, 2)
          .overlay(Rectangle().stroke(Palette.rule.opacity(0.7)))
      }
      .foregroundStyle(ink)
      .padding(20)

      Divider().overlay(Palette.rule.opacity(0.5))

      VStack(alignment: .leading, spacing: 12) {
        Button(action: chooseFolder) {
          Label("Open folder", systemImage: "folder")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ManifestButtonStyle(primary: true))
        .keyboardShortcut("o", modifiers: .command)

        if let project = model.currentProject {
          VStack(alignment: .leading, spacing: 3) {
            Text(project.lastPathComponent)
              .fontWeight(.semibold)
            Text(project.path)
              .font(.caption2.monospaced())
              .lineLimit(2)
              .foregroundStyle(ink.opacity(0.65))
          }
        }
      }
      .padding(20)

      Text("RECENT PROJECTS")
        .font(.caption2.monospaced().weight(.semibold))
        .tracking(1.5)
        .foregroundStyle(ink.opacity(0.65))
        .padding(.horizontal, 20)
        .padding(.top, 8)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          if model.recentProjects.isEmpty {
            Text("No recent projects")
              .font(.caption)
              .foregroundStyle(ink.opacity(0.55))
              .padding(.vertical, 12)
          }
          ForEach(model.recentProjects) { project in
            Button {
              model.openProject(URL(fileURLWithPath: project.path))
            } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(project.name).fontWeight(.semibold)
                Text(project.path)
                  .font(.caption2.monospaced())
                  .lineLimit(1)
                  .foregroundStyle(ink.opacity(0.58))
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 20)
      }

      Spacer()
      Text("NATIVE PREVIEW")
        .font(.caption2.monospaced())
        .foregroundStyle(ink.opacity(0.5))
        .padding(20)
    }
    .background(desk)
    .foregroundStyle(ink)
  }

  private var mainDocument: some View {
    VStack(spacing: 0) {
      toolbar
      fileTabs
      Divider().overlay(Palette.rule.opacity(0.5))

      Group {
        if model.currentProject == nil {
          emptyState
        } else if model.selectedFile == nil {
          noFilesState
        } else {
          environmentDocument
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      outputPanel
    }
    .background(paper)
    .foregroundStyle(ink)
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Button("Encrypt file") { model.encryptSelected() }
        .buttonStyle(ManifestButtonStyle(primary: true))
        .disabled(!model.canEdit)
        .keyboardShortcut("e", modifiers: .command)
      Button("Decrypt file") { confirmingDecrypt = true }
        .buttonStyle(ManifestButtonStyle(tint: Palette.caution))
        .disabled(!model.canEdit)
        .keyboardShortcut("d", modifiers: .command)
      Button("Add variable") { showingAdd = true }
        .buttonStyle(ManifestButtonStyle())
        .disabled(!model.canEdit)
      Button("Run") { showingRun = true }
        .buttonStyle(ManifestButtonStyle())
        .disabled(!model.canRun)

      Spacer()

      if model.isBusy { ProgressView().controlSize(.small) }
      Button(lamplight ? "Daylight" : "Lamplight") { lamplight.toggle() }
        .buttonStyle(ManifestButtonStyle())
      Button("Help") { showingHelp = true }
        .buttonStyle(ManifestButtonStyle())
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(desk.opacity(lamplight ? 0.75 : 0.55))
  }

  private var fileTabs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        ForEach(model.files, id: \.path) { file in
          Button(file.lastPathComponent) { model.selectFile(file) }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .monospaced, weight: .semibold))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(model.selectedFile == file ? paper : desk.opacity(0.48))
            .overlay(alignment: .bottom) {
              Rectangle()
                .fill(model.selectedFile == file ? Palette.wax : .clear)
                .frame(height: 2)
            }
        }
      }
    }
    .frame(height: model.files.isEmpty ? 0 : 38)
  }

  private var emptyState: some View {
    VStack(spacing: 14) {
      Image(systemName: "seal")
        .font(.system(size: 42, weight: .light))
        .foregroundStyle(Palette.rule)
      Text("No project open")
        .font(.system(.title, design: .serif, weight: .semibold))
      Text("Choose a local folder to read and seal the environment files inside it.")
        .foregroundStyle(ink.opacity(0.7))
      HStack {
        Button("Open folder") { chooseFolder() }
          .buttonStyle(ManifestButtonStyle(primary: true))
        Button("How dotenvx works") { showingHelp = true }
          .buttonStyle(ManifestButtonStyle())
      }
    }
    .padding(44)
    .overlay(
      Rectangle().stroke(Palette.rule.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4])))
  }

  private var noFilesState: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.badge.ellipsis")
        .font(.largeTitle)
        .foregroundStyle(Palette.caution)
      Text("No environment files")
        .font(.system(.title2, design: .serif, weight: .semibold))
      Text("This folder does not contain a regular .env file.")
        .foregroundStyle(ink.opacity(0.7))
      Button("Run a command anyway") { showingRun = true }
        .buttonStyle(ManifestButtonStyle())
    }
  }

  private var environmentDocument: some View {
    VStack(spacing: 0) {
      documentHeader
      Divider().overlay(Palette.rule.opacity(0.4))
      variableHeader
      ScrollView {
        LazyVStack(spacing: 0) {
          if model.variables.isEmpty {
            Text("No variables in this file")
              .font(.callout.monospaced())
              .foregroundStyle(ink.opacity(0.58))
              .frame(maxWidth: .infinity)
              .padding(38)
          }
          ForEach(model.variables) { variable in
            VariableRow(
              variable: variable,
              fileName: model.selectedFile?.lastPathComponent ?? "the selected file",
              ink: ink,
              onSave: { model.setValue(key: variable.key, value: $0) },
              onDelete: { model.deleteValue(key: variable.key) }
            )
            Divider().overlay(Palette.rule.opacity(0.28))
          }
        }
      }
    }
  }

  private var documentHeader: some View {
    let secretVariables = model.variables.filter { !$0.isPublicKeyMetadata }
    let encryptedCount = secretVariables.filter(\.encrypted).count
    let sealed = !secretVariables.isEmpty && encryptedCount == secretVariables.count
    return HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("ENVIRONMENT FILE")
          .font(.caption2.monospaced().weight(.semibold))
          .tracking(1.6)
          .foregroundStyle(ink.opacity(0.58))
        Text(model.selectedFile?.lastPathComponent ?? "")
          .font(.system(.largeTitle, design: .serif, weight: .semibold))
      }
      Spacer()
      Image(systemName: sealed ? "checkmark.seal.fill" : "seal")
        .font(.system(size: 38))
        .foregroundStyle(sealed ? Palette.wax : Palette.caution)
      VStack(alignment: .leading, spacing: 2) {
        Text(secretVariables.isEmpty ? "Empty" : sealed ? "Encrypted" : "Plaintext")
          .font(.headline.monospaced())
        Text("\(encryptedCount) of \(secretVariables.count) secret values encrypted")
          .font(.caption.monospaced())
          .foregroundStyle(ink.opacity(0.62))
      }
    }
    .padding(22)
  }

  private var variableHeader: some View {
    HStack(spacing: 14) {
      Text("KEY").frame(width: 180, alignment: .leading)
      Text("VALUE").frame(maxWidth: .infinity, alignment: .leading)
      Text("STATUS").frame(width: 110, alignment: .leading)
      Text("ACTIONS").frame(width: 160, alignment: .trailing)
    }
    .font(.caption2.monospaced().weight(.semibold))
    .tracking(1.2)
    .foregroundStyle(ink.opacity(0.6))
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(desk.opacity(0.35))
  }

  private var outputPanel: some View {
    VStack(spacing: 0) {
      Divider().overlay(Palette.rule.opacity(0.55))
      HStack {
        Text("OUTPUT").font(.caption2.monospaced().weight(.semibold)).tracking(1.4)
        Spacer()
        Button(outputExpanded ? "Hide" : "Show") { outputExpanded.toggle() }
          .buttonStyle(.plain)
        Button("Clear") { model.clearLogs() }
          .buttonStyle(.plain)
      }
      .padding(.horizontal, 18)
      .frame(height: 34)

      if outputExpanded {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 5) {
            ForEach(model.logs) { entry in
              HStack(alignment: .top, spacing: 8) {
                Text(entry.date, style: .time)
                  .foregroundStyle(ink.opacity(0.48))
                Text(entry.message)
                  .foregroundStyle(logColor(entry.kind))
                  .textSelection(.enabled)
              }
              .font(.caption.monospaced())
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
        }
        .frame(height: 145)
        .background(Color.black.opacity(lamplight ? 0.15 : 0.035))
      }
    }
  }

  private func logColor(_ kind: LogEntry.Kind) -> Color {
    switch kind {
    case .info: ink.opacity(0.8)
    case .success: Palette.wax
    case .error: Palette.redline
    }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.title = "Select a project folder"
    panel.prompt = "Open"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    if panel.runModal() == .OK, let url = panel.url { model.openProject(url) }
  }
}

private struct VariableRow: View {
  let variable: EnvVariable
  let fileName: String
  let ink: Color
  let onSave: (String) -> Void
  let onDelete: () -> Void
  @State private var revealed = false
  @State private var editing = false
  @State private var draft = ""
  @State private var confirmingDelete = false

  var body: some View {
    HStack(spacing: 14) {
      Text(variable.key)
        .fontWeight(.semibold)
        .frame(width: 180, alignment: .leading)

      valueEditor
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(
        variable.isPublicKeyMetadata
          ? "Public key" : variable.encrypted ? "Encrypted" : "Unencrypted"
      )
      .font(.caption.monospaced().weight(.semibold))
      .foregroundStyle(
        variable.isPublicKeyMetadata
          ? ink.opacity(0.68) : variable.encrypted ? Palette.wax : Palette.caution
      )
      .frame(width: 110, alignment: .leading)

      HStack(spacing: 10) {
        if editing {
          Button("Save", action: save)
          Button("Cancel") { editing = false }
        } else {
          Button(revealed ? "Hide" : "Show") { revealed.toggle() }
          Button("Edit") {
            draft = variable.value
            editing = true
          }
          Button("Delete", role: .destructive) { confirmingDelete = true }
        }
      }
      .buttonStyle(.plain)
      .font(.caption.monospaced().weight(.medium))
      .frame(width: 160, alignment: .trailing)
    }
    .font(.system(.body, design: .monospaced))
    .foregroundStyle(ink)
    .padding(.horizontal, 20)
    .padding(.vertical, 13)
    .alert("Delete \(variable.key)?", isPresented: $confirmingDelete) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive, action: onDelete)
    } message: {
      Text("This removes the variable from \(fileName).")
    }
  }

  private func save() {
    onSave(draft)
    editing = false
  }

  @ViewBuilder
  private var valueEditor: some View {
    if editing {
      SecureField("Value", text: $draft)
        .textFieldStyle(.plain)
        .onSubmit(save)
    } else if revealed {
      Text(variable.value).textSelection(.enabled)
    } else {
      Text("••••••••")
    }
  }
}

private struct ManifestButtonStyle: ButtonStyle {
  var primary = false
  var tint: Color = Palette.ink

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(.caption, design: .monospaced, weight: .semibold))
      .textCase(.uppercase)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .foregroundStyle(primary ? Color.white : tint)
      .background(primary ? Palette.wax : Color.clear)
      .overlay(Rectangle().stroke(primary ? Palette.wax : tint.opacity(0.55)))
      .opacity(configuration.isPressed ? 0.66 : 1)
  }
}

private struct AddVariableSheet: View {
  let onAdd: (String, String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var key = ""
  @State private var value = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Add variable").font(.system(.title2, design: .serif, weight: .semibold))
      TextField("KEY_NAME", text: $key).font(.body.monospaced())
      SecureField("Value", text: $value).font(.body.monospaced())
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Add") {
          onAdd(key.trimmingCharacters(in: .whitespaces), value)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 430)
  }
}

private struct RunCommandSheet: View {
  let onRun: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var command = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Run with dotenvx").font(.system(.title2, design: .serif, weight: .semibold))
      Text(
        "dotenvx decrypts the selected project's values in memory and injects them into the command process."
      )
      .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Text("dotenvx run --").font(.body.monospaced()).foregroundStyle(.secondary)
        TextField("npm run dev", text: $command).font(.body.monospaced())
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Run") {
          onRun(command.trimmingCharacters(in: .whitespaces))
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 560)
  }
}

private struct GuideView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.wax)
        Text("dotenvx guide").font(.system(.title2, design: .serif, weight: .semibold))
        Spacer()
        Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      .padding(20)
      Divider()

      TabView {
        GuideSection(
          title: "Work with an environment file",
          lead:
            "dotenvx keeps encrypted values in normal .env files and stores private keys separately.",
          steps: [
            "Open a project and choose the environment file you want to edit.",
            "Values stay masked until you reveal them.",
            "Encrypt before committing and keep .env.keys out of Git.",
          ]
        ).tabItem { Text("Start") }

        GuideSection(
          title: "Ship an encrypted environment",
          lead:
            "Your repository gets the encrypted file. Your deployment platform gets the matching private key.",
          steps: [
            "Encrypt the selected file before staging it.",
            "Store the matching private key in your deployment platform.",
            "Start the application through dotenvx run.",
          ]
        ).tabItem { Text("Ship") }

        GuideSection(
          title: "Related commands",
          lead: "Use these when you prefer the terminal.",
          steps: [
            "dotenvx get KEY",
            "dotenvx set KEY value",
            "dotenvx encrypt -f .env.production",
            "dotenvx run -- npm start",
          ]
        ).tabItem { Text("Commands") }
      }
      .padding(20)
    }
    .frame(width: 700, height: 500)
  }
}

private struct GuideSection: View {
  let title: String
  let lead: String
  let steps: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(title).font(.system(.title, design: .serif, weight: .semibold))
      Text(lead).font(.title3).foregroundStyle(.secondary)
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .top, spacing: 12) {
          Text("\(index + 1)")
            .font(.caption.monospaced().weight(.bold))
            .frame(width: 24, height: 24)
            .background(Palette.wax)
            .foregroundStyle(.white)
            .clipShape(Circle())
          Text(step).font(.body.monospaced())
        }
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(18)
  }
}
