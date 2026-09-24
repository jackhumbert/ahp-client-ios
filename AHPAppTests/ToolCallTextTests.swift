import Testing
@testable import AHPApp

/// A card shows the host's message and the command it ran; when the message
/// is just the command again, only one of them should show.
struct ToolCallTextTests {
    @Test func aMessageThatIsTheTruncatedCommandRepeatsIt() {
        let command = "$ powershell -NoProfile -Command \"Get-CimInstance Win32_Process -Filter \\\"ParentProcessId=28500\\\" | Select-Object ProcessId\""
        #expect(ToolCallText.repeats(
            "powershell -NoProfile -Command \"Get-CimInstance Win32_Process -Filter \\\"ParentProcessId=28500\\\" | Sel…",
            summary: command, displayName: "Run command"))
    }

    @Test func aMessageAfterTheDisplayNameRepeatsIt() {
        #expect(ToolCallText.repeats("Run command: git ls-files | wc -l", summary: "$ git ls-files | wc -l", displayName: "Run command"))
    }

    @Test func aDescriptionIsKept() {
        #expect(!ToolCallText.repeats("Count tracked files", summary: "$ git ls-files | wc -l", displayName: "Run command"))
        #expect(!ToolCallText.repeats("Read file: a.py", summary: "/x/a.py", displayName: "Read file"))
    }

    @Test func noSummaryKeepsTheMessage() {
        #expect(!ToolCallText.repeats("Running Echo Tool", summary: nil, displayName: "Echo Tool"))
    }
}
