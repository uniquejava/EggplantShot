# EggplantShot — User guide

Menu-bar screenshot tool for macOS (Snipaste-style snip → annotate → pin / copy / save).

## Permissions

| Permission | Why |
|------------|-----|
| **Accessibility** | Global hotkeys |
| **Screen Recording** | Capture |

Without Accessibility, hotkeys do nothing. Without Screen Recording, capture fails with a prompt.

## Capture

| Action | Default |
|--------|---------|
| **Snip** | `F1` |
| **Snip and copy** | `⌘F1` |

1. Displays freeze; hover highlights the window under the cursor.
2. Click to lock that window, or drag to free-select a region.
3. Refine the blue rect (move interior / resize handles), annotate if you want, then **Pin** / **Copy** / **Save**.
4. **Return** confirms the primary action (Pin for Snip, Copy for Snip and copy). **Esc** cancels the snip.

Menu bar → **Disable hotkeys** pauses global shortcuts (persisted).

## Pins

Floating image above ordinary windows. Drag to move. **Esc** or double-click closes that pin only.

## Annotate (during refine)

Toolbar under the selection: shape, arrow, pencil, mosaic (blur), text, **Recognize Text** (OCR), undo/redo, then cancel / pin / save / copy.

- Marks work on the **full freeze**, not only inside the blue rect. Pin/Copy/Save still crop to the selection (outside ink is clipped from the baked image).
- **Recognize Text** runs OCR on the selection, copies text to the clipboard, plays a short success sound, and closes the snip (no result panel).
- **⌘Z** / **⇧⌘Z** (or **⌘Y**) undo / redo. **Delete** removes the selected mark.
- **Esc** while editing text ends the editor only; otherwise Esc cancels the whole snip.

### Pencil — move vs draw

While the pencil tool is active, hovering an existing pencil stroke **keeps the draw reticle** so you can trace along an edge without accidentally grabbing the stroke.

To **move** a pencil stroke without switching tools:

1. Hold **⌘**
2. Pointer over the stroke → four-arrow cursor
3. Drag to reposition
4. Release **⌘** to draw again

(Other annotate tools can still click a pencil stroke to move it.)

### Other handy modifiers

| Context | Modifier | Effect |
|---------|----------|--------|
| Shape / mosaic region | **Shift** | Square / circle |
| Arrow / pencil / freehand mosaic | **Shift** | Straight line (arrow also 45° snap) |

## History while snipping

With the overlay up, **`,`** goes to an older snip record and **`.`** to a newer one (replay prior capture + marks into the current refine session).

## Preferences

Open from the menu bar item (**Settings…** / Preferences). Do not hunt for a Dock icon — the app is menu-bar only unless Preferences is open.
