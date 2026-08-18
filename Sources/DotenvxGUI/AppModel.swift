import Foundation
import SwiftUI

struct LogEntry: Identifiable {
  let id = UUID()
  let date = Date()
  let message: String
  let kind: Kind

  enum Kind { case info, success, error }
}

@MainActor
final class AppModel: ObservableObject {
  @Published var currentProject: URL?
  @Published var files: [URL] = []
  @Published var selectedFile: URL?
  @Published var variables: [EnvVariable] = []
  @Published var recentProjects: [RecentProject] = []
  @Published var logs: [LogEntry] = []
  @Published var isBusy = false
  @Published var errorMessage: String?

  private let engine: DotenvxEngine

  init(engine: DotenvxEngine = DotenvxEngine()) {
    self.engine = engine
    self.recentProjects = engine.loadRecentProjects()
    log("dotenvx GUI ready. Open a project folder to begin.", kind: .info)
  }

  var canEdit: Bool { selectedFile != nil && !isBusy }
  var canRun: Bool { currentProject != nil && !isBusy }

  func openProject(_ url: URL) {
    do {
      let project = try engine.projectURL(url)
      let discovered = try engine.environmentFiles(in: project)
      currentProject = project
      files = discovered
      selectedFile = discovered.first
      variables = try discovered.first.map(engine.readEnvironmentFile) ?? []
      recentProjects = try engine.rememberProject(project)
      log("Opened \(project.lastPathComponent).", kind: .success)
      if discovered.isEmpty { log("No .env files found in this folder.", kind: .info) }
    } catch {
      report(error)
    }
  }

  func selectFile(_ url: URL) {
    do {
      selectedFile = url
      variables = try engine.readEnvironmentFile(url)
      log("Loaded \(url.lastPathComponent) (\(variables.count) variables).", kind: .info)
    } catch {
      report(error)
    }
  }

  func setValue(key: String, value: String) {
    guard let file = selectedFile else { return }
    do {
      try engine.setValue(file: file, key: key, value: value)
      try reloadSelectedFile()
      log("Saved \(key).", kind: .success)
    } catch {
      report(error)
    }
  }

  func deleteValue(key: String) {
    guard let file = selectedFile else { return }
    do {
      try engine.unsetValue(file: file, key: key)
      try reloadSelectedFile()
      log("Deleted \(key).", kind: .success)
    } catch {
      report(error)
    }
  }

  func encryptSelected() {
    guard let file = selectedFile else { return }
    perform("Encrypting \(file.lastPathComponent)…") {
      let result = try await self.engine.encrypt(file: file)
      try self.reloadSelectedFile()
      self.log(result.text.isEmpty ? "Encryption complete." : result.text, kind: .success)
    }
  }

  func decryptSelected() {
    guard let file = selectedFile else { return }
    perform("Decrypting \(file.lastPathComponent)…") {
      let result = try await self.engine.decrypt(file: file)
      try self.reloadSelectedFile()
      self.log(result.text.isEmpty ? "Decryption complete." : result.text, kind: .success)
    }
  }

  func run(_ command: String) {
    guard let project = currentProject else { return }
    perform("> dotenvx run -- \(command)") {
      let result = try await self.engine.run(command: command, in: project)
      self.log(
        result.text.isEmpty ? "Command completed with no output." : result.text, kind: .success)
    }
  }

  func clearLogs() {
    logs.removeAll()
  }

  private func perform(
    _ openingMessage: String, operation: @escaping @MainActor () async throws -> Void
  ) {
    guard !isBusy else { return }
    isBusy = true
    log(openingMessage, kind: .info)
    Task {
      defer { isBusy = false }
      do { try await operation() } catch { report(error) }
    }
  }

  private func reloadSelectedFile() throws {
    guard let file = selectedFile else { return }
    variables = try engine.readEnvironmentFile(file)
  }

  private func report(_ error: Error) {
    let message = error.localizedDescription
    errorMessage = message
    log(message, kind: .error)
  }

  private func log(_ message: String, kind: LogEntry.Kind) {
    logs.append(LogEntry(message: message, kind: kind))
  }
}
