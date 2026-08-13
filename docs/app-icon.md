# App icon (Dock / Finder / About) — design spec

Reference: [Apple HIG — App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)

## What we ship

| Rule | Value |
|------|--------|
| Master | `EggplantShot/Assets.xcassets/AppIcon.appiconset/AppIcon-1024-master.png` |
| Shape | Continuous rounded rect, corner radius ≈ **22.37%** of edge (Big Sur+ grid) |
| Corners | **Transparent** outside the rounded rect |
| Sizes | All `mac` idiom 16…512 @1x/@2x via `scripts/generate_app_icons.py` |
| Art (this app) | Cream scissors + cyan crop brackets on a teal/blue field — **Shot-only**. Not Fred’s purple hat. |

```bash
python3 scripts/generate_app_icons.py
# then rebuild so AppIcon / Assets.car refresh
```

About uses `NSApp.applicationIconImage`, which reads this catalog icon.
