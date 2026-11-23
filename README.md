# FoodLabel

Native Mac app for Xprinter XP-365B and NIIMBOT B21 Pro nutrition labels. Russian interface. Apple Silicon, macOS 15 or newer. Local editing, storage and printing work offline. Importing shared recipes requires internet; no account, Homebrew, or driver is required to run the packaged app.

## Install

Download the DMG from [GitHub Releases](https://github.com/Photon94/FoodLabel/releases/latest), open it, and drag **FoodLabel** into **Applications**. Quit an older version before replacing it. Updating the app preserves the database. Release notes state the signing and Apple notarization status of each download.

## Screenshots

**NIIMBOT B21 Pro** — USB printing on 50 × 30 mm labels, with the wider layout and extra top spacing.

![FoodLabel with NIIMBOT B21 Pro selected and a 50 × 30 mm QR label](docs/screenshots/niimbot-b21-pro.jpg)

**Label editor and live preview** — enter nutrition per 100 g, choose the portion weight, and preview the exact printed label.

![FoodLabel editor with nutrition per 100 g and a live 58 × 30 mm label preview](docs/screenshots/label-editor.jpg)

<details>
<summary>Per-portion nutrition input</summary>

Enter the values for a portion to calculate the corresponding values per 100 g. Switching the input basis converts the current values.

![FoodLabel with per-portion input selected and converted nutrition values](docs/screenshots/portion-calculation.jpg)

</details>

<details>
<summary>Local print history</summary>

Review past jobs, their label images, copy counts, dates, and USB transfer results. Open a previous label for explicit reprinting.

![FoodLabel local print history showing saved label images and transfer results](docs/screenshots/print-history.jpg)

</details>

## Use

1. Open FoodLabel.app. You can move it to Applications.
2. Connect your printer by USB: XP-365B with 58 × 30 mm labels, or NIIMBOT B21 Pro with 50 × 30 mm labels. Select it in the printer menu. When only one supported model is connected, FoodLabel selects it on launch.
3. Enter the food name, portion weight and known calories/protein/fat/carbs. Select whether those values describe 100 g or a portion. Switching the selector converts existing values; changing the weight recalculates the other basis.
4. Check the preview and date, choose 1–100 copies, then press **Напечатать этикетки**.
5. **Сохранить блюдо** saves a reusable food. **История печати** retains each attempted job automatically, even when the food was not saved.

### Import from «Худеем вместе»

Paste the entire **Делюсь рецептом «…» из приложения…** message, or just its `https://hv.life/app-intent/shareUserRecipe?...` link, into **Ссылка на блюдо (QR)**. Both normal paste and **Вставить** extract the clean link and load the dish name and calories, protein, fat and carbs automatically. Escaped `https\://` links are accepted too.

FoodLabel calculates nutrition per 100 g from the recipe's ingredients and finished weight, while preserving your label portion weight. The preview and portion totals update automatically. Imported values and the QR link are saved locally with the draft, saved dish and subsequent print jobs.

A new import clears the previous dish's nutrition. If the link is unavailable or the service changes its format, use **Повторить загрузку** or enter the numbers manually. Editing the name or nutrition, removing the link, or opening another dish cancels a pending import. Nothing is printed automatically. Loading an already saved dish does not contact the service.

This integration uses the sharing endpoint verified in Android app version 5.7.11. The service may change independently of FoodLabel. See [import format and calculation](docs/recipe-import.md).

### QR dish links

Paste a dish link copied from another app into **Ссылка на блюдо (QR)**, or use **Вставить** to paste from the clipboard. FoodLabel adds a QR code on the right and keeps both nutrition rows and the barcode in a compact layout. Web URLs and app-specific deep links are supported. The receiving phone needs an app that supports the link.

The link is saved with the food and each print snapshot. **Убрать QR** returns to the original layout. Older saved foods and print history remain readable. Long links that would make the QR too dense for the label are rejected; use the source app's shorter sharing link. FoodLabel fetches recipe data only for recognized «Худеем вместе» recipe links; other URLs are used only in the QR code. It never truncates the URL. See [QR layout details](docs/qr-links.md).

![FoodLabel QR dish link field and compact nutrition label with both QR and barcode](docs/screenshots/qr-dish-link.jpg)

Comma or dot decimals are accepted. Portion weight supports one decimal place (0.1–10,000 g). Nutrition is calculated with Decimal and displayed to one decimal place. Calories are taken from your input, not inferred from macronutrients. Six-digit Code 128 barcodes are internal identifiers, not registered retail product codes.

## Local database

`~/Library/Application Support/FoodLabel/foodlabel.sqlite`

SQLite stores saved foods, the last draft, the barcode counter, and immutable print snapshots: original inputs, label date, copy count, printer model, exact PNG and print payload (TSPL for Xprinter, packed raster for NIIMBOT), timestamp, transfer result and byte count. Recipe edits do not change old history. Saving a food is optional; recording print jobs is mandatory before USB transmission. Database errors block printing.

**Резервная копия** creates a consistent standalone SQLite backup, including current changes from the write-ahead log. **База данных** reveals the database in Finder. Do not copy just the live .sqlite file while the app is running; use the backup button. To restore: quit FoodLabel, move the whole current FoodLabel data folder aside, create a fresh folder at the same location, and place the backup there named foodlabel.sqlite. Keep the original folder until you verify the restored history.

On reopening a saved food or starting the app, the date defaults to today and copies to 1. Opening a print from history preserves its label date, shows a reminder, and resets copies to 1. Reopening history does not start printing.

“Отправлено” means USB accepted the complete Xprinter job, or NIIMBOT confirmed the copy count and end of printing; inspect physical labels to confirm output. Failed, partial, or interrupted transfers are never automatically retried. A pending job found after restarting becomes “Результат неизвестен”. Check the printer before choosing to reprint.

## Printers

### Xprinter XP-365B

Direct libusb, VID 1fc9 / PID 2016, IEEE 1284 identity XP-365B + TSPL required. Fixed 58 × 30 mm, 8 dots/mm, direction 1, density 8. Gap calibration is preserved. Preview and printing use the same 464 × 240 monochrome raster. The printer receives horizontal BAR runs followed by one PRINT command. No automatic feed, reset, calibration, or test label is sent on launch.

### NIIMBOT B21 Pro

USB VID 3513 / PID 0002, class-7 printer interface. Both USB identity and NIIMBOT model ID 785 are checked before printing. Labels: 50 × 30 mm; 300 dpi, 592-dot raster width (byte-padded from 591 dots) and 354 rows. Text, QR and barcode are rendered at the printer resolution. The layout leaves space at the edges; preview, exported PNG and stored raster share the same pixels.

NIIMBOT uses its own packet protocol with checksums, cover/paper checks, command acknowledgements and completion polling. Interrupted jobs are cancelled when possible, saved with an uncertain result, and never automatically retried. Only USB is supported; this version does not use Bluetooth. The protocol implementation was informed by [NiimBlueLib](https://github.com/MultiMote/niimbluelib) and verified with a connected B21 Pro.

Opening history restores its original printer profile and checks that printer again. Old records default to Xprinter. Saved-food loading keeps the printer currently selected.

If the printer is unavailable, reconnect it, turn it on and close other printing applications, then click the refresh icon.

## Build from source

Requires Apple command-line development tools and libusb headers/library at /opt/homebrew (override USB_PREFIX if needed). Run `bash test.sh`, then `bash build.sh`. The script prints the output path in the Mac temporary folder. APP_PATH can change the output location; use a local folder outside iCloud Drive so cloud metadata does not interfere with signing. Tests render and scan a barcode, verify nutrition conversion and invalid input, and exercise SQLite persistence, snapshots, recovery and backup; they do not print. macOS graphics access is required for rendering tests.

For an isolated manual test, set FOODLABEL_DATA_DIR to a temporary directory before launching the executable. Normal launches use the database path above.

The bundled libusb license and upstream source reference are in Packaging and in the app’s Resources folder.

## Create a release DMG

Run `bash package-dmg.sh` to build a drag-to-Applications installer in `dist/`. It bundles libusb and uses a local ad-hoc signature by default. Set `SIGN_IDENTITY` to a Developer ID Application identity in the Mac keychain to sign with hardened runtime and a secure timestamp. Set `NOTARY_PROFILE` to an existing notarytool keychain profile to additionally submit to Apple and staple the resulting ticket. No certificate or credential belongs in this repository.

The script verifies the disk image and writes `dist/SHA256SUMS.txt`. It refuses to overwrite an existing release. Update Packaging/Info.plist for a new version, run the tests, create a matching Git tag, then attach the DMG and checksum file to that tag's GitHub release. This repository does not use an unattended cloud signing service.
