import UIKit
import NitroModules

class HybridContextMenuView: HybridContextMenuViewSpec {

    // MARK: - View

    private let containerView = ContextMenuContainerView()
    var view: UIView { containerView }

    // MARK: - Props

    var menuConfigJson: String = "{}" {
        didSet { containerView.menuConfigJson = menuConfigJson }
    }

    var previewConfigJson: String = "{}" {
        didSet { containerView.previewConfigJson = previewConfigJson }
    }

    var onPressAction: (String) -> Void = { _ in } {
        didSet { containerView.onPressAction = onPressAction }
    }

    var onMenuWillShow: () -> Void = {} {
        didSet { containerView.onMenuWillShow = onMenuWillShow }
    }

    var onMenuWillHide: () -> Void = {} {
        didSet { containerView.onMenuWillHide = onMenuWillHide }
    }

    var onPreviewPress: () -> Void = {} {
        didSet { containerView.onPreviewPress = onPreviewPress }
    }
}

// MARK: - Container View

private class ContextMenuContainerView: UIView, UIContextMenuInteractionDelegate {

    private var interaction: UIContextMenuInteraction?
    private var menuButton: UIButton?
    private var tabState = TabState()
    private var trigger: String = "tap"
    /// The view the long-press interaction is attached to — the Fabric host that
    /// actually contains the RN children, NOT `self`. See `syncInteraction()`.
    private weak var interactionHost: UIView?
    /// The host view we hand to the context-menu lift, plus where it sat in its
    /// own superview. UIKit reparents the lifted view during the animation and
    /// re-seats it at the wrong index afterwards; we restore the original index
    /// when the menu ends so Fabric's child bookkeeping stays in sync (see
    /// `restoreLiftedHostIndex()`).
    private weak var liftedHost: UIView?
    private weak var liftedHostParent: UIView?
    private var liftedHostIndex: Int?

    var menuConfigJson: String = "{}" {
        didSet { configDidChange() }
    }

