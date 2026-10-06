import Foundation
import PrinboxCore

let invocation: Invocation
do {
    invocation = try CLIArguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch let error as UsageError {
    FileHandle.standardError.write(Data("prinbox: \(error.message)\n\(CLIArguments.usage)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("prinbox: \(error)\n".utf8))
    exit(2)
}
let code = await CLI.run(
    invocation, context: Composition.context(for: invocation),
    stdout: { FileHandle.standardOutput.write(Data($0.utf8)) },
    stderr: { FileHandle.standardError.write(Data($0.utf8)) },
    readLine: { Swift.readLine(strippingNewline: true) },
    makeContext: { Composition.context(for: invocation) })
exit(code)
