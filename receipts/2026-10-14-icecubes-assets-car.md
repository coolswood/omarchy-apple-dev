# IceCubes Assets.car: defects, repair, rebuild, 2026-10-14

See FINDINGS.md, "Assets.car files that Apple's assetutil rejects".

The oracle is `assetutil --validate-file` from Xcode 27.0 (27A266a) on macOS 26.6.2, on an M1 Ultra Mac Studio.
It judged cars. Every catalog that shipped was compiled on Linux.
Xcode's own actool, run on the same inputs, gave the passing control.

## Defects found

- BITMAPKEYS slots are OR(1 << token) over the asset's renditions.
  Xcode actool writes this for 147 of 147 rows of the root catalog.
  `assetutil -U` rewrote the 46 failing cars that have the tree to the same values.
  Of 55 distinct retained cars, 8 pass and match the rule, and 46 fail and differ.
- The TVL 1007 stride was rounded up to 16 over unpadded rows.
  The root car with only the atlas stride patched from 240 to 236 gives rc 0.
  The unpatched car gives `early EOF ... at row 7` and `Image data corrupted`.
- An editor-saved symbol template broke the bounds code.
  Sprites came out 13 times too large (199x110 at 15 pt, where actool writes 15x16).
  Three weight layers shared one rendition key.

Apple accepted many builds whose cars fail this validator. That holds for 43 retained car entries in COMPLETE builds.
The defects are real against actool and assetutil.
They are not shown to cause any App Store processing failure, or the support case.

## Fix

- AssetKit PR `joshuaswarren/AssetKit#1`, head `f465edb33167b9a7c76301da88e6e11490a10fc0`, base `omarchy/mac-icon` 705ce2f.
  80 tests in 20 suites pass. Each new test fails on the old code.
- `tools/car_check.py` checks every `.car` in an `.ipa` with the standard library.
  `tools/asc.py upload` runs it before its first App Store Connect call.
  `asc.py validate` reports one check per car.
- On the 55 retained original cars the check agrees with assetutil on 55 of 55.
  It flags 16 more cars that assetutil accepted after `-U`.
  Each holds a second packed atlas whose rows do not match its stride.

## Controls

Xcode 27.0 actool compiled four catalogs from the same sources: the root, the action extension, the widget extension and the Colors package.
Apple assetutil gave rc 0 on each.
The Linux-built cars of the same catalogs also give rc 0.

## Rebuild

- Sources: the `ice-ship-1200` tree from the 2026-10-11 archive, sha256 `14ac34bfbea4dfe63970302b2e3b772dcdbb5cf807495dd50366edea80df18f6`.
  The adapter came from `tools/xcodeproj2xtool.py --bundle-id com.joshuaswarren.omarchyappledev.icecubes`. The version is 1.0.1.
- actool: AssetKit `f00367eb`, sha256 `c439b1db00010793c355ac4b92848f086830654f3a4861afffdb7e1bf2f3c011`.
  The previous actool is `ed541ae847129e63a85db3fad6a13a53f662d8acf8299671f0400b990f4ff641`.
- `ship.sh` is from fdf6a0c, with the car gate.
- The chroot SDK predates the App Shortcuts training step.
  Its input, the `SiriSSUKitModel` resources (tree hash `a1bcc2c05ace9186874080e2fb0fb8da18a97acfd295b39e5c288c7dfec6f0fb`), came from the same Xcode build.
- IPA sha256 `07637de8a923ec5f070fcda36488db001c5321dd6aaf7264b735d8f38e73d296`, 122974151 bytes, version 1.0.1 (202610150234).
  Offline validation passed 107 of 107.
- Its four catalogs are the app root (70250804 B), the resource bundle (15612430 B), the action extension (74019 B) and the widget bundle (18715 B).
  Each gave assetutil rc 0 with all image blocks valid.
- `asc.py upload` made buildUpload `9035a473-df84-4005-aa8d-b90c62d5375b`. Its state is COMPLETE, with no errors or warnings.
  The build reached `processingState` VALID about three minutes later (uploaded 2026-10-14T19:50:14-07:00).
  Nothing was submitted for review.
- A rebuild with the final actool gave four catalogs that are byte-identical to the uploaded ones.
  That actool has sha256 `f0785e50add04ec547ec424dc7d0279231154f7c9aa773d07a10fbbd5a5beebe` (AssetKit `f465edb3`). It was not uploaded.

Cars, hashes, scripts and raw Apple output are in `artifacts/w7C/20261014-icecubes-assets-car/`, with SHA256SUMS.
