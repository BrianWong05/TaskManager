// TaskManagerTests/BundlePathTests.swift
// .app bundle extraction from executable paths (spec §3.3, §4.1).

import Testing
@testable import TaskManager

@Suite struct BundlePathTests {
    @Test func extractsContainingAppBundle() {
        #expect(appBundlePath(forExecutablePath: "/Applications/Safari.app/Contents/MacOS/Safari")
                == "/Applications/Safari.app")
        // Helper processes live deeper inside the bundle.
        #expect(appBundlePath(forExecutablePath: "/Applications/Firefox.app/Contents/Frameworks/XPC/Helper")
                == "/Applications/Firefox.app")
        // Nested .app resolves to the outermost bundle (the real app).
        #expect(appBundlePath(forExecutablePath: "/Applications/Outer.app/Contents/Inner.app/Contents/MacOS/Inner")
                == "/Applications/Outer.app")
    }

    @Test func processesWithoutBundleReturnNil() {
        #expect(appBundlePath(forExecutablePath: "/usr/libexec/sshd-keygen-wrapper") == nil)
        #expect(appBundlePath(forExecutablePath: "/sbin/launchd") == nil)
    }

    @Test func bareBundlePathCounts() {
        #expect(appBundlePath(forExecutablePath: "/Applications/Thing.app") == "/Applications/Thing.app")
    }

    @Test func displayNameStripsExtension() {
        #expect(ProcessTableReducer.displayName(forBundlePath: "/Applications/Safari.app") == "Safari")
        #expect(ProcessTableReducer.displayName(forBundlePath: "/Applications/Weird Name.app") == "Weird Name")
    }
}

@Suite struct ProtectedProcessTests {
    @Test func launchdAndKernelTaskAreProtected() {
        #expect(isSystemProtected(pid: 0, name: "kernel_task", path: ""))
        #expect(isSystemProtected(pid: 1, name: "launchd", path: "/sbin/launchd"))
        #expect(!isSystemProtected(pid: 500, name: "Safari", path: "/Applications/Safari.app"))
    }
}
