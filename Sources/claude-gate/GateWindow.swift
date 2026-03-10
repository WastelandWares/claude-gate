import AppKit

// MARK: - Styled Button

private class StyledButton: NSButton {
    private let fillColor: NSColor
    private let hoverColor: NSColor
    private let isDestructive: Bool
    private var trackingArea: NSTrackingArea?
    private var isHovering = false

    init(title: String, fillColor: NSColor, hoverColor: NSColor? = nil, isDestructive: Bool = false, keyEquivalent: String = "") {
        self.fillColor = fillColor
        self.hoverColor = hoverColor ?? fillColor.withAlphaComponent(0.85)
        self.isDestructive = isDestructive
        super.init(frame: .zero)
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.bezelStyle = .rounded
        self.isBordered = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.contentTintColor = .white
        self.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        self.setAccessibilityLabel(title)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true; applyColors() }
    override func mouseExited(with event: NSEvent) { isHovering = false; applyColors() }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 24
        size.height = max(size.height, 30)
        return size
    }

    private func applyColors() {
        layer?.backgroundColor = (isHovering ? hoverColor : fillColor).cgColor
    }
}

// MARK: - Section Background View

private class SectionView: NSView {
    init(arrangedSubviews: [NSView], spacing: CGFloat = 4) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor

        let stack = NSStackView(views: arrangedSubviews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Make the width of inner wrapping labels match the section width
    func constrainLabelsWidth(to anchor: NSLayoutDimension) {
        for sub in (subviews.first as? NSStackView)?.arrangedSubviews ?? [] {
            if let tf = sub as? NSTextField, tf.cell?.wraps == true {
                tf.widthAnchor.constraint(equalTo: anchor, constant: -24).isActive = true
            }
        }
    }
}

// MARK: - Risk Badge View

private class RiskBadge: NSView {
    init(riskLevel: String) {
        super.init(frame: .zero)
        wantsLayer = true

        let (bgColor, textColor) = Self.colors(for: riskLevel)
        layer?.cornerRadius = 4
        layer?.backgroundColor = bgColor.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: riskLevel.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = textColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityLabel("Risk level: \(riskLevel)")
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func colors(for risk: String) -> (bg: NSColor, text: NSColor) {
        switch risk.lowercased() {
        case "critical": return (.systemRed, .systemRed)
        case "high": return (.systemOrange, .systemOrange)
        case "medium": return (.systemYellow, .systemYellow)
        case "low": return (.systemGreen, .systemGreen)
        default: return (.secondaryLabelColor, .secondaryLabelColor)
        }
    }
}

// MARK: - GateWindow

class GateWindow: NSObject, NSWindowDelegate {
    var onAuthenticate: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTimeout: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    var onAlwaysDeny: (() -> Void)?
    var onRequestJustification: (() -> Void)?

    private let window: NSWindow
    private let errorLabel: NSTextField
    private let auditHeader: NSTextField
    private let auditLabel: NSTextField
    private let auditDisclaimer: NSTextField
    private let justificationResponseLabel: NSTextField
    private let whyButton: NSButton
    private let stackView: NSStackView
    private var resolved = false

    // Countdown
    private let countdownLabel: NSTextField
    private var remainingSeconds: Int
    private var countdownTimer: Timer?
    private let timeoutActionWord: String

