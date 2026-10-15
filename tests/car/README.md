# Assets.car fixtures for tests/test_car_check.py

Each car comes from the IceCubes catalogs (MIT). Apple results are `assetutil --validate-file` from Xcode 27.0 (27A266a) on macOS 26.6.2, run on 2026-10-14.

| File | Made by | Apple result | sha256 |
| --- | --- | --- | --- |
| `colors-xcode-actool.car` | Xcode actool on `Colors.xcassets` | rc 0, all image blocks valid | `88d262f7702f3a49b3be89bc4517859cf9c81d7bd200e4d8eaaebbd928fcd938` |
| `action-assetkit.car` | AssetKit 7352722 plus the symbol and stride fixes, `ActionIcon` catalog | rc 0, all image blocks valid | `317dbbf4dada8b2b7e2c0e34ca33b7b58c15bf07e9bf23fbdf20d82dc93d3eac` |
| `colors-assetkit-old.car` | AssetKit 705ce2f, the car of the 2026-10-06 IceCubes upload | rc 1, `invalid bitmapindex` | `40cd37526bd04d18941e28c87a93a425ff14b0b2a4b1c116b65c0c277141c53c` |
| `colors-assetkit-old-assetutil-U.car` | the car above after Apple `assetutil -U`; Apple wrote these bytes, not AssetKit | rc 0 | `f0d9ca13c794809a4bf9ec08fb6f40d9cd0446d04d2a1d04a9a8a4132434c731` |
| `empty-assetkit-old.car` | AssetKit 705ce2f, an empty car of the 2026-10-05 builds (0 renditions, no BITMAPKEYS tree) | rc 1, `invalid bitmapindex` | `86e5a70cf951b1eaa1f7a544355de958a9521670916685fd2ff1008971a8f600` |

The tests change single fields of these cars (a BITMAPKEYS word, a TVL stride) to make mutants. A mutant is not an Apple-tested car.
