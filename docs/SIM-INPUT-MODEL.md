# M3 and M5 input rules

Date: 2026-10-11. M3 defines the frame loader and touch rules. M5 adds the
vertical scroll model. Both are implemented in `simview/Sources/SwiftUI/`.
Related files: `../receipts/2026-10-11-simview-m3.md` and
`../receipts/2026-10-11-simview-m5.md`.

This page fixes what a touch or key event is in our Linux simulation, and which rules the M3 tests check.
It belongs to [IOS-SIMULATION-LINUX.md](IOS-SIMULATION-LINUX.md), rungs M3 and M5.

The rules describe our simulation. They do not claim to match Apple's input behavior.

## One event

An event is one frame. It has a time and a list of finger records, one record for each finger that is down or just lifted.

| Frame field | Meaning |
|---|---|
| `t_ms` | Time in milliseconds from the host clock. It never goes backward. |
| `fingers` | The list of finger records. It is never empty. |

| Finger record field | Meaning |
|---|---|
| `finger` | A number from 0 to 9. One number for each finger that is down. |
| `phase` | `began`, `moved`, `ended`, `cancelled` or `stationary`. `stationary` means the finger is down and did not change. |
| `x`, `y` | Position in scene points. The origin is the top left corner of the scene. |

These four rules are the core of the model.

1. Coordinates are scene points, not pixels. A 390 by 844 scene gets the same numbers at any pixel scale.
2. The target is fixed at touch down. The topmost visible element under the first finger at `began` gets the whole
   touch. It keeps it when the finger leaves the element. All fingers of one gesture share that target.
3. Every frame lists all fingers that are down. When a second finger moves, the frame also carries the first finger as
   `stationary`. A lifted finger appears once, as `ended`, and is gone from the next frame. A cancelled finger does the
   same: it appears once, as `cancelled`, and is gone from the next frame.
4. Time comes from the host. M5 uses the drag delta and does not implement fling.

## From a Mac-style host to touches

| Host input | Becomes |
|---|---|
| Mouse click and drag | Finger 0: `began`, `moved` for each step, `ended`. |
| Two-finger trackpad scroll | Finger 9. It goes down at the cursor when the scroll begins, moves by each delta, and lifts when the scroll ends. |
| Scroll momentum events from the host | Dropped. M5 does not implement deceleration after the lift. |
| A scroll that starts and never moves | `cancelled`, so nothing is tapped. |
| Trackpad pinch | Fingers 7 and 8, placed around the cursor, moved apart or together by the pinch amount. |
| Trackpad rotate | The same two fingers, turned around the cursor. |
| Two-finger double tap | A double tap at the cursor. |

M3 builds mouse frames. M5 adds drag scrolling in our own `ScrollView` model.
It does not reproduce Apple's scroll implementation.

## M5 scrolling

The M5 runner interprets `began`, `moved`, and `ended` records as one drag.
It changes the vertical content offset by the finger delta. It clamps the
offset between zero and the content height minus the viewport height.

Inside a scroll view, a movement greater than eight points crosses the slop.
The runner cancels the original row tap and applies the drag to scrolling.
Movement below the slop leaves a tap eligible. This rule applies only inside
the scroll view. M3 touch tests outside it keep their original behavior.

M5 has no momentum or fling. It does not implement pinch, rotate, or keys.

## Keys

Keys come in two forms.

- **By position.** The host sends a USB keyboard usage number (usage page 7). The app maps it with its own layout,
  which is US by default. A host with another layout therefore types US characters.
- **Modifiers are real key events.** Before a key, the host presses or releases shift, control, option and command to
  match the current flags. The host event stream does not send them on its own.
- **Text outside ASCII** goes in through a text insertion call, not through key events. The app then sees an edit but
  no per-key callback.

Keys need more than input. The app must also know which text field has focus. M3 does not build keys. A rung after M3
builds them, and it is not planned yet.

## The scripted frame file for M3

M3 takes frames from a file, with no window. A tap is two frames. A two-finger frame lists both fingers:

```json
[
  {"t_ms": 0,   "fingers": [{"finger": 0, "phase": "began", "x": 195, "y": 420}]},
  {"t_ms": 80,  "fingers": [{"finger": 0, "phase": "ended", "x": 195, "y": 420}]},
  {"t_ms": 400, "fingers": [{"finger": 0, "phase": "began", "x": 100, "y": 300},
                            {"finger": 1, "phase": "began", "x": 290, "y": 300}]}
]
```

A short form `{"tap": [195, 420]}` expands to the first two frames above, 80 ms apart.

Each frame writes one log line for each finger record. This line is what the
demo app prints when the first tap above lands on its button, whose rect the
runner reports as 177,430,35,9:

`t=80 finger=0 ended (194,434) target=Button#1 state=count:1 render=ok`

Coordinates come from the scene, so tests read tap points from the printed
rects instead of hard coding them.

## M3 tests

Each test runs on Linux with no device. The expected result is written before the code.

| Test | Expected |
|---|---|
| Tap inside a button | The button's action runs once. The re-render differs from the no-tap render inside the button box. |
| Press inside, move out, lift outside | No action. The button is not activated. |
| Press inside, move out, move back in, lift inside | One action. |
| Press on a button, drag across a second button, lift on the second | No action on either. The first button owns the touch. |
| Tap on empty space | No action, no state change, and the log says `target=none`. |
| Two fingers down, one lifts | The frame of the lift lists both fingers: one `ended`, one `stationary`. The next frame lists only the finger still down. |
| Frames out of time order | The runner refuses the file and names the line. |
| Same file twice | The same log and the same pixels. |

Status after M3 (2026-10-11): all eight rows pass. `simview/test-m3.sh` runs
them; the expected result of each row, and the tolerances, are in
`simview/TESTS-M3.md`, which was committed before the input code. Two notes:
the tap-inside row runs on `m3app`, whose button label carries the state, so
the changed pixels sit inside the button box; the demo button label is
static. The out-of-order row is refused by index, which this page allows in
place of a line number.

## What this cannot prove

- iOS gesture recognizers. We write our own hit testing, so passing proves our model, not Apple's.
- Edge rules of the real system, such as the edge swipe that goes back, or touches that start in a safe area.
- M5 scroll offset is our model. We have not measured it against Apple's behavior.
- Keyboard focus, dictation, and the pause some apps show the first time a text field gets focus.

The phone path in [OVER-TAILNET.md](OVER-TAILNET.md) can later give a real device to compare against.
