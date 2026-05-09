import Cocoa
import Kit

public class RemoteSettingsView: NSStackView, Settings_v {
    public var onDevicesChanged: (([RemoteDevice], RemoteDevice?) -> Void)?

    private var devices: [RemoteDevice] = []
    private var tableView: NSTableView!
    private var nameField: NSTextField!
    private var hostField: NSTextField!
    private var statusLabel: NSTextField!
    private var testButton: NSButton!

    public init() {
        super.init(frame: NSZeroRect)
        self.orientation = .vertical
        self.spacing = 8
        self.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        devices = RemoteDeviceStore.load()
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    // Settings_v protocol
    public func load(widgets: [widget_t]) {}

    private func buildUI() {
        // Title
        let title = NSTextField(labelWithString: "Remote Devices")
        title.font = NSFont.boldSystemFont(ofSize: 13)
        self.addArrangedSubview(title)

        // Table
        tableView = NSTableView()
        let col1 = NSTableColumn(identifier: .init("name"))
        col1.title = "Name"; col1.width = 120
        let col2 = NSTableColumn(identifier: .init("host"))
        col2.title = "SSH Host"; col2.width = 160
        tableView.addTableColumn(col1)
        tableView.addTableColumn(col2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsEmptySelection = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 130).isActive = true
        self.addArrangedSubview(scroll)

        // Buttons row
        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 6
        let addBtn = NSButton(title: "+", target: self, action: #selector(newDevice))
        addBtn.bezelStyle = .smallSquare
        let removeBtn = NSButton(title: "−", target: self, action: #selector(removeDevice))
        removeBtn.bezelStyle = .smallSquare
        testButton = NSButton(title: "Test SSH", target: self, action: #selector(testConn))
        btnRow.addArrangedSubview(addBtn)
        btnRow.addArrangedSubview(removeBtn)
        btnRow.addArrangedSubview(testButton)
        self.addArrangedSubview(btnRow)

        // Form
        let nameRow = NSStackView()
        nameRow.orientation = .horizontal
        nameRow.spacing = 6
        nameRow.addArrangedSubview(makeLabel("Name:", width: 40))
        nameField = NSTextField()
        nameField.placeholderString = "buildserver"
        nameRow.addArrangedSubview(nameField)
        self.addArrangedSubview(nameRow)

        let hostRow = NSStackView()
        hostRow.orientation = .horizontal
        hostRow.spacing = 6
        hostRow.addArrangedSubview(makeLabel("Host:", width: 40))
        hostField = NSTextField()
        hostField.placeholderString = "buildserver or user@hostname"
        hostRow.addArrangedSubview(hostField)
        self.addArrangedSubview(hostRow)

        let saveBtn = NSButton(title: "Save / Add", target: self, action: #selector(saveDevice))
        self.addArrangedSubview(saveBtn)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        self.addArrangedSubview(statusLabel)

        let hint = NSTextField(wrappingLabelWithString: "SSH hosts are read from ~/.ssh/config. Use key-based auth for passwordless connection.")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        self.addArrangedSubview(hint)
    }

    private func makeLabel(_ text: String, width: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 12)
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        return l
    }

    // MARK: - Actions

    @objc private func newDevice() {
        tableView.deselectAll(nil)
        nameField.stringValue = ""
        hostField.stringValue = ""
        nameField.becomeFirstResponder()
    }

    @objc private func removeDevice() {
        let row = tableView.selectedRow
        guard devices.indices.contains(row) else { return }
        devices.remove(at: row)
        RemoteDeviceStore.save(devices)
        tableView.reloadData()
        notifyChange()
        statusLabel.stringValue = "Device removed."
    }

    @objc private func saveDevice() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !host.isEmpty else {
            statusLabel.stringValue = "Fill in both Name and Host."
            return
        }
        let row = tableView.selectedRow
        if devices.indices.contains(row) {
            devices[row].name = name
            devices[row].host = host
        } else {
            devices.append(RemoteDevice(name: name, host: host))
        }
        RemoteDeviceStore.save(devices)
        tableView.reloadData()
        notifyChange()
        statusLabel.stringValue = "Saved '\(name)'."
    }

    @objc private func testConn() {
        let host = hostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { statusLabel.stringValue = "Enter a Host first."; return }
        statusLabel.stringValue = "Testing…"
        testButton.isEnabled = false
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = ["-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                           "-o", "StrictHostKeyChecking=no", host, "echo ok"]
            let pipe = Pipe()
            p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let ok = p.terminationStatus == 0 && out.contains("ok")
            DispatchQueue.main.async {
                self.statusLabel.stringValue = ok ? "✅ Connected to '\(host)'" : "❌ Failed to connect to '\(host)'"
                self.testButton.isEnabled = true
            }
        }
    }

    private func notifyChange() {
        let selected = devices.first
        onDevicesChanged?(devices, selected)
    }
}

extension RemoteSettingsView: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int { devices.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let d = devices[row]
        let text = tableColumn?.identifier.rawValue == "name" ? d.name : d.host
        let cell = NSTextField(labelWithString: text)
        cell.font = NSFont.systemFont(ofSize: 12)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard devices.indices.contains(row) else { return }
        nameField.stringValue = devices[row].name
        hostField.stringValue = devices[row].host
    }
}
