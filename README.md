# @yyq1025/react-native-nitro-menu

Native iOS & Android menus built with [Nitro Modules](https://nitro.margelo.com) — tap menus and long-press context menus with a working lift preview. Supports actions, submenus, selection state, inline groups, palettes, and tabbed menus.

> **Fork of [`react-native-nitro-contextmenu`](https://github.com/vineyardbovines/react-native-nitro-contextmenu) by Spencer Pope.** What this fork adds:
>
> - **A working New Arch long-press lift preview.** The lifted card now renders the live trigger content — text included — instead of a blank/partial snapshot.
> - **Safe inside virtualized lists** (`FlatList` / `SectionList` / LegendList). The native view is hosted in a dedicated, non-collapsible wrapper so the lift can't desync the recycler and trip the "unmount a view which has a different index" crash. See [Use in lists](#use-in-lists).
>
> MIT-licensed; original copyright retained.

<p align="center">
  <img src="./assets/ios-demo.gif" alt="iOS Demo" width="300" />
  <img src="./assets/android-demo.gif" alt="Android Demo" width="300" />
</p>

## Installation

```sh
npm install @yyq1025/react-native-nitro-menu react-native-nitro-modules
```

For iOS, install pods:

```sh
cd ios && pod install
```

Android requires no additional setup.

## Quick Start

```tsx
import { ContextMenu } from "@yyq1025/react-native-nitro-menu";
import type { MenuConfig } from "@yyq1025/react-native-nitro-menu";

function MyComponent() {
  const menuConfig: MenuConfig = {
    title: "",
    items: [
      { actionKey: "copy", title: "Copy", image: { systemName: "doc.on.doc" } },
      { actionKey: "paste", title: "Paste", image: { systemName: "doc.on.clipboard" } },
      {
        actionKey: "delete",
        title: "Delete",
        image: { systemName: "trash" },
        attributes: ["destructive"],
      },
    ],
  };

  return (
    <ContextMenu menuConfig={menuConfig} onPressAction={(key) => console.log("Selected:", key)}>
      <View style={{ padding: 20 }}>
        <Text>Tap me</Text>
      </View>
    </ContextMenu>
  );
}
```

## Use in lists

`ContextMenu` is safe to render directly as a list cell — no manual wrapping required. The component already hosts the native view in a dedicated, non-collapsible wrapper, which keeps the long-press lift from desyncing the list recycler (the New Arch "unmount a view which has a different index" crash). Put your cell layout (e.g. a fixed row height) on the `style` prop:

```tsx
<SectionList
  sections={sections}
  renderItem={({ item }) => (
    <ContextMenu
      trigger="longPress"
      menuConfig={rowMenu(item)}
      previewConfig={{ previewType: "view", borderRadius: 10, preferredCommitStyle: "dismiss" }}
      onPressAction={onAction}
      style={{ height: 52 }}
    >
      <View style={styles.row}>
        <Text>{item.title}</Text>
      </View>
    </ContextMenu>
  )}
/>
```

> Using a CSS-in-JS library (NativeWind / uniwind)? Register the component once so `className` maps to `style`: `cssInterop(ContextMenu, { className: "style" })`. The library itself stays styling-agnostic and only accepts a plain `style`.

## Tappable triggers

A `longPress` trigger and a tap coexist — handy for rows that open on tap and show a menu on long-press. Put a `Pressable` as the trigger content: a tap fires its `onPress`, a long-press opens the menu (iOS arbitrates the two by duration).

Use [`react-native-gesture-handler`](https://docs.swmansion.com/react-native-gesture-handler/)'s `Pressable`, **not** React Native's — RN's `Pressable` loses the tap to the native long-press, whereas RNGH's native recognizer arbitrates correctly. Wrap your app (or screen) in `GestureHandlerRootView`.

```tsx
import { Pressable } from "react-native-gesture-handler";

<ContextMenu trigger="longPress" menuConfig={rowMenu(item)} style={{ height: 52 }}>
  <Pressable onPress={() => openItem(item)} style={styles.row}>
    <Text>{item.title}</Text>
  </Pressable>
</ContextMenu>;
```

## Props

| Prop              | Type                          | Description                                               |
| ----------------- | ----------------------------- | --------------------------------------------------------- |
| `menuConfig`      | `MenuConfig`                  | **Required.** The menu structure to display.                    |
| `trigger`         | `'tap' \| 'longPress'`        | How the menu is triggered. Default: `'tap'`.                    |
| `onPressAction`   | `(actionKey: string) => void` | Called when a menu action is selected.                          |
| `onMenuWillShow`  | `() => void`                  | Called when the menu is about to appear.                  |
| `onMenuWillHide`  | `() => void`                  | Called when the menu is about to disappear.               |
| `onPreviewPress`  | `() => void`                  | Called when the user taps the preview (iOS only).         |
| `previewConfig`   | `PreviewConfig`               | Customize the preview appearance (iOS only).              |
| `style`           | `StyleProp<ViewStyle>`        | Style for the wrapper around the trigger content. Use it to size/lay out the cell (e.g. a fixed row height in a list). |
| `children`        | `ReactNode`                   | **Required.** The trigger content.                        |

## Menu Configuration

### MenuConfig

The root menu and any submenus share the same shape:

```ts
interface MenuConfig {
  title?: string;
  subtitle?: string; // iOS only
  image?: SystemImage;
  options?: MenuOption[];
  preferredElementSize?: "small" | "medium" | "large"; // iOS 16+
  tabs?: MenuTab[]; // iOS 16+ — when present, items is ignored
  items: MenuElement[];
}
```

### MenuAction

Leaf actions that appear as tappable rows:

```ts
interface MenuAction {
  actionKey: string; // Unique key returned in onPressAction
  title: string;
  subtitle?: string; // iOS 15+
  image?: MenuImage; // SF Symbol or URL
  selectedImage?: SystemImage; // Icon when state is 'on' (iOS 17+)
  attributes?: MenuElementAttribute[];
  state?: "on" | "off" | "mixed";
  discoverabilityTitle?: string; // iOS only
}
```

### MenuElement

A union of `MenuAction | MenuConfig`. The native side discriminates by checking for `actionKey` (action) vs `items` (submenu).

### Images

```ts
// SF Symbol (iOS native, mapped to Android system drawables)
{
  systemName: "star.fill";
}

// URL image (iOS only)
{
  url: "https://example.com/icon.png";
}
```

On Android, common SF Symbol names are automatically mapped to equivalent `android.R.drawable` icons. You can also provide your own drawables by adding resources named with dots replaced by underscores (e.g. `doc_on_doc.xml` for `doc.on.doc`).

### Options

Applied to `MenuConfig.options`:

| Option               | iOS                                            | Android                                           |
| -------------------- | ---------------------------------------------- | ------------------------------------------------- |
| `'displayInline'`    | Renders children inline with a separator.      | Items added to parent menu with group separators. |
| `'destructive'`      | Renders the submenu title in red.              | No visual change.                                 |
| `'singleSelection'`  | Only one child can be `state: 'on'` at a time. | Exclusive checkable group.                        |
| `'displayAsPalette'` | Renders children as a horizontal icon row.     | No effect (renders as normal items).              |

### Attributes

Applied to `MenuAction.attributes`:

| Attribute              | iOS                                      | Android                   |
| ---------------------- | ---------------------------------------- | ------------------------- |
| `'destructive'`        | Red text and icon.                       | Icon tinted red.          |
| `'disabled'`           | Grayed out, not tappable.                | Grayed out, not tappable. |
| `'hidden'`             | Not visible in the menu.                 | Not visible in the menu.  |
| `'keepsMenuPresented'` | Menu stays open after tapping (iOS 16+). | No effect.                |

## Examples

### Submenus

Nest `MenuConfig` objects inside `items` to create submenus:

```tsx
const menuConfig: MenuConfig = {
  title: "",
  items: [
    {
      title: "Sort By",
      image: { systemName: "arrow.up.arrow.down" },
      items: [
        { actionKey: "sort-name", title: "Name" },
        { actionKey: "sort-date", title: "Date" },
        { actionKey: "sort-size", title: "Size" },
      ],
    },
  ],
};
```

### Single Selection

Use `singleSelection` with `state` to create radio-style groups:

```tsx
const [selected, setSelected] = useState('medium')

const menuConfig: MenuConfig = {
  title: 'Text Size',
  items: [
    {
      title: '',
      options: ['displayInline', 'singleSelection'],
      items: [
        { actionKey: 'small', title: 'Small', state: selected === 'small' ? 'on' : 'off' },
        { actionKey: 'medium', title: 'Medium', state: selected === 'medium' ? 'on' : 'off' },
        { actionKey: 'large', title: 'Large', state: selected === 'large' ? 'on' : 'off' },
      ],
    },
  ],
}

<ContextMenu menuConfig={menuConfig} onPressAction={setSelected}>
  {/* ... */}
</ContextMenu>
```

### Inline Groups with Separators

Use `displayInline` to show items in the same level with visual separators, and `preferredElementSize: 'small'` for compact icon rows (iOS only):

```tsx
const menuConfig: MenuConfig = {
  title: "",
  items: [
    {
      title: "",
      options: ["displayInline"],
      preferredElementSize: "small",
      items: [
        { actionKey: "cut", title: "Cut", image: { systemName: "scissors" } },
        { actionKey: "copy", title: "Copy", image: { systemName: "doc.on.doc" } },
        { actionKey: "paste", title: "Paste", image: { systemName: "doc.on.clipboard" } },
      ],
    },
    { actionKey: "select-all", title: "Select All", image: { systemName: "selection.pin.in.out" } },
  ],
};
```

### Palette (iOS only)

Use `displayAsPalette` for a horizontal icon strip (e.g. color pickers). On Android, items render as a normal list.

```tsx
const menuConfig: MenuConfig = {
  title: "Color",
  items: [
    {
      title: "",
      options: ["displayInline", "displayAsPalette"],
      items: [
        { actionKey: "red", title: "Red", image: { systemName: "circle.fill" } },
        { actionKey: "green", title: "Green", image: { systemName: "circle.fill" } },
        { actionKey: "blue", title: "Blue", image: { systemName: "circle.fill" } },
      ],
    },
  ],
};
```

### Destructive & Disabled Actions

```tsx
const menuConfig: MenuConfig = {
  title: "",
  items: [
    { actionKey: "edit", title: "Edit", image: { systemName: "pencil" } },
    { actionKey: "archive", title: "Archive", attributes: ["disabled"] },
    {
      title: "",
      options: ["displayInline"],
      items: [
        {
          actionKey: "delete",
          title: "Delete",
          image: { systemName: "trash" },
          attributes: ["destructive"],
        },
      ],
    },
  ],
};
```

### Tabbed Menu (iOS 16+)

Tabs display a row of buttons at the top of the menu. Tapping a tab swaps the items below without dismissing the menu. When `tabs` is provided, `items` is ignored.

```tsx
const menuConfig: MenuConfig = {
  title: "",
  tabs: [
    {
      tabKey: "sort",
      title: "Sort",
      image: { systemName: "arrow.up.arrow.down" },
      items: [
        { actionKey: "sort-name", title: "Name" },
        { actionKey: "sort-date", title: "Date" },
        { actionKey: "sort-size", title: "Size" },
      ],
    },
    {
      tabKey: "filter",
      title: "Filter",
      image: { systemName: "line.3.horizontal.decrease" },
      items: [
        { actionKey: "filter-images", title: "Images" },
        { actionKey: "filter-videos", title: "Videos" },
      ],
    },
  ],
  items: [],
};
```

On iOS < 16 and on Android, the tab bar is omitted and the first tab's items are shown as a flat menu.

### Trigger Mode

By default, the menu opens on a single tap. Use `trigger="longPress"` for long-press with preview (iOS):

```tsx
<ContextMenu menuConfig={menuConfig} trigger="longPress">
  <View>
    <Text>Long press me</Text>
  </View>
</ContextMenu>
```

On iOS, no preview is shown when `trigger` is `'tap'`.

### Preview Configuration (iOS only)

Customize the context menu preview. This has no effect on Android.

```tsx
<ContextMenu
  menuConfig={menuConfig}
  previewConfig={{
    previewType: "view", // 'view' (default) or 'none'
    preferredCommitStyle: "pop", // 'pop' (default) or 'dismiss'
    backgroundColor: "#ffffff",
    borderRadius: 16,
  }}
  onPreviewPress={() => console.log("Preview tapped")}
>
  {/* ... */}
</ContextMenu>
```

## Type Exports

All types are exported for use in your own code:

```ts
import type {
  ContextMenuProps,
  MenuConfig,
  MenuAction,
  MenuElement,
  MenuTab,
  MenuOption,
  MenuElementAttribute,
  MenuElementSize,
  MenuElementState,
  MenuImage,
  SystemImage,
  UrlImage,
  PreviewConfig,
} from "@yyq1025/react-native-nitro-menu";
```

## Platform Support

### Feature matrix

| Feature              | iOS                                        | Android                      |
| -------------------- | ------------------------------------------ | ---------------------------- |
| Actions with icons   | SF Symbols + URL images                    | Mapped system drawables      |
| Submenus             | Nested menus                               | Nested menus                 |
| Inline groups        | Separator + inline items                   | Group separators             |
| Single selection     | Checkmarks                                 | Checkmarks                   |
| Destructive style    | Red text + icon                            | Red icon tint                |
| Disabled items       | Grayed out                                 | Grayed out                   |
| Hidden items         | Excluded                                   | Excluded                     |
| Trigger mode         | `trigger="tap"` (default) or `"longPress"` | `trigger="tap"` or `"longPress"` |
| Tabbed menus         | Tab bar + swappable content (iOS 16+)      | First tab shown as flat menu |
| Palette mode         | Horizontal icon row (iOS 17+)              | Normal menu items            |
| Preview              | Customizable preview with commit styles    | Not supported                |
| Subtitles            | Below action title (iOS 15+)               | Not supported                |
| `keepsMenuPresented` | Menu stays open (iOS 16+)                  | Not supported                |
| `selectedImage`      | Alternate icon for checked state (iOS 17+) | Not supported                |

### iOS version requirements

| Feature                                                    | Minimum iOS |
| ---------------------------------------------------------- | ----------- |
| Context menus                                              | 13.0        |
| Subtitles                                                  | 15.0        |
| `keepsMenuPresented`, `preferredElementSize`, tabbed menus | 16.0        |
| `displayAsPalette`, `selectedImage`                        | 17.0        |

Features are gracefully skipped on older iOS versions and unsupported Android features.

## Credits

Fork of [`react-native-nitro-contextmenu`](https://github.com/vineyardbovines/react-native-nitro-contextmenu) by [Spencer Pope](https://github.com/vineyardbovines). All of the original menu engine, Nitro wiring, and cross-platform work is his; this fork adds the New Arch lift-preview fix and list safety described above.

## License

MIT © [Spencer Pope](https://github.com/vineyardbovines) (original) and [Yueqian Yang](https://github.com/yyq1025) (modifications). See [LICENSE](./LICENSE).
