import AppKit

class GateWindow: NSObject, NSWindowDelegate {
    var onAuthenticate: (() -> Void)?
    var onCancel: (() -> Void)?

    private let window: NSWindow
    private let errorLabel: NSTextField
    private let auditHeader: NSTextField
    private let auditLabel: NSTextField
    private let stackView: NSStackView
    private var resolved = false

    init(ruleName: String, riskLevel: String, reason: String, commandText: String, workingDirectory: String, justification: String? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "claude-gate: Authorization Required"
        window.level = .floating
        window.center()
        self.window = window

        // -- Build the content view --

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView = stackView

        // Rule name
        let ruleLabel = NSTextField(labelWithString: ruleName)
        ruleLabel.font = NSFont.boldSystemFont(ofSize: 16)

        // Risk level
        let riskColor: NSColor = {
            switch riskLevel.lowercased() {
            case "critical": return .systemRed
            case "high": return .systemOrange
            case "medium": return .systemYellow
            case "low": return .systemGreen
            default: return .labelColor
            }
        }()
        let riskLabel = NSTextField(labelWithString: "Risk: \(riskLevel.uppercased())")
        riskLabel.font = NSFont.boldSystemFont(ofSize: 13)
        riskLabel.textColor = riskColor

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // WHY section
        let whyHeader = NSTextField(labelWithString: "WHY:")
        whyHeader.font = NSFont.boldSystemFont(ofSize: 13)

        let reasonLabel = NSTextField(wrappingLabelWithString: reason)
        reasonLabel.font = NSFont.systemFont(ofSize: 13)

        // AGENT JUSTIFICATION section (if provided)
        var justificationViews: [NSView] = []
        if let justification = justification, !justification.isEmpty {
            let justHeader = NSTextField(labelWithString: "AGENT JUSTIFICATION:")
            justHeader.font = NSFont.boldSystemFont(ofSize: 13)

            let justLabel = NSTextField(wrappingLabelWithString: justification)
            justLabel.font = NSFont.systemFont(ofSize: 13)
            justLabel.textColor = .secondaryLabelColor

            justificationViews = [justHeader, justLabel]
        }

        // COMMAND section
        let commandHeader = NSTextField(labelWithString: "COMMAND:")
        commandHeader.font = NSFont.boldSystemFont(ofSize: 13)

        let commandTextView = NSTextView()
        commandTextView.isEditable = false
        commandTextView.isSelectable = true
        commandTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        commandTextView.backgroundColor = NSColor(calibratedRed: 0x1e/255.0, green: 0x1e/255.0, blue: 0x1e/255.0, alpha: 1.0)
        commandTextView.textColor = .white
        commandTextView.string = commandText
        commandTextView.textContainerInset = NSSize(width: 6, height: 6)

        let scrollView = NSScrollView()
        scrollView.documentView = commandTextView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // WORKING DIRECTORY section
        let cwdHeader = NSTextField(labelWithString: "WORKING DIRECTORY:")
        cwdHeader.font = NSFont.boldSystemFont(ofSize: 13)

        let cwdLabel = NSTextField(labelWithString: workingDirectory)
        cwdLabel.font = NSFont.systemFont(ofSize: 13)
        cwdLabel.lineBreakMode = .byTruncatingMiddle

        // SECURITY AUDIT section (hidden initially, shown when audit completes)
        let auditSeparator = NSBox()
        auditSeparator.boxType = .separator
        auditSeparator.translatesAutoresizingMaskIntoConstraints = false

        let auditHeader = NSTextField(labelWithString: "SECURITY AUDIT: analyzing...")
        auditHeader.font = NSFont.boldSystemFont(ofSize: 13)
        auditHeader.textColor = .secondaryLabelColor
        self.auditHeader = auditHeader

        let auditLabel = NSTextField(wrappingLabelWithString: "")
        auditLabel.font = NSFont.systemFont(ofSize: 12)
        auditLabel.textColor = .secondaryLabelColor
        auditLabel.isHidden = true
        self.auditLabel = auditLabel

        // Error label (hidden initially)
        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        self.errorLabel = errorLabel

        // Button bar
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        let authButton = NSButton(title: "Authenticate", target: nil, action: nil)
        authButton.bezelStyle = .rounded
        authButton.keyEquivalent = "\r"
        cancelButton.bezelStyle = .rounded

        let buttonBar = NSStackView(views: [cancelButton, authButton])
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 12

        // Spacer view
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        // Add all views to stack
        stackView.addArrangedSubview(ruleLabel)
        stackView.addArrangedSubview(riskLabel)
        stackView.addArrangedSubview(separator)
        stackView.addArrangedSubview(whyHeader)
        stackView.addArrangedSubview(reasonLabel)
        for view in justificationViews {
            stackView.addArrangedSubview(view)
        }
        stackView.addArrangedSubview(commandHeader)
        stackView.addArrangedSubview(scrollView)
        stackView.addArrangedSubview(cwdHeader)
        stackView.addArrangedSubview(cwdLabel)
        stackView.addArrangedSubview(auditSeparator)
        stackView.addArrangedSubview(auditHeader)
        stackView.addArrangedSubview(auditLabel)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(errorLabel)
        stackView.addArrangedSubview(buttonBar)

        // Right-align button bar
        buttonBar.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),

            separator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            auditSeparator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),

            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 80),
            scrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),

            reasonLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            cwdLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            auditLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),

            buttonBar.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -20),
        ])

        // Constrain justification label width if present
        for view in justificationViews {
            if view is NSTextField, view != justificationViews.first {
                NSLayoutConstraint.activate([
                    view.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
                ])
            }
        }

        super.init()

        window.delegate = self

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        authButton.target = self
        authButton.action = #selector(authenticateClicked)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        resolved = true
        window.close()
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = false
    }

    /// Update the security audit section with results
    func showAuditResult(verdict: String, analysis: String) {
        let color: NSColor
        switch verdict.uppercased() {
        case "SAFE": color = .systemGreen
        case "SUSPICIOUS": color = .systemOrange
        case "DANGEROUS": color = .systemRed
        default: color = .secondaryLabelColor
        }

        auditHeader.stringValue = "SECURITY AUDIT: \(verdict.uppercased())"
        auditHeader.textColor = color
        auditLabel.stringValue = analysis
        auditLabel.isHidden = false
    }

    /// Show that the audit is unavailable (no API key)
    func showAuditUnavailable() {
        auditHeader.stringValue = "SECURITY AUDIT: unavailable (no ANTHROPIC_API_KEY)"
        auditHeader.textColor = .tertiaryLabelColor
    }

    // MARK: - Actions

    @objc private func authenticateClicked() {
        resolved = true
        onAuthenticate?()
    }

    @objc private func cancelClicked() {
        resolved = true
        onCancel?()
        window.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if !resolved {
            resolved = true
            onCancel?()
        }
    }
}
