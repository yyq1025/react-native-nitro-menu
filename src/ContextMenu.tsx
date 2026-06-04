import React, { useMemo } from "react";
import { View } from "react-native";
import { callback, getHostComponent } from "react-native-nitro-modules";
import type { ContextMenuProps } from "./ContextMenuTypes";
import type {
  ContextMenuViewMethods,
  ContextMenuViewProps as NativeProps,
} from "./specs/ContextMenu.nitro";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const config = () => require("../nitrogen/generated/shared/json/ContextMenuViewConfig.json");

const NativeContextMenuView = getHostComponent<NativeProps, ContextMenuViewMethods>(
  "ContextMenuView",
  config
);

const noop = () => {};

export function ContextMenu({
  menuConfig,
  trigger = "tap",
  previewConfig,
  onPressAction,
  onMenuWillShow,
  onMenuWillHide,
  onPreviewPress,
  style,
  children,
}: ContextMenuProps) {
  const menuConfigJson = useMemo(
    () =>
      JSON.stringify({
        ...menuConfig,
        _trigger: trigger,
      }),
    [menuConfig, trigger]
  );

  const previewConfigJson = useMemo(() => JSON.stringify(previewConfig ?? {}), [previewConfig]);

  // Wrap the native view in a dedicated, non-collapsible host view. On iOS the
  // long-press lift reparents the native view during the menu animation; giving
  // it a parent that holds ONLY it (and is never flattened away by RN) keeps the
  // index stable so the New Arch "unmount a view which has a different index"
  // crash can't happen in a virtualized list. `style` lands on this wrapper so
  // callers can size/lay out the cell (e.g. a fixed row height).
  return (
    <View collapsable={false} style={style}>
      <NativeContextMenuView
        menuConfigJson={menuConfigJson}
        previewConfigJson={previewConfigJson}
        onPressAction={callback(onPressAction ?? noop)}
        onMenuWillShow={callback(onMenuWillShow ?? noop)}
        onMenuWillHide={callback(onMenuWillHide ?? noop)}
        onPreviewPress={callback(onPreviewPress ?? noop)}
      >
        {children}
      </NativeContextMenuView>
    </View>
  );
}