    init(ruleName: String, riskLevel: String, reason: String, commandText: String, workingDirectory: String, justification: String? = nil, timeout: Int = 60, timeoutAction: String = "deny") {

        // -- Window --
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "claude-gate: Authorization Required"
        window.level = .floating
        window.center()
        window.isMovableByWindowBackground = true
        self.window = window

        // -- Root stack --
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.stackView = stackView

        // ── Title row: rule name + risk badge ──

        let ruleLabel = NSTextField(labelWithString: ruleName)
        ruleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        ruleLabel.setAccessibilityLabel("Rule: \(ruleName)")

        let riskBadge = RiskBadge(riskLevel: riskLevel)

        let titleRow = NSStackView(views: [ruleLabel, riskBadge])
        titleRow.orientation = .horizontal
        titleRow.spacing = 10
        titleRow.alignment = .centerY

        // ── Countdown ──

        let actionWord = timeoutAction == "passthrough" ? "Auto-allow" : "Auto-deny"
        let countdownLabel = NSTextField(labelWithString: "\(actionWord) in \(timeout)s")
        countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        countdownLabel.textColor = .secondaryLabelColor
        self.countdownLabel = countdownLabel
        self.remainingSeconds = timeout
        self.timeoutActionWord = actionWord

        // ── WHY section ──

        let whyHeader = Self.sectionHeader("WHY")
        let reasonLabel = NSTextField(wrappingLabelWithString: reason)
        reasonLabel.font = NSFont.systemFont(ofSize: 13)

        var whySectionViews: [NSView] = [whyHeader, reasonLabel]

        // Agent justification (if provided)
        if let justification = justification, !justification.isEmpty {
            let justHeader = Self.sectionHeader("AGENT JUSTIFICATION")
            let justLabel = NSTextField(wrappingLabelWithString: justification)
            justLabel.font = NSFont.systemFont(ofSize: 13)
            justLabel.textColor = .secondaryLabelColor
            whySectionViews.append(justHeader)
            whySectionViews.append(justLabel)
        }

        let whySection = SectionView(arrangedSubviews: whySectionViews, spacing: 4)

        // ── COMMAND section ──

        let commandHeader = Self.sectionHeader("COMMAND")

        let commandTextView = NSTextView()
        commandTextView.isEditable = false
        commandTextView.isSelectable = true
        commandTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        commandTextView.backgroundColor = NSColor(calibratedRed: 0x1e/255.0, green: 0x1e/255.0, blue: 0x1e/255.0, alpha: 1.0)
        commandTextView.textColor = .white
        commandTextView.string = commandText
        commandTextView.textContainerInset = NSSize(width: 8, height: 8)
        commandTextView.setAccessibilityLabel("Command: \(commandText)")

        let scrollView = NSScrollView()
        scrollView.documentView = commandTextView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 6
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let commandSection = SectionView(arrangedSubviews: [commandHeader, scrollView], spacing: 6)

        // ── WORKING DIRECTORY section ──

        let cwdHeader = Self.sectionHeader("WORKING DIRECTORY")

        let cwdLabel = NSTextField(labelWithString: workingDirectory)
        cwdLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cwdLabel.textColor = .secondaryLabelColor
        cwdLabel.lineBreakMode = .byTruncatingMiddle
        cwdLabel.isSelectable = true

        let cwdSection = SectionView(arrangedSubviews: [cwdHeader, cwdLabel], spacing: 4)

        // ── SECURITY AUDIT section ──

        let auditHeader = NSTextField(labelWithString: "SECURITY AUDIT")
        auditHeader.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        auditHeader.textColor = .tertiaryLabelColor

        let auditStatusLabel = NSTextField(labelWithString: "analyzing...")
        auditStatusLabel.font = NSFont.systemFont(ofSize: 11)
        auditStatusLabel.textColor = .tertiaryLabelColor

        let auditHeaderRow = NSStackView(views: [auditHeader, auditStatusLabel])
        auditHeaderRow.orientation = .horizontal
        auditHeaderRow.spacing = 6

        self.auditHeader = auditHeader

        let auditLabel = NSTextField(wrappingLabelWithString: "")
        auditLabel.font = NSFont.systemFont(ofSize: 12)
        auditLabel.textColor = .secondaryLabelColor
        auditLabel.isHidden = true
        self.auditLabel = auditLabel

        let auditDisclaimer = NSTextField(labelWithString: "AI audit is advisory only — verify commands yourself")
        auditDisclaimer.font = NSFont.systemFont(ofSize: 10)
        auditDisclaimer.textColor = .tertiaryLabelColor
        auditDisclaimer.isHidden = true
        self.auditDisclaimer = auditDisclaimer

        let auditSection = SectionView(arrangedSubviews: [auditHeaderRow, auditLabel, auditDisclaimer], spacing: 4)

        // ── "Why?" button and justification response ──

        let whyButton = StyledButton(
            title: "  Why?  ",
            fillColor: .systemBlue.withAlphaComponent(0.15),
            hoverColor: .systemBlue.withAlphaComponent(0.25)
        )
        whyButton.contentTintColor = .systemBlue
        whyButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        self.whyButton = whyButton

        let justificationResponseLabel = NSTextField(wrappingLabelWithString: "")
        justificationResponseLabel.font = NSFont.systemFont(ofSize: 12)
        justificationResponseLabel.textColor = .secondaryLabelColor
        justificationResponseLabel.isHidden = true
        self.justificationResponseLabel = justificationResponseLabel

        // ── Error label ──

        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = NSFont.systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 2
        self.errorLabel = errorLabel

        // ── Button bars ──

        // Primary actions
        let cancelButton = StyledButton(
            title: "Cancel",
            fillColor: NSColor.systemGray.withAlphaComponent(0.2),
            hoverColor: NSColor.systemGray.withAlphaComponent(0.3)
        )
        cancelButton.contentTintColor = .labelColor

        let authButton = StyledButton(
            title: "Authenticate",
            fillColor: .systemBlue,
            hoverColor: .systemBlue.withAlphaComponent(0.85),
            keyEquivalent: "\r"
        )

        let buttonBar = NSStackView(views: [cancelButton, authButton])
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 10

        // Persistent rule buttons
        let alwaysDenyButton = StyledButton(
            title: "Always Deny",
            fillColor: .systemRed.withAlphaComponent(0.12),
            hoverColor: .systemRed.withAlphaComponent(0.22),
            isDestructive: true
        )
        alwaysDenyButton.contentTintColor = .systemRed

        let alwaysAllowButton = StyledButton(
            title: "Always Allow",
            fillColor: .systemGreen.withAlphaComponent(0.12),
            hoverColor: .systemGreen.withAlphaComponent(0.22)
        )
        alwaysAllowButton.contentTintColor = .systemGreen

        let persistBar = NSStackView(views: [alwaysDenyButton, alwaysAllowButton])
        persistBar.orientation = .horizontal
        persistBar.spacing = 10

        // ── Thin separator above buttons ──

        let bottomSeparator = NSBox()
        bottomSeparator.boxType = .separator
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false

        // ── Spacer ──

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        // ── Assemble stack ──

        stackView.addArrangedSubview(titleRow)
        stackView.addArrangedSubview(countdownLabel)
        stackView.addArrangedSubview(whySection)
        stackView.addArrangedSubview(commandSection)
        stackView.addArrangedSubview(cwdSection)
        stackView.addArrangedSubview(auditSection)
        stackView.addArrangedSubview(whyButton)
        stackView.addArrangedSubview(justificationResponseLabel)
        stackView.addArrangedSubview(spacer)
        stackView.addArrangedSubview(errorLabel)
        stackView.addArrangedSubview(bottomSeparator)
        stackView.addArrangedSubview(persistBar)
        stackView.addArrangedSubview(buttonBar)

        // Custom spacing after certain views
        stackView.setCustomSpacing(4, after: titleRow)
        stackView.setCustomSpacing(16, after: countdownLabel)
        stackView.setCustomSpacing(10, after: whySection)
        stackView.setCustomSpacing(10, after: commandSection)
        stackView.setCustomSpacing(10, after: cwdSection)
        stackView.setCustomSpacing(8, after: auditSection)
        stackView.setCustomSpacing(4, after: errorLabel)
        stackView.setCustomSpacing(12, after: bottomSeparator)
        stackView.setCustomSpacing(8, after: persistBar)

        // ── Layout ──

        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        persistBar.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = stackView

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),

