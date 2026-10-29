import AppKit
import SwiftUI

/// 扩大控件本身的命中范围，避免只有外层占位变高。
struct AppCheckboxStyle: ToggleStyle {
    var showsLabel = true

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(configuration.isOn ? AppColor.accentText : .secondary)
                    .frame(width: AppControl.iconTarget, height: AppControl.height)
                    .accessibilityHidden(true)
                if showsLabel { configuration.label }
            }
            .frame(minHeight: AppControl.height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppPressButtonStyle())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}

/// 保留原生分段的键盘与辅助功能行为，额外的按钮覆盖原生单元格以外的留白。
struct AppSegmentedPicker<Selection: Hashable>: NSViewRepresentable {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(picker: self) }

    func makeNSView(context: Context) -> SegmentedHitView {
        let view = SegmentedHitView()
        view.control.target = context.coordinator
        view.control.action = #selector(Coordinator.selectSegment(_:))
        return view
    }

    func updateNSView(_ view: SegmentedHitView, context: Context) {
        context.coordinator.picker = self
        view.update(labels: options.map(\.1), selected: options.firstIndex { $0.0 == selection } ?? -1,
                    enabled: isEnabled, title: title)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SegmentedHitView, context: Context) -> CGSize? {
        CGSize(width: max(proposal.width ?? nsView.control.intrinsicContentSize.width,
                          CGFloat(options.count) * AppControl.iconTarget), height: AppControl.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var picker: AppSegmentedPicker

        init(picker: AppSegmentedPicker) { self.picker = picker }

        @objc func selectSegment(_ control: NSSegmentedControl) {
            guard picker.options.indices.contains(control.selectedSegment) else { return }
            picker.selection = picker.options[control.selectedSegment].0
        }
    }
}

final class SegmentedHitView: NSView {
    let control = KeyboardSegmentedControl()
    private var targets: [NSButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.controlSize = .regular
        control.font = .systemFont(ofSize: 13, weight: .medium)
        addSubview(control)
        // 辅助技术只看到原生分段，避免每个选项重复出现两次。
        setAccessibilityChildren([control])
    }

    required init?(coder: NSCoder) { nil }

    func update(labels: [String], selected: Int, enabled: Bool, title: String) {
        control.segmentCount = labels.count
        for (index, label) in labels.enumerated() { control.setLabel(label, forSegment: index) }
        control.selectedSegment = selected
        control.isEnabled = enabled
        control.setAccessibilityLabel(title)
        if targets.count != labels.count {
            targets.forEach { $0.removeFromSuperview() }
            targets = labels.indices.map { index in
                let button = NSButton(title: "", target: self, action: #selector(selectTarget(_:)))
                button.tag = index
                button.isTransparent = true
                button.isBordered = false
                button.refusesFirstResponder = true
                button.setAccessibilityElement(false)
                addSubview(button)
                return button
            }
        }
        targets.forEach { $0.isEnabled = enabled }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        control.frame = bounds
        let segmentWidth = bounds.width / CGFloat(max(targets.count, 1))
        for (index, target) in targets.enumerated() {
            target.frame = NSRect(x: CGFloat(index) * segmentWidth, y: 0,
                                  width: segmentWidth, height: bounds.height)
        }
    }

    @objc private func selectTarget(_ sender: NSButton) {
        guard control.isEnabled else { return }
        control.selectedSegment = sender.tag
        window?.makeFirstResponder(control)
        _ = control.sendAction(control.action, to: control.target)
    }
}

final class KeyboardSegmentedControl: NSSegmentedControl {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard isEnabled, segmentCount > 0, modifiers.isEmpty, [123, 124].contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        // 鼠标扩大命中后仍把焦点交还原生控件；方向键须同步草稿，不能只移动单元格的焦点。
        let next = min(max(selectedSegment + (event.keyCode == 123 ? -1 : 1), 0), segmentCount - 1)
        guard next != selectedSegment else { return }
        selectedSegment = next
        _ = sendAction(action, to: target)
    }
}
