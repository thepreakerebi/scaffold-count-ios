# Scaffold Count (iOS demo)

An iPhone app that counts scaffold steel planks from one photo, entirely on the phone.

1. Take a photo of the plank ends, or pick one from the library.
2. Drag four corners around the stack. A magnifier shows the spot under your finger.
3. Get numbered boxes and a count. Tap a box to remove it, tap a missed plank to add it, undo, pinch to zoom, and share the marked photo.

The model is the YOLO11n plank detector from [scaffold-plank-counter](https://github.com/thepreakerebi/scaffold-plank-counter), exported to Core ML (`PlankModel.mlpackage`, 5.4 MB, FP16, NMS built in). No network is used.

## Run

Open `ScaffoldCount.xcodeproj` in Xcode 16 or later, pick an iPhone simulator or your phone, and press Run. iOS 18+. On a phone, set your team under Signing & Capabilities (a free Apple ID works).

## How the count works (`PlankDetector.swift`)

The steps match the Python pipeline the model was trained and tested with:

1. Grey out everything outside the marked area (grey 114), crop to it with a 3% margin.
2. Pad the crop to a square and scale it to 640 × 640. Stretching it instead dropped accuracy badly on the staggered and top-view photos.
3. Run the model (IoU 0.5, confidence 0.25).
4. Drop half-plank boxes that sit inside a more confident box, keep boxes centred in the area, and join side-by-side halves whose joined width is still about one plank.
5. Number the planks column by column, top to bottom.

Checked against the 5 test photos with the same marked areas: the app counts 54 / 27 / 76 / 17 / 60 against true counts of 54 / 27 / 76 / 18 / 60 (one plank off in total, from image-resizing differences). Note that this model was trained on all 5 photos, so this checks the port, not accuracy on new photos.

## Debug launch arguments

Debug builds only: `-selftest <file.json>` prints counts for a set of photos and quads; `-demo <photo> <x0,y0,…,x3,y3> [-result]` opens the Mark or Result screen directly.

## Structure

- `Session.swift`: app state, counting, tap-to-fix edits and undo
- `PlankDetector.swift`: Core ML input, model call, clean-up rules, numbering
- `HomeView.swift`, `MarkView.swift`, `ResultView.swift`: the three screens
- `ShareRenderer.swift`: the shared image with boxes and the count
- `Theme.swift`, `Components.swift`, `PlankArt.swift`: colours, buttons, drawings
