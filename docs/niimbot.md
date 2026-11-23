# NIIMBOT B21 Pro support

Add explicit printer selection: XP-365B (58 × 30 mm) and B21 Pro (50 × 30 mm).
Keep saved foods, previous history, QR links and Xprinter output compatible.
The B21 Pro uses USB VID 3513 / PID 0002, printer interface class 7, and NIIMBOT V4 commands. Confirm model 785 before printing. Use a 592-dot raster width (byte-padded from 591 dots) and 354 rows at 300 dpi; the outer paper width is 50 mm. Content has at least 2 mm top spacing. Preview, PNG and saved print raster must match.

Plan:
1. Add printer profiles, optional draft/history profile and native-resolution rendering. Test legacy decoding, barcode/QR decoding and raster geometry.
2. Add framed NIIMBOT protocol with checksum validation, bounded waits, explicit acknowledgements, partial-write accounting and no automatic print retries. Test fragmented responses, rejected commands and exact raster encoding.
3. Integrate selection/discovery, persist target in history, probe actual hardware, and print exactly one authorized test label.
4. Review, test, build/install and publish a signed/notarized DMG release.

Protocol references: MultiMote/niimbluelib (MIT), D110MV4PrintTask, packet generator/parser; printers.niim.blue B21_PRO hardware page. Actual USB probe confirmed MFG:NIIMBOT;CMD:ESC;MDL: B21_Pro and connect response 55 55 C2 01 03 C0 AA AA.

## Verification log

- Hardware identified through USB printer-class interface 2 (OUT 03 / IN 83).
- Model response 03 11, heartbeat reports closed cover and loaded RFID paper.
- Actual firmware returns SetPageSize acknowledgement [1, 0]; accepted only this verified extension or [1]. Initial setup attempts stopped before sending image data and were cancelled.
- Single authorized physical print completed, 22,406 bytes transmitted; the printer confirmed copy count and PrintEnd. User requested more top spacing and wider output. Revised to 592 × 354 (591-dot head plus byte padding), with at least 24 blank top rows; second authorized test completed (22,367 bytes) and user confirmed the layout is acceptable.
- Full Swift tests passed including native raster barcode/QR decoding, persistence, exact packed-raster reconstruction, fragmented responses, unsupported command rejection, partial writes, abort/no-retry and post-completion disconnect.
- Independent review identified unsupported responses, cleanup result, stale printer status and preview proportions. All corrected; raster proportions treated as required preview correctness.
- Ruling: preserve historical SQLite column name `tspl` for compatibility; new profile-tagged NIIMBOT records store NIM1 packed image payload there. No data migration required.

- UI verified with an isolated database: automatic B21 selection, both printer choices, correct status after switching, and revised QR preview. Screenshot saved with example data only.
- Build scripts corrected for macOS Bash empty-array handling and repeated builds over a read-only copied libusb binary.
