import AppKit

@MainActor
enum MainMenu {
    static let savedMacrosTitle = "Saved Macros"
    static let deleteMacrosTitle = "Delete Saved Macro"

    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        func menu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            holder.submenu = menu
            main.addItem(holder)
        }
        // No target: handled by whichever text field or editor has focus.
        func standard(_ title: String, _ action: Selector, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func command(_ title: String, _ action: Selector, _ key: String = "",
                     _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = standard(title, action, key, modifiers)
            item.target = target
            return item
        }

        menu("Slate", [
            standard("About Slate", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            standard("Hide Slate", #selector(NSApplication.hide(_:)), "h"),
            standard("Quit Slate", #selector(NSApplication.terminate(_:)), "q"),
        ])
        menu("File", [
            command("New", #selector(AppDelegate.newFile), "n"),
            command("Open…", #selector(AppDelegate.openFile), "o"),
            {
                let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
                let recent = NSMenu(title: "Open Recent")
                recent.delegate = target
                item.submenu = recent
                return item
            }(),
            .separator(),
            command("Save", #selector(AppDelegate.saveFile), "s"),
            command("Save As…", #selector(AppDelegate.saveFileAs), "s", [.command, .shift]),
            command("Save All", #selector(AppDelegate.saveAllFiles), "s", [.command, .option]),
            .separator(),
            command("Close Tab", #selector(AppDelegate.closeTab), "w"),
        ])
        menu("Edit", [
            standard("Undo", Selector(("undo:")), "z"),
            standard("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            standard("Cut", #selector(NSText.cut(_:)), "x"),
            standard("Copy", #selector(NSText.copy(_:)), "c"),
            standard("Paste", #selector(NSText.paste(_:)), "v"),
            standard("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            command("Find…", #selector(AppDelegate.showFind), "f"),
            command("Replace…", #selector(AppDelegate.showReplace), "f", [.command, .option]),
            command("Find Next", #selector(AppDelegate.findNext), "g"),
            command("Find Previous", #selector(AppDelegate.findPrevious), "g", [.command, .shift]),
            .separator(),
            command("Go to Line…", #selector(AppDelegate.goToLine), "l"),
            {
                let item = NSMenuItem(title: "Line Operations", action: nil, keyEquivalent: "")
                let lines = NSMenu(title: "Line Operations")
                let keys: [LineOperation: (String, NSEvent.ModifierFlags)] = [
                    .duplicate: ("d", .command),
                    .delete: ("k", [.command, .shift]),
                    .moveUp: (String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .control]),
                    .moveDown: (String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .control]),
                    .join: ("j", [.command, .control]),
                ]
                // Groups, separated in the menu.
                let groups: [[LineOperation]] = [
                    [.duplicate, .delete, .moveUp, .moveDown, .insertAbove, .insertBelow, .join],
                    [.sortAscending, .sortDescending, .sortIgnoringCase, .reverse],
                    [.removeDuplicates, .removeConsecutiveDuplicates, .removeEmpty, .removeBlank],
                    [.trimTrailing, .trimLeading, .trimBoth],
                ]
                for (index, group) in groups.enumerated() {
                    if index > 0 { lines.addItem(.separator()) }
                    for operation in group {
                        let key = keys[operation]
                        let entry = command(operation.rawValue, #selector(AppDelegate.performLineOperation(_:)),
                                            key?.0 ?? "", key?.1 ?? .command)
                        entry.representedObject = operation.rawValue
                        lines.addItem(entry)
                    }
                }
                item.submenu = lines
                return item
            }(),
        ])
        menu("View", [
            command("Word Wrap", #selector(AppDelegate.toggleWordWrap), "z", .option),
            command("Document Map", #selector(AppDelegate.toggleMinimap), "m", [.command, .option]),
            command("Change History", #selector(AppDelegate.toggleChangeHistory)),
            .separator(),
            command("Terminal", #selector(AppDelegate.toggleTerminal), "`", .control),
            command("Open Terminal in File's Folder", #selector(AppDelegate.openTerminalHere), "`", [.control, .shift]),
            .separator(),
            command("Split Editor", #selector(AppDelegate.toggleSplit), "\\"),
            command("Split Top and Bottom", #selector(AppDelegate.toggleSplitDirection)),
            .separator(),
            command("Zoom In", #selector(AppDelegate.zoomIn), "="),
            command("Zoom Out", #selector(AppDelegate.zoomOut), "-"),
            command("Actual Size", #selector(AppDelegate.actualSize), "0"),
        ])
        menu("Language", Language.menuOrder.map { language in
            let item = command(language.rawValue, #selector(AppDelegate.selectLanguage(_:)))
            item.representedObject = language.rawValue
            return item
        })
        func dynamic(_ title: String) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.delegate = target
            item.submenu = submenu
            return item
        }
        menu("Macro", [
            command("Start Recording", #selector(AppDelegate.toggleMacroRecording), "r", [.command, .control]),
            command("Play", #selector(AppDelegate.playMacro), "p", [.command, .control]),
            command("Run Multiple Times…", #selector(AppDelegate.playMacroManyTimes)),
            command("Save Recorded Macro…", #selector(AppDelegate.saveMacro)),
            .separator(),
            dynamic(savedMacrosTitle),
            dynamic(deleteMacrosTitle),
        ])
        menu("Git", [
            command("Commit…", #selector(AppDelegate.gitCommit), "k", [.command, .option]),
            command("Push", #selector(AppDelegate.gitPush), "p", [.command, .option, .shift]),
            command("Pull", #selector(AppDelegate.gitPull), "l", [.command, .option, .shift]),
            command("Fetch", #selector(AppDelegate.gitFetch)),
            .separator(),
            command("Switch Branch…", #selector(AppDelegate.gitSwitchBranch), "b", [.command, .option, .shift]),
            .separator(),
            command("Show Changes Since Last Commit", #selector(AppDelegate.showChanges), "d", [.command, .shift]),
        ])
        menu("Window", [
            standard("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            standard("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            command("Previous Tab", #selector(AppDelegate.previousTab), "[", [.command, .shift]),
            command("Next Tab", #selector(AppDelegate.nextTab), "]", [.command, .shift]),
            .separator(),
            command("Slate", #selector(AppDelegate.showWindow), "1"),
        ])
        return main
    }
}