    var previewConfigJson: String = "{}"
    var onPressAction: (String) -> Void = { _ in } {
        didSet {
            if trigger == "tap" {
                rebuildButtonMenu()
            }
        }
    }
    var onMenuWillShow: () -> Void = {}
    var onMenuWillHide: () -> Void = {}
    var onPreviewPress: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Default trigger is "tap" — start in button mode
        switchToButtonMode()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        switchToButtonMode()
    }

    /// Attach the long-press interaction to the HOST (our superview) — the view
    /// that actually holds the RN children — rather than to `self`. `self` is a
    /// transparent sibling overlay of the content: an interaction here can't
    /// observe touches on the children, and the overlay also swallows taps, so a
    /// child `Pressable` never sees them. With the interaction on the host, the
    /// children are descendants, so long-press is observed AND a child (RNGH)
    /// `Pressable` still receives the tap — UIKit arbitrates the two by duration.
    /// Mirrors the Fabric sibling project, whose interaction view contains its
    /// children directly.
    private func syncInteraction() {
        let desiredHost: UIView? = (trigger == "longPress") ? superview : nil

        if interactionHost !== desiredHost, let interaction, let old = interactionHost {
            old.removeInteraction(interaction)
            interactionHost = nil
        }

        guard let desiredHost else {
            interaction = nil
            return
        }

        let inter = interaction ?? UIContextMenuInteraction(delegate: self)
        interaction = inter
        if interactionHost == nil {
            desiredHost.addInteraction(inter)
            interactionHost = desiredHost
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        // The host (superview) is where the interaction must live; (re)bind it
        // whenever we're (re)parented or torn down.
        syncInteraction()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // Let touches on our own empty, transparent area fall through to the
        // content sibling below, so a tap reaches the RN children's Pressable.
        // Keep hits on real subviews (the tap-mode button overlay).
        return hit === self ? nil : hit
    }

    private func configDidChange() {
        let newTrigger = MenuBuilder.parseTrigger(from: menuConfigJson)

        if newTrigger != trigger {
            trigger = newTrigger
            if trigger == "tap" {
                switchToButtonMode()
            } else {
                switchToInteractionMode()
            }
        }

        if trigger == "tap" {
            rebuildButtonMenu()
        }
    }

    private func switchToButtonMode() {
        // Drop the long-press interaction (it lives on the host, not self).
        syncInteraction()

        // Add a transparent button overlay
        if #available(iOS 14.0, *) {
            let button = UIButton(type: .system)
            button.showsMenuAsPrimaryAction = true
            button.frame = bounds
            button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.backgroundColor = .clear
            // Make the button invisible but tappable
            button.setTitle(nil, for: .normal)
            addSubview(button)
            menuButton = button
            rebuildButtonMenu()
        }
    }

    private func switchToInteractionMode() {
        // Remove button
        menuButton?.removeFromSuperview()
        menuButton = nil

        // Bind the long-press interaction to the host.
        syncInteraction()
    }

    private func rebuildButtonMenu() {
        if #available(iOS 14.0, *) {
            guard let button = menuButton else { return }
            let menu = MenuBuilder.buildMenu(
                from: menuConfigJson,
                onAction: onPressAction,
                tabState: tabState,
                onTabSelected: { [weak self] in
                    self?.handleTabSelected()
                }
            )
            button.menu = menu
        }
    }

    private func handleTabSelected() {
        if #available(iOS 16.0, *) {
            if let interaction = self.interaction {
                // Long-press mode: update the visible context menu in-place.
                interaction.updateVisibleMenu { [weak self] currentMenu in
                    guard let self = self else { return currentMenu }
                    let rebuilt = MenuBuilder.assembleMenu(
                        rootTitle: currentMenu.title,
                        tabState: self.tabState,
                        onAction: self.onPressAction,
                        onTabSelected: { [weak self] in
                            self?.handleTabSelected()
                        }
                    )
                    return currentMenu.replacingChildren(rebuilt.children)
                }
            } else if menuButton != nil {
                // Button mode: reassign the menu to refresh visible content.
                rebuildButtonMenu()
            }
        }
    }

    // MARK: - UIContextMenuInteractionDelegate

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        let previewConfig = PreviewConfigParser.parse(json: previewConfigJson)

        // Reset tab state for each new menu presentation
        tabState = TabState()

        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: previewConfig.previewType == .none ? { UIViewController() } : nil,
            actionProvider: { [weak self] _ in
                guard let self = self else { return nil }
                return MenuBuilder.buildMenu(
                    from: self.menuConfigJson,
                    onAction: self.onPressAction,
                    tabState: self.tabState,
                    onTabSelected: { [weak self] in
                        self?.handleTabSelected()
                    }
                )
            }
        )
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        onMenuWillShow()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: (any UIContextMenuInteractionAnimating)?
    ) {
        tabState = TabState()
        onMenuWillHide()
        // Restore the lifted host's index once the dismiss animation finishes —
        // after UIKit has handed it back, before the list can scroll and drive an
        // unmount.
        if let animator = animator {
            animator.addCompletion { [weak self] in
                self?.restoreLiftedHostIndex()
            }
        } else {
            restoreLiftedHostIndex()
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: any UIContextMenuInteractionCommitAnimating
    ) {
        let previewConfig = PreviewConfigParser.parse(json: previewConfigJson)

        switch previewConfig.preferredCommitStyle {
        case .dismiss:
            animator.preferredCommitStyle = .dismiss
        case .pop:
            animator.preferredCommitStyle = .pop
        }

        animator.addCompletion { [weak self] in
            self?.onPreviewPress()
            // Commit ends the menu too; restore the host index here in case
            // `willEndFor` doesn't fire on the commit path.
            self?.restoreLiftedHostIndex()
        }
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        return makeContentPreview()
    }

    // MARK: - Lift preview (lift the live host, restore it on dismiss)
    //
    // RN's New Arch flattens `<View><Text>…</View>` into *sibling* views under
    // the Nitro host (an `RCTViewComponentView`): one view paints the row
    // background, a separate `RCTParagraphComponentView` paints the text, and
    // this `containerView` sits alongside them — positioned by absolute frames,
    // so they only *look* nested. The text lives in a sibling, not inside the
    // background row.
    //
    // We lift the live `host` itself, which contains all those siblings, so
    // UIKit's own preview shows the real on-screen rendering — text included —
    // with no rasterization. (Rasterizing via `layer.render(in:)` worked but
    // raced on fast open/close: the synchronous render could catch the text
    // layer mid-redraw and produce a blank card. The live view never has that
    // gap.)
    //
    // Lifting a live view has a cost: `UITargetedPreview` reparents its target
    // during the animation and re-seats `host` at the wrong index in its
    // superview afterwards, desyncing Fabric's child bookkeeping — the "unmount
    // a view which has a different index" crash. We record host's index here and
    // restore it in `restoreLiftedHostIndex()` once the menu ends, before any
    // scroll can drive an unmount.
    private func makeContentPreview() -> UITargetedPreview? {
        guard let host = superview, host.bounds.width > 0, host.bounds.height > 0 else {
            return nil  // nothing to lift → let UIKit pick its default target
        }
        // The lift hugs the actual trigger content: the union of host's children
        // minus this container and the tap-mode button. Trims the host's
        // transparent margins and stays correct for any content — one child or
        // several (RN flattens nested views into sibling frames). Falls back to
        // the full host bounds when there's nothing to measure.
        let contentRect = host.subviews
            .filter { $0 !== self && !($0 is UIButton) }
            .reduce(CGRect.null) { $0.union($1.frame) }
        let rowRect = contentRect.isNull ? host.bounds : contentRect

        liftedHost = host
        liftedHostParent = host.superview
        liftedHostIndex = host.superview?.subviews.firstIndex(of: host)

        let previewConfig = PreviewConfigParser.parse(json: previewConfigJson)
        let parameters = UIPreviewParameters()
        // The live host carries its own content (incl. background); only override
        // the platter when the app explicitly asks for one.
        parameters.backgroundColor = previewConfig.backgroundColor ?? .clear
        parameters.visiblePath = UIBezierPath(
            roundedRect: rowRect,
            cornerRadius: previewConfig.borderRadius.map { CGFloat($0) } ?? 0
        )

        return UITargetedPreview(view: host, parameters: parameters)
    }

    /// Re-seat the lifted host at the index Fabric still expects, after the
    /// menu's dismiss/commit animation and before the list can scroll into an
    /// unmount. `insertSubview` moves it if UIKit re-seated it elsewhere, or
    /// re-adds it if UIKit detached it during the lift.
    private func restoreLiftedHostIndex() {
        defer { clearLiftedHostRefs() }
        guard let host = liftedHost,
              let parent = liftedHostParent,
              let index = liftedHostIndex
        else { return }

        if parent.subviews.firstIndex(of: host) != index {
            parent.insertSubview(host, at: min(index, parent.subviews.count))
        }
    }

    private func clearLiftedHostRefs() {
        liftedHost = nil
        liftedHostParent = nil
        liftedHostIndex = nil
    }
}

