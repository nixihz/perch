import AppKit
import SwiftUI

/// 统一主窗口分栏的分隔线宽度，避免 macOS 26 Liquid Glass 下标题栏跟踪线
/// 与内容区 4pt 分隔条落在不同像素列。
struct SplitDividerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> DividerStyleView { DividerStyleView() }

    func updateNSView(_ nsView: DividerStyleView, context: Context) {
        nsView.scheduleApply()
    }

    final class DividerStyleView: NSView {
        private var applyScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleApply()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleApply()
        }

        override func layout() {
            super.layout()
            scheduleApply()
        }

        fileprivate func scheduleApply() {
            guard window != nil, !applyScheduled else { return }
            applyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applyScheduled = false
                self.applyDividerStyle()
            }
        }

        private func applyDividerStyle() {
            guard let contentView = window?.contentView else { return }
            for splitView in splitViews(in: contentView) where splitView.dividerStyle != .thin {
                splitView.dividerStyle = .thin
            }
        }

        private func splitViews(in view: NSView) -> [NSSplitView] {
            [view as? NSSplitView].compactMap { $0 }
                + view.subviews.flatMap(splitViews(in:))
        }
    }
}
