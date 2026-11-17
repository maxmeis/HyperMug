import Foundation
import HyperMugCore

@main
enum SchemaMain {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try Data(configSchemaJSON.utf8).write(to: directory.appendingPathComponent(AppIdentity.schemaFileName), options: .atomic)
    }
}
