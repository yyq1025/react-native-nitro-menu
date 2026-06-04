# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## 0.1.0 — 2026-06-03

Initial release of this fork, based on
[`react-native-nitro-contextmenu@2026.4.2`](https://github.com/vineyardbovines/react-native-nitro-contextmenu)
by Spencer Pope.

### Added

- **Working New Arch long-press lift preview.** The lifted card now renders the
  live trigger content — text included — by lifting the host view and restoring
  its index on dismiss/commit, instead of rasterizing (which dropped Fabric
  paragraph glyphs and raced to a blank card on fast reopen).
- **List safety.** The native view is hosted in a dedicated, non-collapsible
  wrapper so the lift no longer desyncs the recycler in virtualized lists
  (`FlatList` / `SectionList` / LegendList) — avoiding the New Arch "unmount a
  view which has a different index" crash. No manual wrapping required.
- **`style` prop**, forwarded to the wrapper, for cell layout (e.g. a fixed row
  height in a list).

### Changed

- Switched versioning from CalVer to SemVer.
- Rebranded to `@yyq1025/react-native-nitro-menu`. Upstream copyright and
  attribution are retained (MIT).

---

Pre-fork history (released as `react-native-nitro-contextmenu`) lives in the
[upstream changelog](https://github.com/vineyardbovines/react-native-nitro-contextmenu/blob/main/CHANGELOG.md).
