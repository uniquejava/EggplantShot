# EggplantShot — User guide

Menu-bar screenshot tool for macOS (Snipaste-style capture → annotate → pin / **paste clipboard as floating pin**).

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Global hotkeys |
| **Screen Recording** | Capture |

Without Accessibility, hotkeys do nothing. Without Screen Recording, capture fails with a prompt.

## Capture

| Action | Default |
|--------|---------|
| **Capture** | `F1` |
| **Capture and copy** | `⌘F1` |

**Capture:** Displays freeze; hover highlights the window under the cursor; click to lock or drag to free-select; refine the blue rect, annotate if you want, then **Pin** / **Copy** / **Save**. **Return** confirms Pin. **Esc** cancels.

**Capture and copy:** Same freeze + hover/drag select; as soon as you lock a window or finish a drag, the crop is copied to the clipboard (no toolbar / annotate). **Esc** cancels while selecting.

Menu bar → **Disable hotkeys** pauses global shortcuts (persisted).

## Paste (highlight)

| Action | Default |
|--------|---------|
| **Paste** | `F3` |

This is **not** the system Paste into another app. EggplantShot turns whatever is on the clipboard into a **floating pin** on your screen (Snipaste-style “paste as image window”).

| Clipboard content | What you get |
|-------------------|--------------|
| Image (e.g. after **Capture and copy**) | Pinned bitmap |
| Color text — `#RRGGBB` / `#RGB`, or three RGB numbers `0–255` or `0–1` | Color swatch card with the value labeled |
| Plain text or HTML | Text rendered as a small sticky image |
| Copied **image file** (Finder) | The image itself; press **Paste** again → path as text |
| Copied non-image file | File path as text image |

Pin appears near the mouse. Works from the menu bar **Paste** item too. Ignored while a capture overlay is active.

**Try this:** `⌘F1` a region → `F3` to float it as a reference while you work in another window. Or copy `#3B82F6` / a paragraph → `F3` for a color card or text sticky.

## Pins

Floating image above ordinary windows. Drag to move. Scroll wheel zooms ±10% (brief % badge in the top-left). **Esc** or double-click closes that pin only. **Hide/Show all images** (`⇧F3`) hides or restores every pin.

## Annotate (during refine)

Toolbar under the selection: move, shape, arrow, pencil, marker, mosaic (blur / pixelate), text, step numbers, magnifier, eraser, **Recognize Text** (OCR), undo/redo, then cancel / pin / save / copy.

- Marks work on the **full freeze**, not only inside the blue rect. Pin/Copy/Save still crop to the selection (outside ink is clipped from the baked image).
- **Recognize Text** prefers **QR / 2D codes** in the selection, otherwise OCR text; on success it copies to the clipboard, plays a short sound, and closes the capture (no result panel).
- **⌘Z** / **⇧⌘Z** (or **⌘Y**) undo / redo. **Delete** removes the selected mark.
- Refine hotkeys (after selection is locked; letter keys type while editing text): **V** move · **A** arrow · **S** shape · **D** pen · **F** marker · **M** mosaic · **I** text · **N** number · **E** eraser · **P** pin · **O** OCR · **⌘S** save · **⌘C** copy. **R** / **G** / **B** set red / green / cyan on the selected mark or armed tool.
  - ASDF mnemonics: **A**rrow · **S**hape · **D**raw · **F** like a brush for highlight. **I** = Insert (text at the cursor). **V** = move / select marks.
- **Esc** while editing text ends the editor only. Otherwise Esc walks down: abort drag → disarm tool → deselect mark → with marks, first Esc tips “Press again to discard”, second Esc cancels. Toolbar **✕** uses the same two-step confirm when marks exist.

### Move (V)

Press **V** (or the cursor toolbar icon) to enter move mode: click and drag any mark (including **inside** a rectangle / oval), resize with handles. Empty click clears the selection. Switch back with **V** again or another tool. (Toggling **V** off does **not** enable dragging the blue crop.)

**Hold Space** and drag to move the **blue crop** (temporary hand cursor). Release Space to return to the current tool. Adjust crop size with handles or by expanding from outside.

### Paint tools — move vs draw

With **pencil**, **marker**, **mosaic**, or **eraser** armed in **freehand** (brush) mode, hovering **any** existing mark **keeps the draw cursor**. To rearrange marks, press **V**, drag, then switch back (e.g. **D**) to keep drawing.

**In rect / oval mode this is different.** A highlight, mosaic or eraser area behaves like an object: click anywhere on it — inside or on the edge — to drag it, and use the handles to resize, all without leaving the tool. Brush strokes still draw through. One consequence: to start a **new** area *inside* an existing one, begin the drag outside it (or press **Esc** / use **V** first).

Under object tools (shape / arrow / text / …), paint-like marks still draw-through; other marks stay hit-to-move.

**Step** is an exception among object tools: it stamps through shapes / arrows / etc. so you can place a number on a border. Hover an existing step badge to move it; hold **⌘** to move other marks.

### Other handy modifiers

| Context | Modifier | Effect |
|---------|----------|--------|
| Refine (any tool) | **Space** (hold) | Drag blue crop |
| Shape / mosaic region | **Shift** | Square / circle |
| Arrow / pencil / freehand mosaic | **Shift** | Straight line (arrow also 45° snap) |
| Step tool over non-step marks | **⌘** | Temporary move |

## History while capturing

With the overlay up, **`,`** goes to an older capture record and **`.`** to a newer one (replay prior capture + marks into the current refine session).

## Preferences

Open from the menu bar item (**Settings…** / Preferences). Do not hunt for a Dock icon — the app is menu-bar only unless Preferences is open.

| Pane | Contents |
|------|----------|
| **General** | Launch at login; app language (System / English / Simplified Chinese; language change relaunches the app) |
| **Permissions** | Accessibility and Screen Recording status + grant buttons |
| **Hotkeys** | Customize capture / paste shortcuts |
| **About** | Version and credits |
