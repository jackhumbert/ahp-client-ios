import Testing
@testable import AHPApp

/// The folder URI shapes the app meets: a single host, the deployed broker
/// (`file://<machine>/…`) and agent-host-broker's `ahp-file:` scheme.
struct FolderURITests {
    @Test func aLocalHost() {
        let uri = "file:///Users/me/repo"
        #expect(FolderURI.path(uri) == "/Users/me/repo")
        #expect(FolderURI.machine(uri) == nil)
        #expect(FolderURI.name(uri) == "repo")
        #expect(FolderURI.parent(uri) == "file:///Users/me")
        #expect(FolderURI.child(uri, "src") == "file:///Users/me/repo/src")
        #expect(FolderURI.parent("file:///") == nil)
    }

    @Test func theDeployedBrokerNamesTheMachineAsTheAuthority() {
        let uri = "file://my-mac-mini/Users/me/Github"
        #expect(FolderURI.path(uri) == "/Users/me/Github")
        #expect(FolderURI.machine(uri) == "my-mac-mini")
        #expect(FolderURI.child(uri, "other-project") == "file://my-mac-mini/Users/me/Github/other-project")
    }

    @Test func aWindowsDriveThroughTheBroker() {
        let uri = "file://studio/D:/work"
        #expect(FolderURI.path(uri) == "D:/work")
        #expect(FolderURI.machine(uri) == "studio")
        #expect(FolderURI.name(uri) == "work")
        #expect(FolderURI.parent("file://studio/D:") == nil)
    }

    @Test func ahpFileWalksFromMachinesIntoAMachinesRoot() {
        #expect(FolderURI.name(FolderURI.brokerRoot) == "Machines")
        #expect(FolderURI.parent(FolderURI.brokerRoot) == nil)
        let machine = FolderURI.child(FolderURI.brokerRoot, "mac-a")
        #expect(machine == "ahp-file:///mac-a")
        #expect(FolderURI.name(machine) == "mac-a")
        #expect(FolderURI.parent(machine) == FolderURI.brokerRoot)
        let project = FolderURI.child(machine, "projects")
        #expect(project == "ahp-file:///mac-a/projects")
        #expect(FolderURI.path(project) == "/projects")
        #expect(FolderURI.machine(project) == "mac-a")
        #expect(FolderURI.parent(project) == "ahp-file:///mac-a")
    }

    @Test func ahpFileOutsideTheRootNamesTheMachineAsTheAuthority() {
        let uri = "ahp-file://mac-a/etc/hosts"
        #expect(FolderURI.machine(uri) == "mac-a")
        #expect(FolderURI.path(uri) == "/etc/hosts")
    }
}
