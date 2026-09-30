# SightShift

**Keyboard focus follows your gaze.** Look at a screen, window or split pane and just start
typing — focus is already there. No clicking first, no ⌘-Tab, no typing into the wrong window.

SightShift is a free, open-source (MIT) macOS menu bar app. It uses your webcam and Apple's Vision
framework to estimate which way your head is turned, entirely on your Mac.

- **Multiple screens** — turn toward a screen and the window you last used there gets focus.
  The pointer comes along too, so scrolling works where you're looking.
- **One screen** — it focuses the window, or the split pane of a terminal or editor, that you
  look at.
- **Calm by design** — quick glances are ignored, focus holds still while you type or use the
  mouse, looking at a bezel doesn't ping-pong, and looking at your phone or the ceiling is
  ignored.
- **Learns as you go** — you look where you click, so each click refines the model, including
  when you sit closer, farther away or off to one side.
- **Private** — frames are analysed in memory at 720p, at most 15 frames a second, and thrown
  away. No network access, no account, no analytics.

## Requirements

- macOS 14 Sonoma or later, Apple silicon or Intel
- A camera that faces you (the built-in camera works best with the laptop in front of you)
- Xcode 16 or later to build

## Build and install

```sh
make install      # builds, signs, copies to /Applications and launches
```

Other targets: `make run` (build and launch from `build/`), `make test` (unit tests),
`make build`, `make clean`. Use `INSTALL_DIR=~/Applications make install` to install without
touching `/Applications`.