            whySection.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -48),
            commandSection.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -48),
            cwdSection.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -48),
            auditSection.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -48),

            scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 80),
            scrollView.widthAnchor.constraint(equalTo: commandSection.widthAnchor, constant: -24),

            cwdLabel.widthAnchor.constraint(equalTo: cwdSection.widthAnchor, constant: -24),

            justificationResponseLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -48),

            bottomSeparator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -48),

            buttonBar.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -24),
            persistBar.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 24),
        ])

        // Constrain wrapping labels inside sections
        whySection.constrainLabelsWidth(to: whySection.widthAnchor)
        auditSection.constrainLabelsWidth(to: auditSection.widthAnchor)

        super.init()

        window.delegate = self

        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        authButton.target = self
        authButton.action = #selector(authenticateClicked)
        alwaysAllowButton.target = self
        alwaysAllowButton.action = #selector(alwaysAllowClicked)
        alwaysDenyButton.target = self
        alwaysDenyButton.action = #selector(alwaysDenyClicked)
        whyButton.target = self
        whyButton.action = #selector(whyClicked)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func startCountdown() {
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.remainingSeconds -= 1
            if self.remainingSeconds <= 0 {
                self.countdownTimer?.invalidate()
                self.countdownTimer = nil
                if !self.resolved {
                    self.resolved = true
                    self.onTimeout?()
                    self.window.close()
                }
            } else {
                self.countdownLabel.stringValue = "\(self.timeoutActionWord) in \(self.remainingSeconds)s"
                if self.remainingSeconds <= 10 {
                    self.countdownLabel.textColor = .systemOrange
                }
                if self.remainingSeconds <= 5 {
                    self.countdownLabel.textColor = .systemRed
                }
            }
        }
    }

    func close() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
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
        case "SAFE": color = .systemBlue
        case "SUSPICIOUS": color = .systemOrange
        case "DANGEROUS": color = .systemRed
        default: color = .secondaryLabelColor
        }

        auditHeader.stringValue = "SECURITY AUDIT: \(verdict.uppercased())"
        auditHeader.textColor = color
        auditLabel.stringValue = analysis
        auditLabel.isHidden = false
        auditDisclaimer.isHidden = false
    }

    /// Show the justification response from the API
    func showJustificationResponse(_ text: String) {
        whyButton.isHidden = true
        justificationResponseLabel.stringValue = text
        justificationResponseLabel.isHidden = false
    }

    /// Show that justification is unavailable
    func showJustificationUnavailable() {
        whyButton.isHidden = true
        justificationResponseLabel.stringValue = "Justification unavailable (no ANTHROPIC_API_KEY)"
        justificationResponseLabel.textColor = .tertiaryLabelColor
        justificationResponseLabel.isHidden = false
    }

    /// Show that the audit is unavailable (no API key)
    func showAuditUnavailable() {
        auditHeader.stringValue = "SECURITY AUDIT: unavailable"
        auditHeader.textColor = .tertiaryLabelColor
    }

    // MARK: - Section Header Helper

    private static func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    // MARK: - Actions

    @objc private func authenticateClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onAuthenticate?()
    }

    @objc private func alwaysAllowClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onAlwaysAllow?()
        window.close()
    }

    @objc private func alwaysDenyClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onAlwaysDeny?()
        window.close()
    }

    @objc private func whyClicked() {
        whyButton.isEnabled = false
        if let styled = whyButton as? StyledButton {
            styled.title = "  Asking...  "
        } else {
            whyButton.title = "Asking..."
        }
        onRequestJustification?()
    }

    @objc private func cancelClicked() {
        resolved = true
        countdownTimer?.invalidate()
        countdownTimer = nil
        onCancel?()
        window.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if !resolved {
            resolved = true
            onCancel?()
        }
    }
}
