import Darwin
import Foundation

struct EnvVariable: Identifiable, Equatable, Sendable {
  var id: String { key }
  var isPublicKeyMetadata: Bool {
    key == "DOTENV_PUBLIC_KEY" || key.hasPrefix("DOTENV_PUBLIC_KEY_")
  }
  let key: String
  let value: String
  let encrypted: Bool
}

struct ProcessOutput: Sendable {
  let text: String
}

struct RecentProject: Codable, Identifiable, Equatable, Sendable {
  var id: String { path }
  let path: String
  let name: String
  let lastOpened: String?
}

private struct RecentProjectStore: Codable {
  let projects: [RecentProject]
}

enum DotenvxError: LocalizedError {
  case invalidPath(String)
  case invalidKey
  case executableMissing
  case commandFailed(String)
  case outputLimit

  var errorDescription: String? {
    switch self {
    case .invalidPath(let message): message
    case .invalidKey: "Key must be a valid environment variable name, such as MY_KEY."
    case .executableMissing:
      "dotenvx is not installed. Install it with Homebrew or place it in ~/.dotenvx/bin."
    case .commandFailed(let message): message.isEmpty ? "The dotenvx command failed." : message
    case .outputLimit: "Command output exceeded the 1 MiB limit."
    }
  }
}

struct DotenvxEngine: Sendable {
  static let maximumOutputBytes = 1_048_576

  let homeURL: URL
  let recentFileURL: URL
  private var fileManager: FileManager { .default }

  init(homeURL: URL = FileManager.default.homeDirectoryForCurrentUser) {
    let resolvedHome = homeURL.standardizedFileURL.resolvingSymlinksInPath()
    self.homeURL = resolvedHome
    self.recentFileURL = resolvedHome.appendingPathComponent(".dotenvx-gui.json")
  }

  func projectURL(_ url: URL) throws -> URL {
    let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
    guard isInsideHome(resolved) else {
      throw DotenvxError.invalidPath("Project folders must remain inside your home directory.")
    }
    let values = try resolved.resourceValues(forKeys: [.isDirectoryKey])
    guard values.isDirectory == true else {
      throw DotenvxError.invalidPath("The selected path is not a directory.")
    }
    return resolved
  }

  func environmentFiles(in project: URL) throws -> [URL] {
    let directory = try projectURL(project)
    return try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
      options: []
    )
    .filter { url in
      let name = url.lastPathComponent
      guard name.hasPrefix(".env"), name != ".env.keys" else { return false }
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      else {
        return false
      }
      return values.isRegularFile == true && values.isSymbolicLink != true
    }
    .sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  func readEnvironmentFile(_ url: URL) throws -> [EnvVariable] {
    let file = try environmentFileURL(url)
    let content = try String(contentsOf: file, encoding: .utf8)
    return parse(content)
  }

