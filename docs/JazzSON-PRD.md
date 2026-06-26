# JazzSON Product Requirements Document

Version: 1.3.0  
Date: 2026-06-25  
Platform: macOS 15 and later  
Status: Current release

## 1. Product Summary

JazzSON is a lightweight native macOS app for viewing JSON files offline. It helps users open JSON documents, inspect nested structures, expand and collapse nodes, search rendered JSON text, select and copy text from the rendered JSON pane, and preserve the original order of object members.

JazzSON is intentionally focused: it is a viewer, not an editor.

## 2. Target Users

- Users who need to inspect JSON files locally without uploading data to a web service.
- Developers, analysts, and technically comfortable users who receive minified or deeply nested JSON.
- Users who prefer standard macOS file opening, menus, windows, selection, and clipboard behavior.

## 3. Core Goals

- Open and read JSON files entirely offline.
- Register as a viewer for `.json` files so files can be opened from Finder.
- Provide a standard Open Recent menu for recently opened local files.
- Render JSON in a readable expandable tree while retaining JSON visual structure.
- Preserve the source order of JSON object members.
- Allow users to expand and collapse individual nodes.
- Allow users to expand or collapse all nodes from the menu or toolbar.
- Allow users to search rendered JSON text using standard macOS Find commands.
- Allow users to select and copy text from the rendered pane in a familiar macOS style.
- Support multiple JSON files open at the same time.
- Provide a clipboard-based way to load JSON when the app starts without a file.
- Follow standard macOS menu/window conventions.

## 4. Current Capabilities

### File Opening

- Opens `.json` and `.txt` files through File > Open.
- Supports opening `.json` and `.txt` files from Finder.
- Supports opening `.json` and `.txt` files through File > Open Recent.
- Stores up to 10 recent files.
- File > Open Recent includes Clear Menu.
- Rejects non-local URLs and unsupported file extensions before reading file contents.
- Supports opening multiple JSON files at once.
- Each opened JSON file appears in its own window unless the active window is still blank.

### Clipboard Opening

- Supports File > Open from Clipboard.
- Supports Edit > Paste and `Cmd+V` to parse JSON from the clipboard.
- If the active window is blank, pasted JSON loads into that window.
- If the active window already has JSON loaded, pasted JSON opens in a new window.
- Clipboard JSON remains offline and is parsed locally.

### JSON Rendering

- Renders JSON as an expandable text-view tree.
- Displays object keys in quotes.
- Displays JSON punctuation, including `{}`, `[]`, `:`, and commas.
- Expanded containers show opening and closing brace/bracket rows.
- Collapsed containers show `{ ... }` or `[ ... ]`.
- Closing braces and brackets align with their corresponding opening rows.
- JSON is expanded by default after loading.
- Object member order is preserved from the original JSON input.
- Duplicate object keys can be represented because parsing does not collapse objects into dictionaries.
- Windows/DOS CRLF line endings are supported.
- UTF-8 files with a byte-order mark are supported.

### Expand and Collapse

- Expandable nodes use chevrons:
  - `▾` for expanded nodes.
  - `▸` for collapsed nodes.
- Chevrons use the same monospaced font and size as the JSON text, so they occupy the same character width.
- Individual nodes can be expanded or collapsed by clicking the chevron.
- View > Expand All expands every expandable node in the active JSON window.
- View > Collapse All collapses every expandable node in the active JSON window.
- Each JSON window includes toolbar items for Expand All and Collapse All.
- Toolbar Expand All and Collapse All items use the same chevron glyph style as the JSON pane.
- The toolbar defaults to icon-only display.

### Text Selection and Copy

- The JSON pane is a read-only selectable text view.
- Users can select partial text, full lines, or multiple lines using standard macOS text selection behavior.
- Edit > Copy and `Cmd+C` copy the selected text.
- Copied text replaces JazzSON's chevrons with spaces so indentation remains stable without including UI glyphs.

### Search

- Supports standard macOS Find commands in the JSON pane.
- Edit > Find > Find... and `Cmd+F` show the native find bar.
- Edit > Find > Find Next and `Cmd+G` move to the next match.
- Edit > Find > Find Previous and `Shift+Cmd+G` move to the previous match.
- Search is normal text search over the rendered JSON text.
- Search highlights and selects matches using native AppKit text find behavior.
- Search does not alter JSON content or expand/collapse state.

