# DesktopDüzen

A native macOS desktop organizer. DesktopDüzen places glass "zones" on your desktop that hold files, mirror folders, or launch apps, so the Desktop stays tidy without hiding anything from Finder.

Version 1.2.0 · macOS 13 or later · Apple silicon · Swift, AppKit, SwiftUI · MIT

![DesktopDüzen icon](Resources/AppIcon-1024.png)

## Download

[DesktopDuzen.dmg](DesktopDuzen.dmg). Open it and drag DesktopDüzen into Applications.

The app is signed with a Developer ID but not yet notarized. On first launch, right-click the app and choose Open, or allow it in System Settings > Privacy & Security.

## Features

Zone types
- Runs from the menu bar only by default, out of the Dock and Cmd-Tab. Settings > Show DesktopDüzen in the Dock brings the icon back.
- File Zones keep their files in a real folder, `~/Desktop/Zones/<zone name>`, so everything stays visible and searchable in Finder.
- Folder Zones show any existing folder (Downloads, a project, an external drive) without moving it. They follow the folder if it is renamed or moved.
- App Zones are one-click launchers for applications.

Files
- Live updates when files are added, renamed, moved or deleted in Finder. No restart needed.
- Double-click to open, Space for Quick Look, Return/Cmd-O to open the selection, Cmd-Delete to move to Trash (with confirmation).
- Drag files in from the Desktop or Finder. Moves within a volume, copies across volumes, and Option-drag always copies.
- Icon and list views, eight sort orders, drag-to-reorder in manual mode, and tabs (subfolders).
- Nothing is ever overwritten: name clashes get a number. Deleting a zone asks first, and its default keeps your files on disk.
- A missing folder (renamed, deleted, ejected drive) is shown as unavailable and reconnects automatically when it returns.

Auto-sort
- Rules route loose Desktop files into zones by extension. Each rule has an editable extension list and target zone.
- "Run Sort Now" previews what will move and offers to create missing zones. Optional continuous sorting waits until a file has finished saving.

Permanent Desktop Item Pinning ("Lock Pinned Positions")
- Permanently lock loose desktop items (files, folders, or icons) to their exact desktop coordinates.
- Pin via Menu Bar ("Pinned Desktop Items" > "Pin Desktop Item Here…"), DesktopDüzen Hub, or context menus.
- Position-locking & snapback: DesktopDüzen monitors the desktop and detects deviations caused by dragging, Finder rearrangement ("Clean Up By" / "Sort By"), or refreshes, restoring icons back to their pinned coordinates.
- Visual Indicator: An unobtrusive badge (📌) appears at the top-right corner of each pinned desktop item. Clicking the badge reveals quick options to unpin or show in Finder without interfering with Finder desktop clicks.
- Excluded from Organization: Auto-sort rules and desktop cleanup routines strictly exclude pinned items, organizing other items around them.
- Persistent: Coordinates, file paths, and display configurations are saved to `state.json` and survive app restarts, Finder restarts, logouts, and system reboots.
- Multi-Display Resilient: Coordinates are tracked per display, gracefully handling resolution changes and monitor reconnections.

Appearance
- 27 themes across Liquid Glass, Classic, Gradient, Solid and Accessibility, plus a custom colour and transparency per zone.
- Clear mode: set the background down to 0 % and turn off the border and shadow so only icons and labels float on the wallpaper. Label colour follows the wallpaper behind the zone: black text on light wallpaper, white text on dark wallpaper.
- Text colour is computed from the zone's actual background (every gradient stop and the sheen) and always meets WCAG AA contrast (4.5:1) in Light and Dark Mode.

Desktop behaviour
- Zones sit just above the desktop icons, below app windows. Optionally pin a zone above other windows.
- Title bars stay hidden until the pointer is over a zone (can be turned off in Preferences).
- Smooth dragging with edge magnetism; grid snapping applies on release. Resize by dragging any edge or corner (no visible handle).
- Align to Grid snaps every zone to the desktop grid in place; Auto-Align arranges zones in rows on each display.
- Works across Spaces, sleep/wake and display changes. A zone whose display is disconnected is shown on the main display without losing its saved position.
- Widgets: Time (clock), calendar, sticky note, real CPU/memory monitor; desktop stickers. Widgets use the same themes and transparency as zones (… menu in the widget header).
- Launch at login, menu bar controls, global search across zones (Cmd-Shift-Space).
- Clicking a zone never steals keyboard focus, so macOS and app shortcuts keep working (optional setting to let zones take focus for Space/Esc/Cmd-A shortcuts).

## Data and safety

- The layout is stored in `~/Library/Application Support/DesktopDuzen/state.json`. An unreadable file is kept as a backup, never silently overwritten.
- The app moves files only when you drag them, run a sort, or enable continuous sorting.

## Build

```bash
swift test                      # 72 tests; they use temporary folders only and never touch your Desktop
./scripts/build_app.sh          # builds and signs DesktopDuzen.app (Developer ID if available, else ad-hoc)
./scripts/create_dmg.sh         # packages and verifies DesktopDuzen-<version>.dmg
swift scripts/make_icon.swift Resources && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

## Changes in 1.2.0

- Added permanent desktop item position-locking ("Lock Desktop Items in Their Pinned Positions").
- Added desktop coordinate persistence across app restarts, Finder restarts, logouts, and reboots.
- Automatic organization and AutoSort rules strictly exclude pinned items.
- Added visual pin indicator overlay (📌) with non-interfering click-through and contextual unpin options.
- Added Menu Bar and Hub interfaces for managing pinned items, restoring positions, and unpinning.
- Multi-monitor resilience: Preserves and restores coordinates per display.

## Changes in 1.1.0

- Fixed duplicate "Active Projects N" folders, which the tests had been creating on the real Desktop.
- Fixed the layout being silently reset when the state file could not be read.
- Fixed zone dragging (jumps, trembling) and resizing (runaway growth); fixed Auto-Align not moving zones; removed z-order flicker.
- Fixed unreadable white text on light themes and in the Hub in Light Mode.
- Fixed "Duplicate" renaming files instead of copying them; zone deletion now confirms and never permanently deletes.
- Fixed auto-sort finding no target zones; added a rule editor and preview.
- Fixed widgets that could not be moved; the search field now accepts typing.
- Launch at login and "show on all Spaces" now work.
- Added liquid glass themes, a new icon, and an About screen.

## Author

Developed by SoftAI Yazılım, Assoc. Prof. Dr. Mehmet Akif Cifci ([@themanoftalent](https://github.com/themanoftalent)).
