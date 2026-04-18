//
//  ExcludeSetupEditorController.swift
//  Later
//

import Cocoa
import UniformTypeIdentifiers

/// Edit display names and excluded bundle IDs for each of the four setups.
final class ExcludeSetupEditorController: NSViewController {

    var onFinished: (() -> Void)?

    private var displayNames: [String] = []
    private var bundleLists: [[String]] = []

    private let slotPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let nameField = NSTextField(string: "")
    private let tableView = NSTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private var tableRows: [String] = []

    private var editingSlot: Int = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 400))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        displayNames = ExcludeSetupStore.loadDisplayNames()
        bundleLists = ExcludeSetupStore.loadBundleLists()

        let title = NSTextField(labelWithString: "Edit setups")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let slotLabel = NSTextField(labelWithString: "Setup:")
        slotLabel.translatesAutoresizingMaskIntoConstraints = false
        slotPopUp.translatesAutoresizingMaskIntoConstraints = false
        for i in 0..<ExcludeSetupStore.slotCount {
            slotPopUp.addItem(withTitle: displayNames[i])
        }
        slotPopUp.target = self
        slotPopUp.action = #selector(slotChanged)

        let nameLabel = NSTextField(labelWithString: "Name:")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.placeholderString = "Display name"
        nameField.target = self
        nameField.action = #selector(nameChanged)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.usesAutomaticRowHeights = false
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bid"))
        col.title = "Bundle ID (do not hide)"
        col.width = 420
        tableView.addTableColumn(col)

        let addBtn = NSButton(title: "Add app…", target: self, action: #selector(addApp))
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        let removeBtn = NSButton(title: "Remove", target: self, action: #selector(removeSelected))
        removeBtn.translatesAutoresizingMaskIntoConstraints = false

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(done))
        doneBtn.keyEquivalent = "\r"
        doneBtn.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(slotLabel)
        view.addSubview(slotPopUp)
        view.addSubview(nameLabel)
        view.addSubview(nameField)
        view.addSubview(scrollView)
        view.addSubview(addBtn)
        view.addSubview(removeBtn)
        view.addSubview(doneBtn)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            slotLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            slotLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            slotPopUp.leadingAnchor.constraint(equalTo: slotLabel.trailingAnchor, constant: 8),
            slotPopUp.centerYAnchor.constraint(equalTo: slotLabel.centerYAnchor),
            slotPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.topAnchor.constraint(equalTo: slotLabel.bottomAnchor, constant: 12),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 12),
            scrollView.heightAnchor.constraint(equalToConstant: 200),

            addBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addBtn.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            removeBtn.leadingAnchor.constraint(equalTo: addBtn.trailingAnchor, constant: 8),
            removeBtn.centerYAnchor.constraint(equalTo: addBtn.centerYAnchor),

            doneBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            doneBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            doneBtn.topAnchor.constraint(greaterThanOrEqualTo: addBtn.bottomAnchor, constant: 16)
        ])

        editingSlot = 0
        slotPopUp.selectItem(at: 0)
        syncSlotToUI()
    }

    private func persistCurrentSlotBeforeSwitch() {
        guard editingSlot >= 0, editingSlot < ExcludeSetupStore.slotCount else { return }
        displayNames[editingSlot] = nameField.stringValue
        bundleLists[editingSlot] = tableRows
        slotPopUp.item(at: editingSlot)?.title = displayNames[editingSlot].isEmpty ? "Setup" : displayNames[editingSlot]
    }

    private func syncSlotToUI() {
        guard editingSlot >= 0, editingSlot < ExcludeSetupStore.slotCount else { return }
        nameField.stringValue = displayNames[editingSlot]
        tableRows = bundleLists[editingSlot]
        tableView.reloadData()
    }

    @objc private func slotChanged() {
        persistCurrentSlotBeforeSwitch()
        editingSlot = slotPopUp.indexOfSelectedItem
        syncSlotToUI()
    }

    @objc private func nameChanged() {
        guard editingSlot >= 0, editingSlot < displayNames.count else { return }
        displayNames[editingSlot] = nameField.stringValue
        slotPopUp.item(at: editingSlot)?.title = nameField.stringValue.isEmpty ? "Setup" : nameField.stringValue
    }

    @objc private func addApp() {
        // Defer so we are not inside the same event-tracking path as the button;
        // then use runModal() — not begin/beginSheetModal — to avoid nested modal deadlocks.
        DispatchQueue.main.async { [weak self] in
            self?.presentAppOpenPanel()
        }
    }

    private func presentAppOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose app"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        guard let bid = Bundle(url: url)?.bundleIdentifier, !bid.isEmpty else {
            NSSound.beep()
            return
        }
        if tableRows.contains(bid) { return }
        persistCurrentSlotBeforeSwitch()
        tableRows.append(bid)
        tableRows.sort()
        bundleLists[editingSlot] = tableRows
        tableView.reloadData()
    }

    @objc private func removeSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < tableRows.count else { return }
        persistCurrentSlotBeforeSwitch()
        tableRows.remove(at: row)
        bundleLists[editingSlot] = tableRows
        tableView.reloadData()
    }

    @objc private func done() {
        persistCurrentSlotBeforeSwitch()
        ExcludeSetupStore.saveDisplayNames(displayNames)
        ExcludeSetupStore.saveBundleLists(bundleLists)
        onFinished?()
        view.window?.close()
    }

    private func titleForBundleID(_ bid: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid),
              let b = Bundle(url: url) else { return bid }
        let n = b.localizedInfoDictionary?["CFBundleName"] as? String
            ?? b.infoDictionary?["CFBundleName"] as? String
        if let n, !n.isEmpty { return "\(n) — \(bid)" }
        return bid
    }
}

extension ExcludeSetupEditorController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bid = tableRows[row]
        let cell = NSTextField(labelWithString: titleForBundleID(bid))
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}
