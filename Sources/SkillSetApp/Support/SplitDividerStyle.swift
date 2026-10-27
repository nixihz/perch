import AppKit
import SwiftUI

/// 原生分栏保持固定窗口边界，避免边栏开关时详情滑出窗口。
struct SplitDividerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> DividerStyleView { DividerStyleView() }

    func updateNSView(_ nsView: DividerStyleView, context: Context) {
        nsView.configureIfNeeded()
    }

    final class DividerStyleView: NSView {
        private weak var configuredSplitView: NSSplitView?
        private var collapseObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureIfNeeded()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            configureIfNeeded()
        }

        override func layout() {
            super.layout()
            configureIfNeeded()
        }

        fileprivate func configureIfNeeded() {
            guard let window, configuredSplitView?.window !== window,
                  let contentView = window.contentView,
                  let controller = navigationSplitController(in: contentView),
                  let sidebar = controller.splitViewItems.first else { return }
            controller.splitView.dividerStyle = .thin
            // 沿用现有布局约束，避免系统展开策略先撑大窗口再重排内容。
            sidebar.collapseBehavior = .useConstraints
            // SwiftUI 会恢复默认分配策略；在下一次转场开始前保持同一套约束。
            collapseObservation = sidebar.observe(\.collapseBehavior) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let controller = self?.configuredSplitView?.delegate as? NSSplitViewController,
                          let item = controller.splitViewItems.first,
                          item.collapseBehavior != .useConstraints else { return }
                    item.collapseBehavior = .useConstraints
                }
            }
            configuredSplitView = controller.splitView
        }

        private func navigationSplitController(in view: NSView) -> NSSplitViewController? {
            if let split = view as? NSSplitView,
               let controller = split.delegate as? NSSplitViewController,
               controller.splitViewItems.first?.behavior == .sidebar {
                return controller
            }
            return view.subviews.lazy.compactMap { self.navigationSplitController(in: $0) }.first
        }
    }
}
