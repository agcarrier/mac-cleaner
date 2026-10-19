# Spruce polish pass, round 1

2026-10-19. Andrew: "I just want it to look polished. As of now the app has a lot of dead space on the left. You can make changes
as you see fit." All calls below are Claude's, within direction C; Andrew reviews them in the app.

## What changed

- **Sidebar:** tools grouped under Clean (Smart Care, Cleanup, Space), Manage (Applications, Performance, My Clutter) and Tools
  (Screen Clean), plus a storage card pinned at the bottom (startup disk name, a bar, free of total; refreshes once a minute;
  click to open Space). This was the "dead space on the left": seven rows at the top of an empty column.
- **Toolbar:** no background, so each tool's wash glows from the very top; the toolbar title is removed on macOS 15+ because the
  header already names the tool (the window keeps its title for the Window menu).
- **Tint:** the detail view takes the tool's color, so prominent buttons, switches and progress bars match it instead of grey.
- **Two layouts:** start, progress, empty and done screens are one centered group (big glyph, title, subtitle, then the content);
  list screens (scan results, Applications, Performance, Updates results) use a compact leading header so the list gets the room.
- **Start screens** for Smart Care, Cleanup and Space show a two-column grid of what the scan covers.
- **Cards:** lists sit in a soft panel with a hairline border (`.card()`); the Screen Clean explainer uses it too.
- Empty and done states get a tinted checkmark.

## Not changed

Colors, icons, typography scale, the disk map, the menu bar item, and every behavior.
