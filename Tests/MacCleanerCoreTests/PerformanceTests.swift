import Foundation
import Testing
@testable import MacCleanerCore

/// Only the user's own non-Apple agents with a readable Label get a switch.
@Test func launchAgentScopes() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "mac-cleaner-perf-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    func plist(_ path: String, _ dict: [String: Any]) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: url)
    }
    try plist("home/Library/LaunchAgents/com.foo.agent.plist", ["Label": "com.foo.agent", "ProgramArguments": ["/opt/foo/bin", "--x"]])
    try plist("home/Library/LaunchAgents/com.apple.thing.plist", ["Label": "com.apple.thing", "Program": "/usr/bin/true"])
    try plist("home/Library/LaunchAgents/nolabel.plist", ["Program": "/usr/bin/true"])
    try plist("sys/Library/LaunchAgents/us.zoom.updater.plist", ["Label": "us.zoom.updater"])
    try plist("sys/Library/LaunchDaemons/com.docker.vmnetd.plist", ["Label": "com.docker.vmnetd"])

    let agents = launchAgents(home: root.appending(path: "home"), systemRoot: root.appending(path: "sys"))
    let byLabel = Dictionary(agents.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })

    #expect(byLabel["com.foo.agent"]?.scope == .user)
    #expect(byLabel["com.foo.agent"]?.isSwitchable == true)
    #expect(byLabel["com.foo.agent"]?.program == "/opt/foo/bin")
    #expect(byLabel["com.apple.thing"]?.isSwitchable == false)
    #expect(byLabel["nolabel"]?.isSwitchable == false)
    #expect(byLabel["us.zoom.updater"]?.scope == .allUsers)
    #expect(byLabel["us.zoom.updater"]?.isSwitchable == false)
    #expect(byLabel["com.docker.vmnetd"]?.scope == .daemon)
    #expect(byLabel["com.docker.vmnetd"]?.isSwitchable == false)
}

@Test func parsesDisabled() {
    let old = """
    \tdisabled services = {
    \t\t"com.foo.agent" => disabled
    \t\t"com.bar.agent" => enabled
    \t}
    """
    let new = """
    disabled services = {
    \t"com.foo.agent" => true
    \t"com.bar.agent" => false
    }
    login item associations = {
    \t"com.baz.helper" => true
    }
    """
    #expect(parseDisabled(old) == ["com.foo.agent"])
    // Only the "disabled services" block counts; other blocks reuse the same line shape.
    #expect(parseDisabled(new) == ["com.foo.agent"])
    #expect(parseDisabled("") == [])
}

@Test func parsesLoaded() {
    let list = """
    PID\tStatus\tLabel
    951\t0\tcom.foo.agent
    -\t0\tcom.bar.agent
    -\t-9\tcom.baz.agent
    """
    let loaded = parseLoaded(list)
    #expect(loaded["com.foo.agent"] == true)
    #expect(loaded["com.bar.agent"] == false)
    #expect(loaded["com.baz.agent"] == false)
    #expect(loaded["Label"] == nil)
    #expect(loaded["com.gone"] == nil)
}

