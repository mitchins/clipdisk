# Finder Template Assets

Optional Finder customization assets for the mounted Clipboard RAM disk.

If this folder contains `.DS_Store` and/or `.background/`, the app copies them to `/Volumes/Clipboard` when the RAM disk is mounted or recovered.

Recommended workflow:

1. Create a temporary RAM disk named `Clipboard`.
2. Open it in Finder and switch to icon view.
3. Set your window size, icon positions, and optional background image.
4. Copy the generated `.DS_Store` from that volume into this folder.
5. If using a background image, copy it to `.background/instructions.png` under this folder.
6. Rebuild the app (`make app`) so these assets are packaged.

Notes:

- Volume name must remain `Clipboard` for the Finder template to match.
- The template is optional; if files are missing, runtime behavior is unchanged.
- Hidden files can be revealed in Finder with `Cmd+Shift+.` while authoring.