You can also open `SightShift.xcodeproj` in Xcode. The project is generated from `project.yml`
with [XcodeGen](https://github.com/yonaskolb/XcodeGen); run `make project` after editing it.

### Why a local signing identity?

macOS remembers Camera and Accessibility permissions by code signature. An ad-hoc signature
changes on every build, which would make macOS forget both permissions each time you rebuild.
`scripts/sign.sh` creates a self-signed certificate in its own keychain under `.signing/`
(git-ignored) the first time you build and signs every build with it, so permissions stick.
Your login keychain is not modified. Set `SIGN_IDENTITY="Developer ID Application: …"` to sign
with a real identity instead.

## First run

The setup guide walks you through three steps:

1. **Camera** — to see which way you're facing.
2. **Accessibility** — to move keyboard focus and to notice typing. Turn on SightShift in the
   list that opens.
3. **Calibration** — follow a dot through nine positions on each screen, about 20 seconds per
   screen. Face each screen the way you naturally would; don't hold your head artificially
   still.

Recalibrate from the menu bar after moving a monitor, the camera, or your chair a lot. With
"Learn from my clicks" on, small changes are absorbed on their own.

## Using it

| | |
|---|---|
| Pause / resume | **⌃⌥⌘G** (change it in Settings) or the menu bar icon |
| Settings | Menu bar icon → Settings… (⌘,) |
| Calibrate one screen | Menu bar icon → Calibrate One Screen |
| See what SightShift sees | Menu bar icon → Diagnostics… |

The default shortcut is deliberately not ⇧⌘G: a global shortcut swallows its keys everywhere,
and ⇧⌘G is Find Previous in most apps and Go to Folder in Finder.

### Settings

| Setting | Default | What it does |
|---|---|---|
| Delay before switching | 300 ms | How long you must face another screen before it takes focus |
| Head turn needed | 50% | How far toward another screen you turn before it wins (more = more deliberate) |
| Bring the pointer along | on | Moves the pointer to the newly focused window |
| Focus the window or split pane I look at | on | Same-screen focus |
| Delay (same screen) | 350 ms | Dwell time before a window or pane takes focus |
| Click a terminal pane that won't take focus directly | on | Fallback for terminals that ignore accessibility focus requests |
| Split panes in VS Code, Cursor and other Electron editors | off | See [Split panes](#split-panes) |
| Wait while I'm typing | on | Holds focus until typing pauses |
| Typing pause | 2 s | How long typing must pause |
| Mouse rest | 1.5 s | Focus never moves while you use the mouse or trackpad, or this long after |
| Learn from my clicks | on | Refines the model from where you click |
| Show gaze dot | off | Shows where SightShift thinks you're looking |

If you keep typing straight through a turn, SightShift assumes you're reading the other
screen while typing on this one, and leaves focus where it is until you look away and back.
If you stop typing, turn, and wait for the typing pause, focus follows you. Lower the typing
pause if you like to start typing the moment you turn.

While one of SightShift's own windows (Settings, Diagnostics) is active, it only watches: you
can look around and see what it would do without anything moving.

## Split panes

Pane focus works in apps that expose their panes through Accessibility: iTerm2, Terminal,
Ghostty, cmux, Xcode, JetBrains IDEs and Android Studio. When a terminal doesn't accept an
accessibility focus request, SightShift clicks the middle of the pane, after checking that
nothing else covers it (turn that off in Settings; with mouse reporting on, vim and tmux see
that click). Editors are never clicked, since a click would move the caret.

VS Code, Cursor, Windsurf, VSCodium and Hyper are built on Electron, which only reveals its
panes when asked. Asking is what screen readers do, so those apps may switch to their screen
reader mode; that's why pane focus for them is off until you turn on "Split panes in VS Code,
Cursor and other Electron editors". Setting `"editor.accessibilitySupport": "off"` in their
settings prevents the mode switch.

Apps that draw everything themselves without accessibility information (for example kitty,
WezTerm, Warp, Zed and Sublime Text) still get window-level focus but not pane focus. tmux
panes live inside a single terminal pane, so keep using the tmux keys for those.

## How it works

```
camera (720p, ≤15 fps)
  → Vision: face rectangle (yaw, pitch) + 76 landmarks        [Camera/FaceTracker.swift]
  → 10 features: head yaw/pitch, nose offset, face asymmetry,
    eye direction, face position and size                      [SightShiftCore/FaceFeatures.swift]
  → 1€ smoothing
  → which screen: nearest calibrated screen in a whitened
    (LDA) feature space, with a turn threshold, hysteresis and
    an off-screen gate                                         [SightShiftCore/ScreenClassifier.swift]
  → where on it: per-screen ridge regression                   [SightShiftCore/PointRegressor.swift]
  → dwell, typing and mouse guards                             [SightShiftCore/DwellTracker.swift, FocusPolicy.swift]
  → focus the last-used window on that screen, or the window
    or pane under your gaze                                    [System/FocusWorker.swift]
```

Screen switching relies mostly on head direction, which an ordinary webcam measures reliably.
Same-screen window and pane focus also uses where your eyes point inside your head, which is
noisier, so it needs a clearer look and a short dwell.

Windows are focused with the same window-server calls that window managers such as AltTab and
yabai use (looked up at run time, with a public-API fallback), so no click is involved.

## Privacy

- Frames are processed with Apple's Vision framework, in memory, and discarded immediately.
- Nothing is recorded, stored or uploaded. The app makes no network requests.
- Calibration is saved as numbers describing head poses in
  `~/Library/Application Support/SightShift/profile.json`. Delete it (or use Settings → Delete
  Calibration…) to start over.
- The camera is off while SightShift is paused, while the Mac is locked or asleep, and until
  setup is complete.

## Troubleshooting

- **Nothing happens.** Open Diagnostics…: check that your face is visible, that "Looking at"
  follows your head, and that Accessibility is allowed.
- **It switches to the wrong screen.** Recalibrate, facing each screen naturally. The
  calibration summary warns when two screens look too similar from the camera.
- **Permissions seem stuck.** Run `make reset-permissions`, relaunch, and grant them again.
- **Wrong camera.** Pick one in Settings → Camera, then recalibrate.

## Development

```
App/Sources/                macOS app (AppKit + SwiftUI)
  Camera/                   capture and Vision
  Engine/                   per-frame decisions, activity monitoring, storage
  System/                   accessibility, window focus, displays, hot key, permissions
  UI/                       menu, settings, onboarding, diagnostics, calibration, gaze dot
Packages/SightShiftCore/    pure-Swift model and decision logic, with unit tests
scripts/                    signing and icon generation
```

`make test` runs the core tests, including a simulated user looking at three screens that
checks screen accuracy, on-screen position, off-screen rejection, hysteresis and learning after
a change of seat.

## License

[MIT](LICENSE)
