import Testing
@testable import BIPro

@Suite("App Launch & Dock Reopen Policy")
struct AppLaunchPolicyTests {
    @Test func opensUntitledWhenLaunchedWithoutFilesOrWindows() {
        #expect(AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: false,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
    }

    @Test func skipsUntitledLaunchWhenLaunchedWithFileOrWindowVisible() {
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: false,
            hasStartedOpening: false,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: true,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: false,
            openDocumentsCount: 1,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: false,
            openDocumentsCount: 0,
            hasVisibleWindow: true,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: false,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: true
        ))
    }

    @Test func dockReopenOpensUntitledOnlyWhenNoWindowOrDocumentIsOpen() {
        #expect(AppLaunchPolicy.shouldOpenUntitledOnReopen(
            hasVisibleWindowsFlag: false,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnReopen(
            hasVisibleWindowsFlag: true,
            openDocumentsCount: 0,
            hasVisibleWindow: true,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnReopen(
            hasVisibleWindowsFlag: false,
            openDocumentsCount: 1,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
        #expect(!AppLaunchPolicy.shouldOpenUntitledOnReopen(
            hasVisibleWindowsFlag: false,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: true
        ))
    }

    @Test func emptyLaunchShowsStartScreenWindowWhenNoDocumentIsOpen() {
        #expect(UntitledDocuments.shouldShowStartScreenOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: false,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
        #expect(!UntitledDocuments.shouldShowStartScreenOnLaunch(
            isDefaultLaunch: true,
            hasStartedOpening: true,
            openDocumentsCount: 0,
            hasVisibleWindow: false,
            isRunningTests: false
        ))
    }
}
