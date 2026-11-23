# Shared recipe import

Verified against the official RuStore package `ru.hudeem.adg` version 5.7.11 on 2026-11-23. This is an interoperability integration, not a stable published API contract. No Android code, binaries, credentials or user recipe identifiers are bundled.

## Reference flow

The source application's `DeepLinkService` recognizes `/app-intent/shareUserRecipe` and reads `userId` and `id`. It decodes `userId` with default Sqids, joins the decoded integers without a separator, then parses the result as the numeric profile ID. `_AppApi.getUserRecipe` performs GET `https://admin.hv.life/api/recipe/item` with query fields `profile_id` and `recipe_id` from `UserRecipeRequest`.

FoodLabel sends only those two identifiers to this endpoint. It uses an ephemeral session without cookies or cache, a 15-second request timeout, a 20-second resource timeout, and a 1 MiB response limit. Redirects are rejected. Only exact HTTPS hv.life recipe links trigger this request. Other QR links are not fetched.

## Nutrition basis

`SyncReceipt` contains `title`, finished recipe `weight`, and `products`. Each product has `dose`, `portionIndex`, and `portions`, each containing `portion.amount` and `nutrient`.

The verified `Ingredient.toProductRepo` → `ProductRepo.calcDose` path selects the indicated portion. Its contribution is:

```
selected nutrient × dose / selected portion amount
```

When amount is zero the source uses unit quantities: `selected nutrient × dose`. The `ReceiptModel` constructor sums these contributions and multiplies by `100 / finished weight` for its `nutrients100g` field. FoodLabel follows that formula with Decimal. Imported editable fields retain up to six decimal places to avoid unreadable repeating fractions; labels and summary cards keep the existing one-decimal display. It reads `calories`, `proteins`, `fats`, `carbohydrates`; it does not substitute the separate `energyValue` field or derive calories from macros.

Missing nutrients, invalid indices, negative quantities, invalid or zero finished weight, oversized responses and unsupported response shapes fail visibly instead of becoming zeros. The current label portion weight is retained. Source `weight_portion` does not replace the user's label weight.

## Editing and persistence

Both the text-field binding and clipboard button call the same parser. It accepts full sharing messages, bare links, escaped colons and surrounding punctuation. Multiple URLs and duplicate recipe identifiers are rejected.

Import starts after a short debounce, clears prior nutrition and disables printing. A generation token and task cancellation reject stale results. Name/nutrition/basis/link edits cancel loading; portion weight and print settings can change while loading because they are retained when applying the result. New/open/history actions cancel pending imports. A new import also detaches from the selected saved dish to prevent accidentally replacing it. Failure leaves nutrition empty and offers retry or manual entry. No automatic printing or fetching on restore.

The normalized QR link and imported values use the existing FoodDraft JSON in SQLite. No schema migration is necessary. Synthetic fixture and state tests run in `test.sh`; no user recipe data is committed.
