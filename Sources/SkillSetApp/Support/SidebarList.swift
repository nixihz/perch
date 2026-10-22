import AppKit
import SwiftUI

struct SidebarList: NSViewRepresentable {
    @Binding var selection: NavigationItem
    let skillCount: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, skillCount: skillCount)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("destination"))
        table.addTableColumn(column)
        table.headerView = nil
        // sourceList 在真实窗口中会叠加系统高亮，plain 才能让自定义行完整控制品牌选中态。
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setAccessibilityLabel(L10n.tr("侧边栏导航"))

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        context.coordinator.selection = $selection
        context.coordinator.skillCount = skillCount
        table.setAccessibilityLabel(L10n.tr("侧边栏导航"))
        table.allowsEmptySelection = selection == .settings
        if selection == .settings {
            table.deselectAll(nil)
        }
        if let row = Coordinator.rows.firstIndex(where: { $0.item == selection }),
           table.selectedRow != row {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        context.coordinator.refreshCells(in: table)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        guard let table = scroll.documentView as? NSTableView else { return }
        table.delegate = nil
        table.dataSource = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        struct Row {
            let heading: String?
            let item: NavigationItem?
        }

        static let rows: [Row] = NavigationItem.groups.flatMap { group in
            [Row(heading: group.title, item: nil)] + group.items.map { Row(heading: nil, item: $0) }
        }

        var selection: Binding<NavigationItem>
        var skillCount: Int

        init(selection: Binding<NavigationItem>, skillCount: Int) {
            self.selection = selection
            self.skillCount = skillCount
        }

        func numberOfRows(in tableView: NSTableView) -> Int { Self.rows.count }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            Self.rows[row].heading != nil
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            Self.rows[row].item != nil
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            Self.rows[row].item == nil ? 30 : 52
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SidebarSelectionRow()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let entry = Self.rows[row]
            if let item = entry.item {
                let cell = SidebarDestinationCell()
                configure(cell, item: item, selected: tableView.selectedRow == row)
                return cell
            }
            let label = NSTextField(labelWithString: L10n.text(entry.heading ?? ""))
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .secondaryLabelColor
            return label
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let table = notification.object as? NSTableView,
                  Self.rows.indices.contains(table.selectedRow),
                  let item = Self.rows[table.selectedRow].item else { return }
            if selection.wrappedValue != item {
                selection.wrappedValue = item
            }
            refreshCells(in: table)
        }

        func refreshCells(in table: NSTableView) {
            for row in Self.rows.indices {
                if let item = Self.rows[row].item,
                   let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? SidebarDestinationCell {
                    configure(cell, item: item, selected: row == table.selectedRow)
                } else if let heading = Self.rows[row].heading,
                          let label = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTextField {
                    label.stringValue = L10n.text(heading)
                }
            }
        }

        private func configure(_ cell: SidebarDestinationCell, item: NavigationItem, selected: Bool) {
            cell.titleLabel.stringValue = item.title
            cell.subtitleLabel.stringValue = item == .skills ? L10n.tr("\(skillCount) 个技能，可搜索和编辑") : item.subtitle
            cell.icon.image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: nil)
            cell.titleLabel.textColor = NSColor(selected ? AppColor.onSelection : AppColor.ink)
            cell.subtitleLabel.textColor = selected ? NSColor(AppColor.onSelection) : .secondaryLabelColor
            cell.icon.contentTintColor = NSColor(selected ? AppColor.onSelection : AppColor.accentText)
            cell.setAccessibilityLabel("\(item.title)，\(cell.subtitleLabel.stringValue)")
            cell.toolTip = "\(item.title)\n\(cell.subtitleLabel.stringValue)"
        }
    }
}

final class SidebarSelectionRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        NSColor(AppColor.selection).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 7, yRadius: 7).fill()
    }
}

final class SidebarDestinationCell: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.font = .systemFont(ofSize: 13)
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        for view in [icon, labels] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 19),
            icon.heightAnchor.constraint(equalToConstant: 19),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            // 让文本字段跟随行宽收缩，省略号才能在实际可见边界内绘制。
            titleLabel.trailingAnchor.constraint(equalTo: labels.trailingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: labels.trailingAnchor),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        textField = titleLabel
        imageView = icon
    }

    required init?(coder: NSCoder) { nil }
}
