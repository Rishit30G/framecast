import AppKit

// `Framecast --selftest <folder>` renders a synthetic project without any UI or permissions.
if let i = CommandLine.arguments.firstIndex(of: "--selftest"), CommandLine.arguments.count > i + 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task.detached {
        let ok = await SelfTest.run(in: folder)
        exit(ok ? 0 : 1)
    }
    dispatchMain()
}

// `Framecast --transcribe <audio file>` prints the captions it would generate.
if let i = CommandLine.arguments.firstIndex(of: "--transcribe"), CommandLine.arguments.count > i + 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task.detached {
        do {
            for c in try await CaptionGenerator.captions(fromAudio: url) {
                print(String(format: "%5.2f – %5.2f  %@", c.start, c.end, c.text))
            }
            exit(0)
        } catch {
            print("TRANSCRIBE FAILED: \(error)")
            exit(1)
        }
    }
    dispatchMain()
}

// `Framecast --clean <in> <out>` runs voice clean-up on an audio file.
if let i = CommandLine.arguments.firstIndex(of: "--clean"), CommandLine.arguments.count > i + 2 {
    do {
        try VoiceCleaner.clean(input: URL(fileURLWithPath: CommandLine.arguments[i + 1]),
                               output: URL(fileURLWithPath: CommandLine.arguments[i + 2]))
        print("cleaned")
        exit(0)
    } catch {
        print("CLEAN FAILED: \(error)")
        exit(1)
    }
}

_ = ClaudeTools.handle(CommandLine.arguments)

// `Framecast --demos <folder>` renders the website's feature clips.
if let i = CommandLine.arguments.firstIndex(of: "--demos"), CommandLine.arguments.count > i + 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    Task.detached { exit(await Demos.run(in: folder) ? 0 : 1) }
    dispatchMain()
}

// `Framecast --colortest <folder>` records and exports known colours and reports the error.
if let i = CommandLine.arguments.firstIndex(of: "--colortest"), CommandLine.arguments.count > i + 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in await ColorTest.run(in: folder) }
        app.run()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
