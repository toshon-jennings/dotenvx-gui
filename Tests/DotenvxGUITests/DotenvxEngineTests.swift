import Darwin
import Foundation
import XCTest

@testable import DotenvxGUI

final class DotenvxEngineTests: XCTestCase {
  private var home: URL!
  private var engine: DotenvxEngine!

  override func setUpWithError() throws {
    home = FileManager.default.temporaryDirectory
      .appendingPathComponent("dotenvx-gui-swift-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    engine = DotenvxEngine(homeURL: home)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  func testDiscoversOnlyRegularEnvironmentFiles() throws {
    let project = try makeProject()
    try "A=one\n".write(
      to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
    try "B=two\n".write(
      to: project.appendingPathComponent(".env.production"), atomically: true, encoding: .utf8)
    try "PRIVATE_KEY=x\n".write(
      to: project.appendingPathComponent(".env.keys"), atomically: true, encoding: .utf8)
    try "ignore\n".write(
      to: project.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: project.appendingPathComponent(".env.link"),
      withDestinationURL: project.appendingPathComponent(".env")
    )

    XCTAssertEqual(
      try engine.environmentFiles(in: project).map(\.lastPathComponent),
      [".env", ".env.production"]
    )
  }

  func testParsesPlaintextAndEncryptedValues() {
    let variables = engine.parse(
      """
      # comment
      DOTENV_PUBLIC_KEY=abc123
      PLAIN="hello world"
      SEALED=encrypted:abc123
      EMPTY=
      """)

    XCTAssertEqual(
      variables,
      [
        EnvVariable(key: "DOTENV_PUBLIC_KEY", value: "abc123", encrypted: false),
        EnvVariable(key: "PLAIN", value: "hello world", encrypted: false),
        EnvVariable(key: "SEALED", value: "encrypted:abc123", encrypted: true),
        EnvVariable(key: "EMPTY", value: "", encrypted: false),
      ])
    XCTAssertTrue(variables[0].isPublicKeyMetadata)
  }

  func testSetAndUnsetPreserveCommentsAndPermissions() throws {
    let project = try makeProject()
    let file = project.appendingPathComponent(".env")
    try "# keep me\nFIRST=one\n".write(to: file, atomically: true, encoding: .utf8)
    XCTAssertEqual(chmod(file.path, 0o640), 0)

    try engine.setValue(file: file, key: "FIRST", value: "two words")
    try engine.setValue(file: file, key: "SECOND", value: "literal$value")
    var content = try String(contentsOf: file, encoding: .utf8)
    XCTAssertTrue(content.contains("# keep me"))
    XCTAssertTrue(content.contains("FIRST=\"two words\""))
    XCTAssertTrue(content.contains("SECOND=\"literal\\$value\""))
    let permissions =
      try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o640)

    try engine.unsetValue(file: file, key: "FIRST")
    content = try String(contentsOf: file, encoding: .utf8)
    XCTAssertFalse(content.contains("FIRST="))
    XCTAssertTrue(content.contains("# keep me"))
    XCTAssertTrue(content.contains("SECOND="))
  }

  func testRejectsPathsOutsideConfiguredHomeAndDotenvKeys() throws {
    XCTAssertThrowsError(try engine.projectURL(FileManager.default.temporaryDirectory))
    let project = try makeProject()
    let keys = project.appendingPathComponent(".env.keys")
    try "PRIVATE_KEY=x".write(to: keys, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try engine.readEnvironmentFile(keys))
  }

  func testRecentProjectsAreCanonicalAndOwnerOnly() throws {
    let project = try makeProject()
    let projects = try engine.rememberProject(project)
    XCTAssertEqual(projects.first?.path, project.resolvingSymlinksInPath().path)

    let permissions =
      try FileManager.default.attributesOfItem(atPath: engine.recentFileURL.path)[.posixPermissions]
      as? NSNumber
    XCTAssertEqual(permissions?.intValue, 0o600)
    XCTAssertEqual(engine.loadRecentProjects(), projects)
  }

  private func makeProject() throws -> URL {
    let project = home.appendingPathComponent("project")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    return project
  }
}