let btmFixture = """
========================
 Records for UID 502 : AAAA
========================

 Items:

 #1:
                 UUID: 1
                 Name: Someone Else
                 Type: app (0x2)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 2.com.other.app
                  URL: /Applications/Other.app

========================
 Records for UID 501 : BBBB
========================

 ServiceManagement migrated: true

 Items:

 #1:
                 UUID: 2
                 Name: Rectangle
       Developer Name: Ryan Hanson
                 Type: app (0x2)
                Flags: [  ] (0)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 2.com.knollsoft.Rectangle
                  URL: /Applications/Rectangle.app
    Bundle Identifier: com.knollsoft.Rectangle

 #2:
                 UUID: 3
                 Name: Blender
                 Type: app (0x2)
          Disposition: [disabled, allowed, notified] (0xa)
           Identifier: 2.org.blenderfoundation.blender
                  URL: /Applications/Blender.app

 #3:
                 UUID: 4
                 Name: ChatGPT
                 Type: app (0x2)
          Disposition: [disabled, disallowed, not notified] (0)
           Identifier: 2.com.openai.chat
                  URL: /Applications/ChatGPT.app

 #4:
                 UUID: 5
                 Name: ChatGPTHelper
                 Type: agent (0x8)
          Disposition: [enabled, disallowed, notified] (0x9)
           Identifier: 8.com.openai.chat-helper
                  URL: Contents/Library/LaunchAgents/com.openai.chat-helper.plist
    Parent Identifier: 2.com.openai.chat

 #5:
                 UUID: 6
                 Name: DockerHelper
                 Type: login item (0x4)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 4.com.docker.helper
                  URL: Contents/Library/LoginItems/DockerHelper.app
    Parent Identifier: 2.com.docker.docker

 #6:
                 UUID: 7
                 Name: GoogleUpdater
                 Type: legacy agent (0x10008)
                Flags: [ legacy ] (0x1)
          Disposition: [enabled, disallowed, notified] (0x9)
           Identifier: 8.com.google.GoogleUpdater.wake
                  URL: /Users/501/Library/LaunchAgents/com.google.GoogleUpdater.wake.plist

 #7:
                 UUID: 8
                 Name: steamclean
                 Type: legacy agent (0x10008)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 8.com.valvesoftware.steamclean

 #8:
                 UUID: 9
                 Name: thumbnailer.appex
                 Type: quicklook (0x800)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 2048.org.blenderfoundation.blender.thumbnailer

========================
 Records for UID 0 : CCCC
========================

 #1:
                 UUID: 10
                 Name: Root Thing
                 Type: app (0x2)
          Disposition: [enabled, allowed, notified] (0xb)
           Identifier: 2.com.root.thing
"""

@Test func parsesBTM() {
    let items = parseBTM(btmFixture, uid: 501)
    #expect(items.map(\.name) == ["ChatGPTHelper", "DockerHelper", "Rectangle"])

    let rectangle = items.first { $0.name == "Rectangle" }
    #expect(rectangle?.kind == .opensAtLogin)
    #expect(rectangle?.allowed == true)
    #expect(rectangle?.appPath == "/Applications/Rectangle.app")

    let helper = items.first { $0.name == "ChatGPTHelper" }
    #expect(helper?.kind == .agent)
    #expect(helper?.allowed == false)
    #expect(helper?.label == "com.openai.chat-helper")
    #expect(helper?.parentName == "ChatGPT")
    #expect(helper?.appPath == "/Applications/ChatGPT.app")

    // Docker's own app record isn't in this fixture: no parent name, no path to guess.
    let docker = items.first { $0.name == "DockerHelper" }
    #expect(docker?.kind == .loginItem)
    #expect(docker?.parentName == nil)
    #expect(docker?.appPath == nil)

    #expect(legacyDisallowed(btmFixture, uid: 501) == ["com.google.GoogleUpdater.wake"])
    #expect(parseBTM("garbage", uid: 501).isEmpty)
}

@Test func toggleCommands() {
    let plist = URL(filePath: "/Users/me/Library/LaunchAgents/com.foo.agent.plist")
    #expect(MacCleanerCore.toggleCommands(label: "com.foo.agent", plist: plist, uid: 501, enable: false) == [
        ["launchctl", "disable", "gui/501/com.foo.agent"],
        ["launchctl", "bootout", "gui/501/com.foo.agent"],
    ])
    #expect(MacCleanerCore.toggleCommands(label: "com.foo.agent", plist: plist, uid: 501, enable: true) == [
        ["launchctl", "enable", "gui/501/com.foo.agent"],
        ["launchctl", "bootstrap", "gui/501", plist.path],
    ])
}

@Test func adminWrapperEscapes() {
    let args = adminWrapped(#"echo "hi" \ there"#)
    #expect(args.first == "osascript")
    let script = args.dropFirst().filter { $0 != "-e" }.joined(separator: "\n")
    #expect(script.contains(#"do shell script "echo \"hi\" \\ there""#))
    #expect(script.contains("with administrator privileges"))
    #expect(script.contains("-128"))
}

@Test func maintenanceList() {
    #expect(Maintenance.allCases.count == 4)
    #expect(Maintenance.dns.needsAdmin && Maintenance.spotlight.needsAdmin)
    #expect(!Maintenance.launchServices.needsAdmin && !Maintenance.quickLook.needsAdmin)
    for task in Maintenance.allCases {
        #expect(!task.command.isEmpty)
        // Admin tasks go through the password dialog, never a bare sudo.
        #expect(!task.command.joined(separator: " ").contains("sudo"))
        if task.needsAdmin { #expect(task.command.first == "osascript") }
    }
}