// MARK: - Tab State

private class TabState {
    struct Tab {
        let tabKey: String
        let title: String
        let image: UIImage?
        let items: [[String: Any]]
    }

    var tabs: [Tab] = []
    var selectedTabKey: String = ""
    var preferredElementSize: String?

    var hasTabs: Bool { !tabs.isEmpty }

    func selectTab(_ key: String) {
        selectedTabKey = key
    }
}

// MARK: - Menu Builder

private enum MenuBuilder {

    /// Reads the `_trigger` value from the JSON config. Defaults to `"tap"`.
    static func parseTrigger(from json: String) -> String {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "tap"
        }
        return root["_trigger"] as? String ?? "tap"
    }

    static func buildMenu(
        from json: String,
        onAction: @escaping (String) -> Void,
        tabState: TabState,
        onTabSelected: @escaping () -> Void
    ) -> UIMenu? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check for tabs in the root config
        if let tabsArray = root["tabs"] as? [[String: Any]], !tabsArray.isEmpty {
            return buildTabbedMenu(
                from: root,
                tabs: tabsArray,
                onAction: onAction,
                tabState: tabState,
                onTabSelected: onTabSelected
            )
        }

        // No tabs — existing behavior
        return parseMenu(from: root, onAction: onAction)
    }

    // MARK: - Tabbed Menu

    static func buildTabbedMenu(
        from root: [String: Any],
        tabs tabDicts: [[String: Any]],
        onAction: @escaping (String) -> Void,
        tabState: TabState,
        onTabSelected: @escaping () -> Void
    ) -> UIMenu {
        // Parse tabs into TabState
        tabState.tabs = tabDicts.map { dict in
            TabState.Tab(
                tabKey: dict["tabKey"] as? String ?? "",
                title: dict["title"] as? String ?? "",
                image: parseImage(dict["image"]),
                items: dict["items"] as? [[String: Any]] ?? []
            )
        }

        // Select first tab by default
        if tabState.selectedTabKey.isEmpty, let first = tabState.tabs.first {
            tabState.selectedTabKey = first.tabKey
        }

        tabState.preferredElementSize = root["preferredElementSize"] as? String

        return assembleMenu(
            rootTitle: root["title"] as? String ?? "",
            tabState: tabState,
            onAction: onAction,
            onTabSelected: onTabSelected
        )
    }

    static func assembleMenu(
        rootTitle: String,
        tabState: TabState,
        onAction: @escaping (String) -> Void,
        onTabSelected: @escaping () -> Void
    ) -> UIMenu {
        // --- Tab bar row ---
        let tabActions: [UIMenuElement] = tabState.tabs.map { tab in
            let isSelected = tab.tabKey == tabState.selectedTabKey

            if #available(iOS 16.0, *) {
                return UIAction(
                    title: tab.title,
                    image: tab.image,
                    identifier: UIAction.Identifier("__tab__\(tab.tabKey)"),
                    attributes: .keepsMenuPresented,
                    state: isSelected ? .on : .off,
                    handler: { _ in
                        tabState.selectTab(tab.tabKey)
                        onTabSelected()
                    }
                )
            } else {
                // iOS < 16: keepsMenuPresented unavailable, tab switching won't work
                return UIAction(
                    title: tab.title,
                    image: tab.image,
                    identifier: UIAction.Identifier("__tab__\(tab.tabKey)"),
                    state: isSelected ? .on : .off,
                    handler: { _ in }
                )
            }
        }

        var tabBarMenu: UIMenu
        if #available(iOS 16.0, *) {
            tabBarMenu = UIMenu(
                title: "",
                identifier: UIMenu.Identifier("__tabBar__"),
                options: .displayInline,
                children: tabActions
            )
            tabBarMenu.preferredElementSize = parseElementSize(tabState.preferredElementSize)
        } else {
            tabBarMenu = UIMenu(
                title: "",
                identifier: UIMenu.Identifier("__tabBar__"),
                options: .displayInline,
                children: tabActions
            )
        }

        // --- Content items from selected tab ---
        let contentChildren: [UIMenuElement]
        if let selectedTab = tabState.tabs.first(where: { $0.tabKey == tabState.selectedTabKey }) {
            contentChildren = selectedTab.items.compactMap { item in
                parseElement(from: item, onAction: onAction)
            }
        } else {
            contentChildren = []
        }

        // --- Root menu ---
        var rootChildren: [UIMenuElement] = []
        if #available(iOS 16.0, *) {
            rootChildren.append(tabBarMenu)
        }

        // Content must be wrapped in a .displayInline group so
        // updateVisibleMenu can properly replace it during tab switches.
        let contentMenu = UIMenu(
            title: "",
            identifier: UIMenu.Identifier("__content__"),
            options: .displayInline,
            children: contentChildren
        )
        rootChildren.append(contentMenu)

        return UIMenu(title: rootTitle, children: rootChildren)
    }

    // MARK: - Standard Menu (unchanged)

    static func parseMenu(from dict: [String: Any], onAction: @escaping (String) -> Void) -> UIMenu {
        let title = dict["title"] as? String ?? ""
        let subtitle = dict["subtitle"] as? String
        let image = parseImage(dict["image"])
        let options = parseMenuOptions(dict["options"] as? [String])
        let items = dict["items"] as? [[String: Any]] ?? []

        let children: [UIMenuElement] = items.compactMap { item in
            parseElement(from: item, onAction: onAction)
        }

        let menu = UIMenu(
            title: title,
            image: image,
            options: options,
            children: children
        )

        if let subtitle = subtitle {
            if #available(iOS 15.0, *) {
                menu.subtitle = subtitle
            }
        }

        if #available(iOS 16.0, *) {
            menu.preferredElementSize = parseElementSize(dict["preferredElementSize"] as? String)
        }

        return menu
    }

    static func parseElement(from dict: [String: Any], onAction: @escaping (String) -> Void) -> UIMenuElement? {
        // If it has "items", it's a submenu (MenuConfig)
        if dict["items"] != nil {
            return parseMenu(from: dict, onAction: onAction)
        }

        // If it has "actionKey", it's a leaf action (MenuAction)
        if let actionKey = dict["actionKey"] as? String {
            return parseAction(from: dict, actionKey: actionKey, onAction: onAction)
        }

        return nil
    }

    static func parseAction(
        from dict: [String: Any],
        actionKey: String,
        onAction: @escaping (String) -> Void
    ) -> UIAction {
        let title = dict["title"] as? String ?? ""
        let subtitle = dict["subtitle"] as? String
        let image = parseImage(dict["image"])
        let selectedImage = parseImage(dict["selectedImage"])
        let attributes = parseActionAttributes(dict["attributes"] as? [String])
        let state = parseState(dict["state"] as? String)
        let discoverabilityTitle = dict["discoverabilityTitle"] as? String

        let action: UIAction
        if #available(iOS 17.0, *) {
            action = UIAction(
                title: title,
                subtitle: subtitle,
                image: image,
                selectedImage: selectedImage,
                identifier: UIAction.Identifier(actionKey),
                discoverabilityTitle: discoverabilityTitle,
                attributes: attributes,
                state: state,
                handler: { _ in onAction(actionKey) }
            )
        } else if #available(iOS 15.0, *) {
            action = UIAction(
                title: title,
                subtitle: subtitle,
                image: image,
                identifier: UIAction.Identifier(actionKey),
                discoverabilityTitle: discoverabilityTitle,
                attributes: attributes,
                state: state,
                handler: { _ in onAction(actionKey) }
            )
        } else {
            action = UIAction(
                title: title,
                image: image,
                identifier: UIAction.Identifier(actionKey),
                discoverabilityTitle: discoverabilityTitle,
                attributes: attributes,
                state: state,
                handler: { _ in onAction(actionKey) }
            )
        }

        return action
    }

    // MARK: - Parsers

    static func parseImage(_ value: Any?) -> UIImage? {
        guard let dict = value as? [String: Any] else { return nil }

        if let systemName = dict["systemName"] as? String {
            return UIImage(systemName: systemName)
        }

        // URL images loaded asynchronously could be supported in the future
        return nil
    }

    static func parseActionAttributes(_ values: [String]?) -> UIMenuElement.Attributes {
        guard let values = values else { return [] }
        var attrs: UIMenuElement.Attributes = []
        for value in values {
            switch value {
            case "destructive": attrs.insert(.destructive)
            case "disabled": attrs.insert(.disabled)
            case "hidden": attrs.insert(.hidden)
            case "keepsMenuPresented":
                if #available(iOS 16.0, *) {
                    attrs.insert(.keepsMenuPresented)
                }
            default: break
            }
        }
        return attrs
    }

    static func parseState(_ value: String?) -> UIMenuElement.State {
        switch value {
        case "on": return .on
        case "mixed": return .mixed
        default: return .off
        }
    }

    static func parseMenuOptions(_ values: [String]?) -> UIMenu.Options {
        guard let values = values else { return [] }
        var opts: UIMenu.Options = []
        for value in values {
            switch value {
            case "displayInline": opts.insert(.displayInline)
            case "destructive": opts.insert(.destructive)
            case "singleSelection":
                if #available(iOS 15.0, *) {
                    opts.insert(.singleSelection)
                }
            case "displayAsPalette":
                if #available(iOS 17.0, *) {
                    opts.insert(.displayAsPalette)
                }
            default: break
            }
        }
        return opts
    }

    @available(iOS 16.0, *)
    static func parseElementSize(_ value: String?) -> UIMenu.ElementSize {
        switch value {
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        default: return .large
        }
    }
}

