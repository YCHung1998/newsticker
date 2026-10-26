import AppKit

/// 設定面板的內容視圖（settings-gear task 8）：把 `SettingsPanelModel.Item` 畫成 AppKit 原生控制項（NSSegmentedControl／NSSlider／NSSwitch／NSButton），
/// 每個控制項的 action 只把模型給的 `Command` 交給 `onCommand`，不含任何設定邏輯。背景：深色純色圓角（不用毛玻璃）。
/// 值更新（`reload`）在版面結構不變時**就地**更新既有控制項，因此拖動中的滑桿不會被換掉。
@MainActor
public final class SettingsPanelContentView: NSView {
    public static let panelWidth: CGFloat = 330
    private static let inset: CGFloat = 14
    private static let titleWidth: CGFloat = 78
    private static var innerWidth: CGFloat { panelWidth - inset * 2 }

    public var onCommand: (SettingsPanelModel.Command) -> Void = { _ in }
    /// 版面結構改變（高度可能不同）時呼叫，讓外層重新定位面板。
    public var onSizeChange: () -> Void = {}
    public private(set) var rebuildCount = 0
    public private(set) var items: [SettingsPanelModel.Item] = []

    private var signature: [String] = []
    private let stack = NSStackView()
    private var segmentedById: [String: NSSegmentedControl] = [:]
    private var sliderById: [String: NSSlider] = [:]
    private var valueLabelById: [String: NSTextField] = [:]
    private var switchById: [String: NSSwitch] = [:]
    private var buttonById: [String: NSButton] = [:]
    private var noticeLabel: NSTextField?
    private var detailLabel: NSTextField?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        layer?.cornerRadius = 12
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: Self.inset, left: Self.inset, bottom: Self.inset, right: Self.inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // 不用 NSLayoutConstraint 的批次啟用 API：全域守衛禁止 Sources 內出現該 API 的呼叫字樣，逐條設定 isActive 即可。
        for c in [stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                  stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                  widthAnchor.constraint(equalToConstant: Self.panelWidth)] { c.isActive = true }
    }
    public convenience init() { self.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 非啟用面板：第一次點擊就要送到控制項，不能被「先啟用視窗」吃掉。
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    /// 內容需要的大小（寬固定、高由內容決定）。
    public var contentSize: CGSize {
        layoutSubtreeIfNeeded()
        return CGSize(width: Self.panelWidth, height: fittingSize.height)
    }

    // MARK: 更新

    public func reload(_ newItems: [SettingsPanelModel.Item]) {
        let sig = SettingsPanelModel.structure(of: newItems)
        items = newItems
        if sig != signature {
            signature = sig
            rebuild()
            rebuildCount += 1
            layoutSubtreeIfNeeded()
            onSizeChange()
        } else {
            updateValues()
        }
    }

    private func rebuild() {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        segmentedById = [:]; sliderById = [:]; valueLabelById = [:]; switchById = [:]; buttonById = [:]
        noticeLabel = nil; detailLabel = nil

        let header = label("設定", size: 13, weight: .semibold, color: .labelColor)
        stack.addArrangedSubview(header)

        var buttonRow: NSStackView?
        for item in items {
            switch item {
            case .notice(let text):
                let l = wrapping(text, size: 11, color: .systemOrange)
                noticeLabel = l
                stack.addArrangedSubview(l)
            case .segmented(let id, let title, let options, let selected):
                let seg = NSSegmentedControl(labels: options.map(\.title), trackingMode: .selectOne, target: self, action: #selector(controlAction(_:)))
                seg.controlSize = .small
                seg.segmentDistribution = .fillEqually
                seg.identifier = NSUserInterfaceItemIdentifier(id)
                seg.selectedSegment = selected ?? -1
                segmentedById[id] = seg
                stack.addArrangedSubview(row(title, seg))
            case .slider(let id, let title, let sl):
                let s = NSSlider(value: sl.value, minValue: sl.range.lowerBound, maxValue: sl.range.upperBound, target: self, action: #selector(controlAction(_:)))
                s.isContinuous = true
                s.controlSize = .small
                s.identifier = NSUserInterfaceItemIdentifier(id)
                sliderById[id] = s
                let value = label(sl.valueText, size: 11, weight: .regular, color: .secondaryLabelColor)
                value.alignment = .right
                value.widthAnchor.constraint(equalToConstant: 46).isActive = true
                valueLabelById[id] = value
                stack.addArrangedSubview(row(title, s, trailing: value))
            case .toggle(let id, let title, let isOn, _):
                let sw = makeSwitch(id, on: isOn)
                stack.addArrangedSubview(row(title, sw))
            case .launchAtLogin(let title, let st):
                let sw = makeSwitch("launchAtLogin", on: st.isOn)
                stack.addArrangedSubview(row(title, sw))
                let detail = wrapping(st.detail, size: 11, color: st.isError ? .systemRed : .secondaryLabelColor)
                detailLabel = detail
                stack.addArrangedSubview(detail)
                if st.offersOpenSettings {
                    let b = makeButton("openLoginSettings", "開啟系統設定")
                    stack.addArrangedSubview(b)
                }
            case .button(let id, let title, _):
                let b = makeButton(id, title)
                // 四個按鈕一列放不下（面板寬 330）：「結束程式」另起一列，與「關閉」同列。
                if id == "quit" { buttonRow = nil }
                if buttonRow == nil {
                    let r = NSStackView()
                    r.orientation = .horizontal; r.spacing = 8; r.alignment = .centerY
                    stack.addArrangedSubview(r)
                    buttonRow = r
                }
                buttonRow?.addArrangedSubview(b)
            }
        }
    }

    private func updateValues() {
        for item in items {
            switch item {
            case .notice: break
            case .segmented(let id, _, _, let selected): segmentedById[id]?.selectedSegment = selected ?? -1
            case .slider(let id, _, let sl):
                if let s = sliderById[id], abs(s.doubleValue - sl.value) >= sl.step / 2 { s.doubleValue = sl.value }   // 拖動中的旋鈕不回彈
                valueLabelById[id]?.stringValue = sl.valueText
            case .toggle(let id, _, let isOn, _): switchById[id]?.state = isOn ? .on : .off
            case .launchAtLogin(_, let st):
                switchById["launchAtLogin"]?.state = st.isOn ? .on : .off
                detailLabel?.stringValue = st.detail
                detailLabel?.textColor = st.isError ? .systemRed : .secondaryLabelColor
            case .button: break
            }
        }
    }

    // MARK: 控制項工廠

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }
    private func wrapping(_ s: String, size: CGFloat, color: NSColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: size)
        l.textColor = color
        l.preferredMaxLayoutWidth = Self.innerWidth
        l.widthAnchor.constraint(equalToConstant: Self.innerWidth).isActive = true
        return l
    }
    private func makeSwitch(_ id: String, on: Bool) -> NSSwitch {
        let sw = NSSwitch()
        sw.controlSize = .small
        sw.state = on ? .on : .off
        sw.target = self; sw.action = #selector(controlAction(_:))
        sw.identifier = NSUserInterfaceItemIdentifier(id)
        switchById[id] = sw
        return sw
    }
    private func makeButton(_ id: String, _ title: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(controlAction(_:)))
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.identifier = NSUserInterfaceItemIdentifier(id)
        buttonById[id] = b
        return b
    }
    private func row(_ title: String, _ control: NSView, trailing: NSView? = nil) -> NSStackView {
        let t = label(title, size: 12, weight: .regular, color: .labelColor)
        t.widthAnchor.constraint(equalToConstant: Self.titleWidth).isActive = true
        let r = NSStackView(views: [t, control] + (trailing.map { [$0] } ?? []))
        r.orientation = .horizontal; r.spacing = 8; r.alignment = .centerY
        if control is NSSegmentedControl || control is NSSlider {
            r.widthAnchor.constraint(equalToConstant: Self.innerWidth).isActive = true
            control.setContentHuggingPriority(.defaultLow, for: .horizontal)
            if control is NSSegmentedControl { control.widthAnchor.constraint(equalToConstant: Self.innerWidth - Self.titleWidth - 8).isActive = true }
        }
        return r
    }

    // MARK: action

    @objc private func controlAction(_ sender: NSControl) {
        guard let id = sender.identifier?.rawValue else { return }
        if id == "openLoginSettings" { onCommand(.openLoginSettings); return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        switch item {
        case .notice: break
        case .segmented(_, _, let options, _):
            guard let seg = sender as? NSSegmentedControl, options.indices.contains(seg.selectedSegment) else { return }
            onCommand(options[seg.selectedSegment].command)
        case .slider(_, _, let sl):
            guard let s = sender as? NSSlider else { return }
            valueLabelById[id]?.stringValue = sl.text(for: s.doubleValue)
            onCommand(sl.command(for: s.doubleValue))
        case .toggle(_, _, _, let command): onCommand(command)
        case .launchAtLogin:
            guard let sw = sender as? NSSwitch else { return }
            onCommand(.setLaunchAtLogin(sw.state == .on))
        case .button(_, _, let command): onCommand(command)
        }
    }

    // MARK: 測試用存取

    public func segmented(_ id: String) -> NSSegmentedControl? { segmentedById[id] }
    public func slider(_ id: String) -> NSSlider? { sliderById[id] }
    public func toggle(_ id: String) -> NSSwitch? { switchById[id] }
    public func button(_ id: String) -> NSButton? { buttonById[id] }
    public func valueText(_ id: String) -> String? { valueLabelById[id]?.stringValue }
    public var noticeText: String? { noticeLabel?.stringValue }
    public var detailText: String? { detailLabel?.stringValue }
}

extension NSSegmentedControl {
    /// 各格標題（測試用）。
    var segmentTitles: [String] { (0..<segmentCount).map { label(forSegment: $0) ?? "" } }
}
