# Dish links on labels

FoodLabel accepts a link copied from another food app and encodes that exact link as a QR code. It does not create dish links, contact the linked service, or open them automatically.

The optional Russian field “Ссылка на блюдо (QR)” supports web links and app-specific deep links. Empty input retains the existing label. The link is part of the saved food, draft, and immutable print snapshot. Records from version 1.0 remain readable without a database migration.

On the 58 × 30 mm label, a QR uses a reserved 20 × 20 mm area on the right. The nutrition table and Code 128 barcode use a compact left column; title, portion, and date stay above. Modules are at least 3 printer dots wide with a four-module white margin. Links that cannot fit legibly are rejected with a request for a shorter sharing link, never truncated or silently shortened.

The receiving phone needs an app that supports the link. Scanning is verified against the exact rendered label using Vision; physical results depend on the thermal printer and paper.

## Shared recipe messages (v1.3)

The link field now accepts complete sharing messages. Recognized hv.life recipe links trigger the narrowly scoped import described in [recipe-import.md](recipe-import.md); other links still have no network behavior. Imported dishes use the same QR validation, layout and local storage.
