import Foundation

// Fixed order; every suite lives in its own file next to the Core file it covers.
supportTests()
configTests()
shortcutTests()
schemaTests()
configStoreTests()
runtimeIssueTests()
configValidationTests()
tomlTests()
configDocumentDraftTests()
tapLogicTests()
trackpadSwipesTests()
engineTests()
capsMonitorTests()
hidutilCleanupTests()
debugLogFormatTests()
hidppTests()
thumbControllerTests()
secureInputTests()
statusLogicTests()
editorTests()
privilegesTests()
doctorTests()

for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
print("HyperMugCoreTests: \(checkCount) checks, \(failureCount) failures")
exit(failureCount == 0 ? 0 : 1)
