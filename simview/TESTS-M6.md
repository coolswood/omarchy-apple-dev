# M6 test expectations

M6 checks scripted keyboard input and text field focus in our Linux
simulation. The `keysdemo` app has two text fields and an echo label. Field
one fires `onSubmit` on return and copies its text to the label. Field two
has no `onSubmit`, so return only blurs it.

A frame file can carry two new record kinds next to the M3 finger records:

- `{"key": n}` presses a key by USB keyboard usage number, page 7. Usage 40
  is Return. Usage 42 is Backspace. Other usage numbers are dropped with a
  warning line.
- `{"text": "c"}` inserts one character. This is the text insertion path.

A frame holds at most one of `fingers`, `key`, and `text`.

The focus rules: the tap rules of M3 decide focus. The target is fixed at
`began`, and a tap completes only when the last finger ends inside the
target. A completed tap focuses the field under it. A tap that ends outside
its target changes nothing: no focus, no blur, no action. A tap that began on
nothing blurs. A cancelled tap changes nothing. Keys go to the focused field
only. A key with no focus is dropped, and the runner prints one warning line
for it. The caret sits at the end of the text. Backspace removes one
character and stops at empty. Return fires `onSubmit` when present and always
blurs. The field box is 60 by 9 points. Text wider than the box overflows;
the field does not scroll.

`simview/test-m6.sh` checks these rows. PNG tolerance is zero differing
pixels and zero channel difference. State is read from the log lines.

| Row | Input | Expected |
|---|---|---|
| 0 | Render without frames | The PNG matches `golden/keys-root.png`. |
| 1 | Tap field one | The log says `target=Field#1`. The PNG matches `golden/keys-focus1.png`: the caret shows and the placeholder stays. |
| 2 | Tap field one, type H and i | State shows `first:Hi`. The PNG matches `golden/keys-hi.png`. |
| 3 | Type H and i, backspace, then e and y | State shows `first:Hey`. The PNG matches `golden/keys-hey.png`. |
| 4 | Type A, tap empty space, type x | The runner warns about x. State stays `first:A`. The PNG matches `golden/keys-blurred.png`: no caret. |
| 5 | Type Hi in field one, tap field two, type ok | State shows `first:Hi,second:ok`. The PNG matches `golden/keys-two.png`: the caret moved. |
| 6 | Type Hi in field one, press Return, type x | Return fires `onSubmit`: state shows `first:Hi,echo:Hi`. Return blurs, so x is dropped with a warning. The PNG matches `golden/keys-echo.png`. |
| 7 | Press Backspace and type q with no field tapped | Two warning lines. State stays empty. The PNG matches `golden/keys-root.png` byte for byte. |
| 8 | Type A in field one, begin a tap on field two, cancel it, type B | The cancelled tap does not focus. B goes to field one: state shows `first:AB,second:`. The PNG matches `golden/keys-cancel.png`. |
| 9 | The demo flow: tap field one, type Hi, backspace, type ey, tap field two, type ok, press Return | State shows `first:Hey,second:ok`. The PNG matches `golden/keys-demo.png`. |
| 10 | Run the demo flow twice | Both logs and both PNG files are byte-identical. |
| 11 | Focus field one and type A, then begin on field two, slide off, and lift on empty space, then type B | The slide changes nothing. Field one keeps focus: state shows `first:AB,second:`. The PNG matches `golden/keys-slideoff.png`. |
| 12 | Begin on field two, move two points inside it, lift inside it, type z | The tap completes and focuses field two: state shows `first:,second:z`. |

## Mutation checks

Each mutation changes one behavior in a copied module. The suite rebuilds the
app against that module. The named row must reject the changed build. A
mutant that fails to compile or survives its row fails the suite.

| Mutation | Changed behavior | Required failing check |
|---|---|---|
| keys-last-field | Routes text records to the highest field id instead of the focused one | Row 2 state |
| no-end-inside | Focuses a field without the end-inside check | Row 11 state |
| backspace-front | Backspace removes the first character instead of the last | Row 3 state |
| no-blur | A tap that began on nothing keeps the old focus | Row 4 state |
| cancelled-focus | A cancelled tap focuses its field | Row 8 state |
| no-return-blur | Return fires `onSubmit` but keeps focus | Row 6 state |
| no-drop-warning | Drops keys without printing the warning line | Row 7 warnings |

## Notes

- Row 4 is also the began-on-nothing blur case: the tap starts and ends on
  empty space, and the runner must blur.
- The button case of the same rule (a gesture that begins on a button and
  ends outside it must not blur) shares the end-inside check with the button
  action path, which the M3 rows cover. `keysdemo` has no button, so no row
  here drives that path with focus set.

