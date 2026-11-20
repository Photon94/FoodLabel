# FoodLabel for macOS

Approved: native Mac app, Russian UI, direct USB Xprinter XP-365B printing, live 58 × 30 mm label preview, saved foods, nutrition conversion in both directions. Added requirement: persistent local database of what was printed.

## Approach
Native SwiftUI UI and AppKit/CoreImage label rendering, with a small C/libusb adapter based on the proven device connection. A browser app would introduce device permission and browser dependence; a full macOS system printer driver is unnecessary for this focused app. Bundle libusb so Homebrew is not needed to launch the finished app.

## Behavior
Food name, portion mass, kcal/protein/fat/carbohydrates, input basis (100 g or portion), editable label date, generated six-digit internal barcode, and 1–100 copies. Derive both nutrition rows without rounding source values. Accept comma or dot decimals. Validate before saving/export/printing. Show a live monochrome preview matching the bytes sent. Nutrition uses explicit supplied energy, not recalculated 4/9/4.

Save food templates and immutable print snapshots in SQLite under ~/Library/Application Support/FoodLabel/foodlabel.sqlite. Record pending job BEFORE USB, then sent/error/uncertain after transfer; never equate a USB success with physical completion. Interrupted attempts remain uncertain after restart and are not retried. User can view history and reopen a snapshot for an explicit new print. Export PNG and database backup. No network, telemetry, automatic printing, fabricated shelf life, or silent retry. Date defaults to today on launch/new template and historical dates are retained explicitly when reopening a past label.

## Validation
Test exact forward/reverse nutrition, comma parsing, zero/negative/NaN/infinite rejection, decimal rounding, barcode validation, label margins/long names, SQLite restart/history snapshot fidelity, persistence errors and interrupted jobs. Read-only USB probe for integration. Do not consume labels without a user print action.