  func parse(_ content: String) -> [EnvVariable] {
    content.split(whereSeparator: { $0.isNewline }).compactMap { rawLine in
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
        return nil
      }
      let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
      let encoded = String(line[line.index(after: separator)...]).trimmingCharacters(
        in: .whitespaces)
      let value = decodeValue(encoded)
      return EnvVariable(key: key, value: value, encrypted: value.hasPrefix("encrypted:"))
    }
  }

  func setValue(file url: URL, key: String, value: String) throws {
    guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
      throw DotenvxError.invalidKey
    }
    let file = try environmentFileURL(url)
    let original = try String(contentsOf: file, encoding: .utf8)
    var lines = original.components(separatedBy: "\n")
    let replacement = "\(key)=\(encodeValue(value))"
    var replaced = false

    for index in lines.indices {
      let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=")
      else {
        continue
      }
      if trimmed[..<separator].trimmingCharacters(in: .whitespaces) == key {
        lines[index] = replacement
        replaced = true
        break
      }
    }

    if !replaced {
      if lines.last == "" {
        lines.insert(replacement, at: lines.count - 1)
      } else {
        lines.append(replacement)
      }
    }
    try atomicWrite(lines.joined(separator: "\n"), to: file)
  }

  func unsetValue(file url: URL, key: String) throws {
    guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else {
      throw DotenvxError.invalidKey
    }
    let file = try environmentFileURL(url)
    let original = try String(contentsOf: file, encoding: .utf8)
    let lines = original.components(separatedBy: "\n").filter { line in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=")
      else {
        return true
      }
      return trimmed[..<separator].trimmingCharacters(in: .whitespaces) != key
    }
    try atomicWrite(lines.joined(separator: "\n"), to: file)
  }

  func encrypt(file url: URL) async throws -> ProcessOutput {
    let file = try environmentFileURL(url)
    return try await runDotenvx(
      ["encrypt", "-f", file.path], directory: file.deletingLastPathComponent())
  }

  func decrypt(file url: URL) async throws -> ProcessOutput {
    let file = try environmentFileURL(url)
    return try await runDotenvx(
      ["decrypt", "-f", file.path], directory: file.deletingLastPathComponent())
  }

  func run(command: String, in project: URL) async throws -> ProcessOutput {
    let directory = try projectURL(project)
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    return try await runDotenvx(["run", "--", shell, "-lc", command], directory: directory)
  }

  func loadRecentProjects() -> [RecentProject] {
    guard let data = try? Data(contentsOf: recentFileURL),
      let store = try? JSONDecoder().decode(RecentProjectStore.self, from: data)
    else {
      return []
    }
    return store.projects
  }

  @discardableResult
  func rememberProject(_ url: URL) throws -> [RecentProject] {
    let project = try projectURL(url)
    var projects = loadRecentProjects().filter { $0.path != project.path }
    projects.insert(
      RecentProject(
        path: project.path,
        name: project.lastPathComponent.isEmpty ? project.path : project.lastPathComponent,
        lastOpened: ISO8601DateFormatter().string(from: Date())
      ),
      at: 0
    )
    let limited = Array(projects.prefix(10))
    let data = try JSONEncoder.pretty.encode(RecentProjectStore(projects: limited))
    try atomicWrite(data, to: recentFileURL, defaultMode: 0o600)
    return limited
  }

  private func environmentFileURL(_ url: URL) throws -> URL {
    let lexical = url.standardizedFileURL
    let lexicalValues = try lexical.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard lexicalValues.isSymbolicLink != true else {
      throw DotenvxError.invalidPath("Symbolic-link environment files are not supported.")
    }
    let resolved = lexical.resolvingSymlinksInPath()
    guard isInsideHome(resolved) else {
      throw DotenvxError.invalidPath("Environment files must remain inside your home directory.")
    }
    let name = resolved.lastPathComponent
    guard name.hasPrefix(".env"), name != ".env.keys" else {
      throw DotenvxError.invalidPath("Only regular .env files are supported.")
    }
    let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
    guard values.isRegularFile == true else {
      throw DotenvxError.invalidPath("The environment file is not a regular file.")
    }
    return resolved
  }

  private func isInsideHome(_ url: URL) -> Bool {
    url.path == homeURL.path || url.path.hasPrefix(homeURL.path + "/")
  }

  private func runDotenvx(_ arguments: [String], directory: URL) async throws -> ProcessOutput {
    let executable = try dotenvxExecutable()
    return try await Task.detached(priority: .userInitiated) {
      let process = Process()
      let pipe = Pipe()
      process.executableURL = executable
      process.arguments = arguments
      process.currentDirectoryURL = directory
      process.standardOutput = pipe
      process.standardError = pipe

      var environment = ProcessInfo.processInfo.environment
      let additional = [
        "/opt/homebrew/bin", "/usr/local/bin",
        self.homeURL.appendingPathComponent(".dotenvx/bin").path,
      ]
      environment["PATH"] = (additional + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(
        separator: ":")
      process.environment = environment

      try process.run()
      var data = Data()
      while true {
        let chunk = pipe.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        data.append(chunk)
        if data.count > Self.maximumOutputBytes {
          process.terminate()
          throw DotenvxError.outputLimit
        }
      }
      process.waitUntilExit()
      let text = String(decoding: data, as: UTF8.self).trimmingCharacters(
        in: .whitespacesAndNewlines)
      guard process.terminationStatus == 0 else { throw DotenvxError.commandFailed(text) }
      return ProcessOutput(text: text)
    }.value
  }

  private func dotenvxExecutable() throws -> URL {
    var candidates: [String] = []
    if let override = ProcessInfo.processInfo.environment["DOTENVX_GUI_DOTENVX_PATH"] {
      candidates.append(override)
    }
    candidates += [
      "/opt/homebrew/bin/dotenvx",
      "/usr/local/bin/dotenvx",
      homeURL.appendingPathComponent(".dotenvx/bin/dotenvx").path,
    ]
    guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
      throw DotenvxError.executableMissing
    }
    return URL(fileURLWithPath: path)
  }

  private func decodeValue(_ encoded: String) -> String {
    guard encoded.count >= 2 else { return encoded }
    if encoded.first == "\"", encoded.last == "\"" {
      return String(encoded.dropFirst().dropLast())
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\r", with: "\r")
        .replacingOccurrences(of: "\\t", with: "\t")
        .replacingOccurrences(of: "\\\"", with: "\"")
        .replacingOccurrences(of: "\\\\", with: "\\")
    }
    if encoded.first == "'", encoded.last == "'" {
      return String(encoded.dropFirst().dropLast())
    }
    return encoded
  }

  private func encodeValue(_ value: String) -> String {
    if !value.isEmpty,
      value.range(of: "^[A-Za-z0-9_./:@%+,-]+$", options: .regularExpression) != nil
    {
      return value
    }
    return "\""
      + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "$", with: "\\$")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\t", with: "\\t") + "\""
  }

  private func atomicWrite(_ content: String, to url: URL, defaultMode: mode_t = 0o600) throws {
    try atomicWrite(Data(content.utf8), to: url, defaultMode: defaultMode)
  }

  private func atomicWrite(_ data: Data, to url: URL, defaultMode: mode_t) throws {
    let mode: mode_t
    if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
      let permissions = attributes[.posixPermissions] as? NSNumber
    {
      mode = mode_t(permissions.uint16Value)
    } else {
      mode = defaultMode
    }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".dotenvx-gui-\(UUID().uuidString).tmp")
    defer { try? fileManager.removeItem(at: temporary) }
    try data.write(to: temporary)
    guard chmod(temporary.path, mode) == 0 else { throw POSIXError(.EACCES) }
    guard rename(temporary.path, url.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}

extension JSONEncoder {
  fileprivate static var pretty: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}
