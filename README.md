# clipboard-fs

A macOS menu bar utility that writes clipboard contents (images, files) to a RAM disk at `/Volumes/Clipboard/`.

Solves one problem: websites with `<input type="file">` that don't accept paste. Copy an image, pick it from `/Volumes/Clipboard/` in the file dialog. That's it.

## Is this for you?

You've copied a screenshot or image, hit "Upload" on some website, and the file picker opens with no way to paste. You have to save the image somewhere first, find it, upload it, then delete it. This skips all of that.

The clipboard content lives on a RAM disk. Nothing touches your real disk. It vanishes when you quit or reboot.

## Install

```sh
git clone git@github.com:mitchins/clipboard-fs.git
cd clipboard-fs
make app
open ClipboardFolder.app
```

Requires macOS 13+. No sudo, no kernel extensions, no admin privileges.

## Usage

1. Copy an image or file
2. A clipboard icon appears in the menu bar (filled = content available)
3. In any file picker, navigate to the "Clipboard" volume under Locations
4. Select the file

The menu bar dropdown shows what's on the volume and lets you open Finder, clear contents, or quit (which ejects the volume).

## License

MIT
