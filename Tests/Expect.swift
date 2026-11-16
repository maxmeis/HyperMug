import Foundation

/// Tiny assertion helpers; the suites run from `main.swift` and the exit code reports failures.
var checkCount = 0
var failureCount = 0

/// Temp dirs handed out by `makeTempDir()`; `main.swift` removes them before exiting.
var tempDirs: [URL] = []

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "",
            file: StaticString = #filePath, line: UInt = #line) {
    checkCount += 1
    if condition() { return }
    failureCount += 1
    report("FAIL \(file):\(line) \(message())")
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
    checkCount += 1
    if actual == expected { return }
    failureCount += 1
    let note = message()
    report("FAIL \(file):\(line) \(note.isEmpty ? "" : note + ": ")expected \(expected), got \(actual)")
}

/// A fresh, unique, empty directory under the system temp dir.
func makeTempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("hypermug-tests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    tempDirs.append(dir)
    return dir
}

private func report(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
