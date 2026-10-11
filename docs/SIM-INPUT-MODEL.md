# Input model for the Linux simulation (M3 spec)

Date: 2026-10-11. Status: spec. No input code exists yet.

This page fixes what a touch or key event is in our Linux simulation, and which rules the M3 tests check.
It belongs to [IOS-SIMULATION-LINUX.md](IOS-SIMULATION-LINUX.md), rung M3.

The rules come from our reading of published research notes on how iOS apps receive input, and from ordinary iOS
behavior. We have run none of them. Each rule becomes a measured claim when its M3 test passes.

## One event

An event is one record:

| Field | Meaning |
|---|---|
| `t_ms` | Time in milliseconds from the host clock. It never goes backward. |
| `finger` | A number from 0 to 9. One number per finger that is down. |
| `phase` | `began`, `moved`, `ended` or `cancelled`. |
| `x`, `y` | Position in scene points. The origin is the top left corner of the scene. |

These four rules are the core of the model.

1. Coordinates are scene points, not pixels. A 390 by 844 scene gets the same numbers at any pixel scale.
2. The target is fixed at touch down. The topmost visible element under the first finger at `began` gets the whole
   touch. It keeps it when the finger leaves the element. All fingers of one gesture share that target.
3. Every event lists all fingers that are down. When a second finger moves, the event also carries the first finger.
   A finger that did not change has an empty change mask.
4. Time comes from the host. Scroll speed and fling use the real gaps between events. Fake, evenly spaced times
   break them.

## From a Mac-style host to touches

| Host input | Becomes |
|---|---|
| Mouse click and drag | Finger 0: `began`, `moved` for each step, `ended`. |
| Two-finger trackpad scroll | Finger 9. It goes down at the cursor when the scroll begins, moves by each delta, and lifts when the scroll ends. |
| Scroll momentum events from the host | Dropped. The app does its own deceleration after the lift. |
| A scroll that starts and never moves | `cancelled`, so nothing is tapped. |
| Trackpad pinch | Fingers 7 and 8, placed around the cursor, moved apart or together by the pinch amount. |
| Trackpad rotate | The same two fingers, turned around the cursor. |
| Two-finger double tap | A double tap at the cursor. |

M3 builds the mouse row only. The scroll and pinch rows are listed so the event record already fits them.

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

## The scripted event file for M3

M3 takes taps from a file, with no window:

```json
[
  {"t_ms": 0,   "finger": 0, "phase": "began", "x": 195, "y": 420},
  {"t_ms": 80,  "finger": 0, "phase": "ended", "x": 195, "y": 420}
]
```

A short form `{"tap": [195, 420]}` expands to the two records above, 80 ms apart.

Each event writes one log line: `t=80 finger=0 ended (195,420) target=Button#1 state=count:1 render=ok`.

## M3 tests

Each test runs on Linux with no device. The expected result is written before the code.

| Test | Expected |
|---|---|
| Tap inside a button | The button's action runs once. The re-render differs from the no-tap render inside the button box. |
| Press inside, move out, lift outside | No action. The button is not activated. |
| Press inside, move out, move back in, lift inside | One action. |
| Press on a button, drag across a second button, lift on the second | No action on either. The first button owns the touch. |
| Tap on empty space | No action, no state change, and the log says `target=none`. |
| Two fingers down, one lifts | Each event lists both fingers until the second lift. |
| Events out of time order | The runner refuses the file and names the line. |
| Same file twice | The same log and the same pixels. |

## What this cannot prove

- iOS gesture recognizers. We write our own hit testing, so passing proves our model, not Apple's.
- Edge rules of the real system, such as the edge swipe that goes back, or touches that start in a safe area.
- The feel of scrolling and fling. Our runner has no deceleration yet.
- Keyboard focus, dictation, and the pause some apps show the first time a text field gets focus.

The phone path in [OVER-TAILNET.md](OVER-TAILNET.md) can later give a real device to compare against.
