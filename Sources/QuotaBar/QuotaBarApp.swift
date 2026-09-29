import AppKit
import Darwin
import SwiftUI
import QuotaCore

/// AppKit lifecycle, not a SwiftUI `App`.
///
/// There is no SwiftUI scene left to show: the menu-bar item is a status item
/// (`StatusItemCoordinator`), the settings window is ours (`SettingsWindow`),
/// and every other surface is an `NSPanel` hosting a SwiftUI view. The
/// intermediate step — a SwiftUI `App` whose only scene was
/// `Settings { EmptyView() }` — put that scene's window on screen at launch,
/// an empty 45×233pt window titled "QuotaBar Settings", because SwiftUI shows
/// the settings scene when it is the only one. Hence the plain delegate.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `NSApplication.delegate` is weak; something has to own the delegate.
    private static var shared: AppDelegate?

    private var store: UsageStore?
    private let coordinators = Coordinators()
    /// Set when a second launch arrives before Settings has a store.
    private var showWhenReady = false
    /// Held for the life of the process. The kernel drops it on exit, so a
    /// crash cannot leave the app unable to start.
    private static var instanceLock: Int32 = -1
    private static let reopenNotification = Notification.Name("bar.quota.QuotaBar.reopen")

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        // `NSApplicationMain`, not `app.run()`: with a bare `run()` the status
        // item's window was created but never placed — it sat at (0, 0, 38, 0)
        // and the accessibility tree showed no status menu bar at all.
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    /// A main menu nobody sees, for the shortcuts it carries.
    ///
    /// Text fields take ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z from the main menu: AppKit hands
    /// a key equivalent to the menu, and the menu item sends `paste:` and the
    /// rest down the responder chain. An accessory app gets no menu from a
    /// nib, so with none built here a pasted API key went nowhere — the
    /// credential field in Settings looked like it refused input. The menu
    /// bar never shows it: an accessory app does not own the menu bar.
    private static func keyEquivalentMenu() -> NSMenu {
        let main = NSMenu()

        let edit = NSMenu(title: L10n.t("Edit", "编辑"))
        edit.addItem(withTitle: L10n.t("Undo", "撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L10n.t("Redo", "重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.t("Cut", "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.t("Copy", "拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.t("Paste", "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.t("Select All", "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        // ⌘W closes Settings and the other windows the way it does anywhere.
        // ⌘Q quits. An accessory app does not own the menu bar, so these
        // equivalents never arrive on their own; `installWindowShortcuts`
        // is what actually handles the keys.
        let appMenu = NSMenu(title: "QuotaBar")
        appMenu.addItem(withTitle: L10n.t("Quit QuotaBar", "退出 QuotaBar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let window = NSMenu(title: L10n.t("Window", "窗口"))
        window.addItem(withTitle: L10n.t("Close", "关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)

        return main
    }

    /// ⌘Q quits and ⌘W closes the key window.
    ///
    /// The menu above is the usual place for both, and it is installed. It
    /// does not fire: this is an accessory app, so the menu bar belongs to
    /// whoever is in front, and AppKit never matches those key equivalents.
    /// Copy and paste still work because the text system binds them itself.
    /// The menu panel already closes itself on ⌘W; this leaves that event
    /// alone and handles every window that actually has a close button.
    private static func installWindowShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else {
                return event
            }
            switch key {
            case "q":
                if !event.isARepeat { NSApp.terminate(nil) }
                return nil
            case "w":
                guard let window = NSApp.keyWindow, window.styleMask.contains(.closable) else { return event }
                if !event.isARepeat { window.performClose(nil) }
                return nil
            default:
                return event
            }
        }
    }

    /// A menu-bar agent is not brought forward when opened again, so Finder
    /// and Launchpad start a second process and a second status icon.
    /// `LSMultipleInstancesProhibited` stops that at Launch Services; this
    /// covers a second process that still gets as far as `main`. One-shot
    /// commands (`--json` and the previews) do not take the lock, so they
    /// can run beside the menu-bar app.
    private static func anotherInstanceIsRunning() -> Bool {
        let url = AppSupport.directory.appendingPathComponent("instance.lock")
        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return true
        }
        instanceLock = fd
        return false
    }

    private func listenForReopen() {
        DistributedNotificationCenter.default().addObserver(
            forName: Self.reopenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.showRunningApp()
            }
        }
    }

    private func showRunningApp() {
        guard store != nil else {
            showWhenReady = true
            return
        }
        SettingsWindow.open()
    }

    /// A titled, closable window — Settings, the share studio, a login sheet's
    /// window — is a main window. The menu panel, island and edge dock are
    /// borderless panels and do not count.
    private static func countsForDock(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && window.styleMask.contains(.closable)
    }

    private func trackDockIcon() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, Self.countsForDock(window) else { return }
                guard NSApp.activationPolicy() != .regular else { return }
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let stillOpen = NSApp.windows.contains { window in
                        window !== closing && window.isVisible && Self.countsForDock(window)
                    }
                    guard !stillOpen, NSApp.activationPolicy() != .accessory else { return }
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    /// Opening the app while it runs — from Launchpad, Spotlight, or the
    /// Finder — means "show me". With the menu-bar item hidden it is also
    /// the way back to Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.open()
        return false
    }

    /// A Kimi Code renewal with its request out holds the only copy of a
    /// refresh token the server may already have rotated: quitting starts no
    /// new renewal or retry, and waits for the reply to be saved — at most
    /// the request's own 30 seconds, and a little more.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let renewal = KimiCodeRenewal.shared
        renewal.stop()
        guard renewal.hasRequestOut else { return .terminateNow }
        Task.detached {
            await renewal.waitForRequests(timeout: 35)
            await MainActor.run { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    /// The run ledger saves five seconds after a change; quitting inside
    /// that window would drop the change without this. Quitting mid-renewal
    /// gives Kimi Code its lock back at once rather than after it goes stale
    /// — only after the renewal's reply is saved (`applicationShouldTerminate`).
    func applicationWillTerminate(_ notification: Notification) {
        RunLedgerStore.shared.flush()
        KimiCodeLock.releaseAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        listenForReopen()
        let arguments = CommandLine.arguments
        // Loading the config applies the saved language. Load it before
        // anything renders, or a preview that sets its own language would
        // have it switched back by the first read of a setting.
        _ = ConfigStore.shared
        // `--lang en|zh` renders the previews below in one language without
        // touching the saved setting.
        if let index = arguments.firstIndex(of: "--lang"), index + 1 < arguments.count {
            L10n.override = arguments[index + 1].hasPrefix("zh") ? .zhHans : .en
        }
        if let index = arguments.firstIndex(of: "--snapshot") {
            let directory = index + 1 < arguments.count ? arguments[index + 1] : "./snapshots"
            Snapshot.run(directory: directory)
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--settings-preview") {
            let directory = index + 1 < arguments.count ? arguments[index + 1] : "./settings"
            Snapshot.settingsPreview(directory: directory)
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--projects-preview") {
            let directory = index + 1 < arguments.count ? arguments[index + 1] : "./projects"
            Snapshot.projectsPreview(directory: directory)
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--icon-preview") {
            let directory = index + 1 < arguments.count ? arguments[index + 1] : "./icons"
            Snapshot.iconPreview(directory: directory)
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--widget-concepts") {
            let directory = index + 1 < arguments.count ? arguments[index + 1] : "./widget-concepts"
            WidgetConceptBoard.render(directory: directory)
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--island-preview") {
            let directory = index + 1 < arguments.count ? arguments[index + 1] : "./island"
            Snapshot.islandPreview(directory: directory)
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--settings-window") {
            // `--settings-window status` opens straight to a section;
            // `--settings-window providers codex` also opens that provider's row.
            let section = index + 1 < arguments.count ? SettingsSection(rawValue: arguments[index + 1]) : nil
            let expanded = index + 2 < arguments.count ? ProviderID(rawValue: arguments[index + 2]) : nil
            Diagnostics.settingsWindow(section: section ?? .providers, expanded: expanded)
            return
        }
        if arguments.contains("--windows") {
            Diagnostics.printWindows()
            return
        }
        if arguments.contains("--cost") {
            Diagnostics.printCost()
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--ledger") {
            Diagnostics.printLedger()
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--status") {
            Diagnostics.printStatus()
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--provider"), index + 1 < arguments.count {
            Diagnostics.printProvider(arguments[index + 1])
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--archive-timing") {
            Diagnostics.printArchiveTiming()
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--projects") {
            // `QuotaBar --projects [days]`: tokens per project from the logs, read now.
            let days = index + 1 < arguments.count ? Int(arguments[index + 1]) ?? 30 : 30
            Diagnostics.printProjects(days: days)
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--json") {
            // `QuotaBar --json [--force]`: the limits other tools read,
            // through the last readings when they are under five minutes old.
            Diagnostics.printLimitsJSON(force: arguments.contains("--force"))
            NSApp.terminate(nil)
            return
        }
        if arguments.contains("--credentials") {
            Diagnostics.printCredentials()
            NSApp.terminate(nil)
            return
        }

        // From here on this is the app itself, which runs on and can see a
        // Kimi Code renewal through; the one-off commands above only read.
        if Self.anotherInstanceIsRunning() {
            DistributedNotificationCenter.default().postNotificationName(
                Self.reopenNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        // Info.plist carries LSUIElement, so the app lives in the menu bar and
        // stays out of the Dock until a real window opens. `trackDockIcon`
        // puts the icon back for that window and takes it away when the last
        // one closes. The menu-bar item is unaffected either way.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.keyEquivalentMenu()
        Self.installWindowShortcuts()
        trackDockIcon()
        KimiCodeRenewal.allowInThisProcess()
        let store = UsageStore()
        self.store = store
        SettingsWindow.configure(store: store)
        if showWhenReady { SettingsWindow.open() }
        MenuPanelController.shared.configure(store: store)
        coordinators.start(store: store)
        if let index = arguments.firstIndex(of: "--simulate-reset"), index + 1 < arguments.count,
           let id = ProviderID(rawValue: arguments[index + 1])
        {
            // Plays the reset moment for that provider a few seconds in.
            store.simulateReset(id)
        }
        if arguments.contains("--panel-window") {
            // Opens the menu panel under the top-right of the screen, for
            // looking at it without clicking the item.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MenuPanelController.shared.open(from: nil)
            }
        }
        if arguments.contains("--update-window") {
            // The update card with a sample release, for looking at the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                store.updateStage = .available(Snapshot.sampleRelease)
                UpdateWindow.show(store: store)
            }
        }
        if arguments.contains("--share-studio") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ShareStudio.open(store: store) }
        }
    }
}

/// The surfaces that hang off the store, and the one place that decides
/// which of them to poke when it changes. The status item's store
/// subscription drives it; the revisions are compared here so that a tick
/// does not re-place the dock or re-sync the widget.
@MainActor
final class Coordinators {
    private let status = StatusItemCoordinator()
    private let island = IslandCoordinator()
    private let dock = EdgeDockCoordinator()
    private let widget = DesktopWidgetCoordinator()

    /// The island and dock switches as last applied; nil forces the next sync
    /// to apply them.
    private var surfaces: (island: Bool, dock: Bool)?
    private var widgetRevision = -1
    private var dockRevision = -1
    private var islandRevision = -1
    private var screenObserver: NSObjectProtocol?

    func start(store: UsageStore) {
        status.onStoreChange = { [weak self, weak store] in
            guard let self, let store else { return }
            self.sync(store: store)
        }
        status.start(store: store)
        store.onResets = { [weak self, weak store] events, before in
            guard let self, let store else { return }
            self.status.playReset(from: before)
            // Both, when both are on: each plays the resets of the
            // providers it shows.
            if store.showsIsland { self.island.playReset(events, store: store) }
            if store.showsDock { self.dock.playReset(events, store: store) }
        }
        sync(store: store)
        // A display plugged in or pulled: whatever screen each surface now
        // belongs on, it goes there.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main)
        { [weak self, weak store] _ in
            guard let self, let store else { return }
            MainActor.assumeIsolated {
                self.dock.relayout()
                self.island.relayout()
                self.widget.sync(store: store)
            }
        }
    }

    /// The island and the dock follow their own switches and can be on
    /// together; the menu-bar item stays regardless, as the settings entry
    /// point.
    private var privacyMasked = false
    private var experienceRevision = -1

    private func sync(store: UsageStore) {
        if store.isPrivacyMasked != privacyMasked {
            privacyMasked = store.isPrivacyMasked
            if privacyMasked {
                island.hide()
                dock.hide()
                widget.hide()
                surfaces = nil
            } else {
                surfaces = nil
                widgetRevision = -1
            }
        }
        if store.experienceRevision != experienceRevision {
            experienceRevision = store.experienceRevision
            GlobalHotkey.shared.action = { [weak self] in
                MenuPanelController.shared.toggle(from: self?.status.button)
            }
            GlobalHotkey.shared.apply(store.experience.hotkey)
            LocalAPIServer.shared.apply(enabled: store.experience.localAPI, store: store)
        }
        guard !privacyMasked else { return }
        island.noteSeverity(store.islandSeverity, enabled: store.experience.islandAutoPeek)
        if surfaces?.island != store.showsIsland || surfaces?.dock != store.showsDock {
            surfaces = (store.showsIsland, store.showsDock)
            island.sync(store: store)
            dock.sync(store: store)
            widget.sync(store: store)
        }
        if store.widgetRevision != widgetRevision {
            widgetRevision = store.widgetRevision
            widget.sync(store: store)
        }
        if store.dockRevision != dockRevision {
            dockRevision = store.dockRevision
            dock.relayout()
        }
        if store.islandRevision != islandRevision {
            islandRevision = store.islandRevision
            island.relayout()
        }
    }
}
