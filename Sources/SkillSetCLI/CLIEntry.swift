import Foundation

@main
struct SkillSetCLIEntry {
    static func main() {
        CLIInvocation.run(arguments: Array(CommandLine.arguments.dropFirst()))
    }
}