// MARK: - Preview Config Parser

private struct ParsedPreviewConfig {
    enum PreviewType { case view, none }
    enum CommitStyle { case pop, dismiss }

    var previewType: PreviewType = .view
    var preferredCommitStyle: CommitStyle = .pop
    var backgroundColor: UIColor?
    var borderRadius: Double?
}

private enum PreviewConfigParser {

    static func parse(json: String) -> ParsedPreviewConfig {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedPreviewConfig()
        }

        var config = ParsedPreviewConfig()

        if let previewType = dict["previewType"] as? String {
            config.previewType = previewType == "none" ? .none : .view
        }

        if let commitStyle = dict["preferredCommitStyle"] as? String {
            config.preferredCommitStyle = commitStyle == "dismiss" ? .dismiss : .pop
        }

        if let bgColorHex = dict["backgroundColor"] as? String {
            config.backgroundColor = UIColor(hex: bgColorHex)
        }

        if let radius = dict["borderRadius"] as? Double {
            config.borderRadius = radius
        }

        return config
    }
}

// MARK: - UIColor Hex Extension

private extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count
        switch length {
        case 6:
            self.init(
                red: CGFloat((rgb & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgb & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgb & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        case 8:
            self.init(
                red: CGFloat((rgb & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgb & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }
}
