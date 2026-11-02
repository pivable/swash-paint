# Known issues

*The app was called Paintbox until 2 Nov 2026, when it became Swash Paint; what follows is history and keeps the old name.*

**Nothing is open.** This file is kept because it says what was found and what became of it.

Paintbox has been through a ten-lens code review and three rounds of fixing, and it carries
self-tests that assert real pixels (199 as of 2 Nov 2026). The nine findings below are what a
final **completeness critic** found afterwards — an agent whose only job was to find what the
review itself had missed.

**Three were fixed before publication** (23 Sep 2026) and **the other six on 2 Nov 2026**, each
with a self-test.


- ~~**Save As can point two windows at one file — the exact data loss Open guards against**~~ *(data-loss)*  **Fixed before release.**

- ~~**--cutout always writes PNG bytes whatever the output is named — including the README's own loop**~~ *(wrong-output)*  **Fixed before release.**

- ~~**Changing the font while a text box is open changes what gets drawn but not what you see**~~ *(wrong-output)*  **Fixed 2 Nov 2026.** The open box now takes the new font and colour as they are picked.

- ~~**A mistyped CLI flag silently launches the GUI instead of reporting usage**~~ *(ux)*  **Fixed 2 Nov 2026.** An unknown or incomplete `--flag` prints the usage and exits 64; `--help` exists.

- ~~**Three README claims describe code that no longer exists**~~ *(tidy)*  **Fixed before release.**

- ~~**Every window opens dead-centre, so opening several files looks like opening one**~~ *(ux)*  **Fixed 2 Nov 2026.** Each new window steps down and right from the frontmost one.

- ~~**An image dragged from a browser or Photos is refused; only file drops work**~~ *(ux)*  **Fixed 2 Nov 2026.** Image bytes and promised files are accepted as well as files.

- ~~**"Save a Copy…" is a Save As: the window ends up editing the copy**~~ *(ux)*  **Fixed 2 Nov 2026.** It writes a copy and leaves the window on the original.

- ~~**Remove Background silently ignores an active selection while its menu neighbours honour one**~~ *(ux)*  **Fixed 2 Nov 2026.** With a selection it works on the selection only.


## The three that were fixed first, and why those three

Two blocked a release. One was data loss: Save As could point two windows at the same file,
which is exactly the hazard that Open already guarded against. The other was wrong output in
something this README tells you to run: the headless `--cutout` wrote PNG bytes whatever you
named the output, so the documented batch loop produced mislabelled files.

The third was the documentation: the README described code that had since changed. It gave a
stale self-test count, said zoom is anchored at the scroll origin (it has held the visible
centre since the polish pass) and that filters always run over the whole canvas (only the
selection's box is rendered now). A fourth stale claim, about Crop to Selection, was corrected
with them. The detail is in `REVIEW-BACKLOG.md`.

At publication the other six were described as interface and tidiness, none of them losing
work. That held, with one qualification found when they were fixed: "Save a Copy…" is the
button the animated-file alert offers as the way to *protect* the original, and it moved the
window off it, so the next ⌘S went somewhere the user had not chosen. It was fixed first.

## The six fixed on 2 Nov 2026

- **Save a Copy.** The alert that warns before an animated file is flattened offered "Save a
  Copy…" and then ran Save As. It now writes the copy and leaves the window on the original,
  still unsaved and still knowing how many frames it has; a copy aimed at the original's own
  file is refused. Chosen from the close or quit review, a written copy lets the window go.
- **Remove Background and the selection.** Vision is shown the selection's bounding box and the
  result goes back through the mask, as Blur, Pixelate and Adjustments already did. Checked with
  two figures side by side: the selected one is cut out, the other does not change by one byte.
- **Font changes with a text box open.** The box is restyled whenever the tool settings change,
  so the letters on screen are in the font and colour that Return will draw.
- **Mistyped flags.** The command line is parsed in one place before anything runs. Only `--`
  words are judged, so the arguments macOS adds to a normal launch still reach AppKit.
- **Window placement.** New windows cascade from the frontmost Paintbox window, wrapping to the
  top of the screen rather than walking off it. Checked on the real app by opening four files and
  reading back the window frames: 24 points apart, each one.
- **Drags from browsers and Photos.** Picture bytes on the drag pasteboard and promised files
  are accepted; a file that is not a picture, and plain text, are still refused. The promised-file
  half cannot be driven from the self-test (it needs another app to keep the promise), so the
  test checks that the canvas registers for it.

## Reporting anything else

Open an issue. If you can say what you did, what you expected and what happened, that is
enough — the self-test suite is good at turning a clear report into a regression test.