### Scrolling

- The JSON pane scrolls vertically.
- The JSON pane scrolls horizontally when visible lines are wider than the window.
- Long lines are clipped rather than visually truncated with an ellipsis.

### Invalid JSON Handling

- Invalid JSON shows an alert.
- The window displays an invalid JSON message.
- Clipboard parse failures are reported without replacing valid loaded content in another window.

### Window and App Behavior

- Multiple windows are supported.
- Closing the last window does not quit the app.
- New windows can be created with File > New or `Cmd+N`.
- Windows are resizable using standard macOS behavior.
- Window title uses the opened file name, or `Clipboard JSON` for pasted content.
- JSON windows include a top toolbar with Expand All and Collapse All controls.

### Menus

- App menu:
  - About JazzSON
  - Hide JazzSON
  - Hide Others
  - Show All
  - Quit JazzSON
- File menu:
  - New
  - Open...
  - Open Recent
    - Recent files
    - Clear Menu
  - Open from Clipboard
  - Close
- Edit menu:
  - Paste
  - Find
    - Find...
    - Find Next
    - Find Previous
  - Copy
  - Select All
- View menu:
  - Expand All
  - Collapse All
  - Enter Full Screen
- Window menu:
  - Minimize
  - Zoom
- Help menu:
  - JazzSON PRD

### About Text

- About title: `JazzSON version 1.3.0`
- About body: `Built by KC Kong on Codex`

### PRD Viewer

- Help > JazzSON PRD opens this PRD from the app bundle.
- The PRD opens in a separate read-only selectable Markdown-rendered window with text wrapping.
- Normal PRD body text is rendered at 14 pt.

### App Identity

- App name: JazzSON
- Bundle identifier: `local.codex.JazzSON`
- Current version: `1.3.0`
- Minimum supported macOS version: macOS 15.0
- App icon: custom blue JazzSON icon supplied by KC.

## 5. Non-Goals for Current Version

- Editing JSON content.
- Saving modified JSON.
- Schema validation.
- Filtering JSON.
- Syntax coloring.
- Preserving original whitespace and formatting from the source file.
- Network features or cloud upload.

## 6. Technical Notes

- Implemented as a native AppKit app in Swift.
- Built as a standalone `.app` bundle using `swiftc` with optimization enabled.
- Uses a custom JSON parser to preserve object member order and duplicate keys.
- Does not use `JSONSerialization` for object tree construction because dictionary conversion loses ordering semantics.
- Treats JSON whitespace by Unicode scalar value so CRLF grapheme clusters are accepted.
- Strips a leading UTF-8 byte-order mark before parsing.
- Uses a read-only `NSTextView` renderer for native text selection and copying.
- Uses native `NSTextView` find bar behavior for normal text search.
- Uses native AppKit windows, menus, alerts, scroll views, and text views.
- Uses a native AppKit toolbar in JSON windows for common expand/collapse actions.
- Stores recent file paths locally in user defaults and caps the list at 10 entries.
- Uses an optimized `.icns` bundle generated from the supplied 1024 px icon source.
- App is ad hoc signed during local build.
- The PRD is bundled as `JazzSON-PRD.md` in app resources and rendered with native Markdown styling, inline code formatting, and text wrapping.
- The app contains no network feature and does not upload JSON content.

## 7. Quality Requirements

- Must work offline.
- Must not crash when closing the last window.
- Must not quit when closing the last window.
- Must retain JSON object member order.
- Must show invalid JSON clearly.
- Must support multiple open windows.
- Must support normal text selection and copy in the JSON pane.
- Must support standard macOS Find, Find Next, and Find Previous in the JSON pane.
- Must keep bundle size small enough for a lightweight utility.
- Must update the app version for each released build.

## 8. Known Limitations

- JazzSON is a viewer only; users cannot edit or save JSON.
- The cursor over chevrons remains the normal text-view cursor.
- Select All selects the currently focused text view, which may be the JSON pane or PRD window depending on focus.

## 9. Candidate Next Requirements

### Syntax Coloring

Potential future versions could color keys, strings, numbers, booleans, and null values while preserving text selection and expand/collapse behavior.
