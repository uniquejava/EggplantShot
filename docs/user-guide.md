# EggplantShot — User guide

Menu-bar screenshot tool for macOS (Snipaste-style capture → annotate → pin / copy / save).

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

## Pins

Floating image above ordinary windows. Drag to move. Scroll wheel zooms ±10% (brief % badge in the top-left). **Esc** or double-click closes that pin only.

## Annotate (during refine)

Toolbar under the selection: shape, arrow, pencil, mosaic (blur), text, **Recognize Text** (OCR), undo/redo, then cancel / pin / save / copy.

- Marks work on the **full freeze**, not only inside the blue rect. Pin/Copy/Save still crop to the selection (outside ink is clipped from the baked image).
- **Recognize Text** runs OCR on the selection, copies text to the clipboard, plays a short success sound, and closes the capture (no result panel).
- **⌘Z** / **⇧⌘Z** (or **⌘Y**) undo / redo. **Delete** removes the selected mark.
- **Esc** while editing text ends the editor only; otherwise Esc cancels the whole capture.

### Pencil / mosaic / eraser — move vs draw

Hovering an existing **pencil**, **mosaic (blur)**, or **eraser** mark **keeps the draw cursor** under any annotate tool, so you can keep painting without accidentally grabbing the mark.

To **move** one of those marks without switching tools:

1. Hold **⌘**
2. Pointer over the mark → four-arrow cursor
3. Drag to reposition
4. Release **⌘** to draw again

(Selected mosaic / eraser **regions** still expose resize handles; body move needs **⌘**.)

### Other handy modifiers

| Context | Modifier | Effect |
|---------|----------|--------|
| Shape / mosaic region | **Shift** | Square / circle |
| Arrow / pencil / freehand mosaic | **Shift** | Straight line (arrow also 45° snap) |
| Pencil / mosaic / eraser marks | **⌘** | Temporary move |

## History while capturing

With the overlay up, **`,`** goes to an older capture record and **`.`** to a newer one (replay prior capture + marks into the current refine session).

## Preferences

Open from the menu bar item (**Settings…** / Preferences). Do not hunt for a Dock icon — the app is menu-bar only unless Preferences is open.
