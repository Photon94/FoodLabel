# Shared recipe import implementation plan

> Execute inline using superpowers:executing-plans; one independent final review.

Goal: paste sharing text and import the linked recipe name and verified nutrition.
Architecture: pure link parser and response decoder, isolated URLSession transport, AppModel-owned cancellable import, existing SwiftUI editor and persistence.
Tech stack: Swift/Foundation, SwiftUI, existing SQLite.
Spec: ../specs/2026-11-23-recipe-import-design.md

## Global constraints
- No automatic printing; preserve both printer profiles and local history.
- Only recognized hv.life recipe links trigger network calls. No login secrets embedded.
- Preserve exact QR link query values; reject ambiguous multiple-link text.
- Nutrition basis must be verified from actual source; do not guess.
- Late responses never overwrite newer edits.

## Tasks
1. Create Sources/RecipeImport.swift with SharedRecipeLink.parse(_:) and a validated recipe reference. Add Tests/RecipeImportTests.swift covering full sharing text, escaped colon, bare URL, other QR links, duplicate query parameters, multiple URLs and title extraction. Run failing tests, implement, run passing tests.
2. Verify the source request/response through static analysis of the official Android package. Implement ImportedRecipe decoding and a bounded ephemeral URLSession fetch for the verified endpoint. Add fixture tests for missing/invalid nutrition and known per-100 calculations; use synthetic IDs in committed fixtures.
3. Integrate AppModel.setRecipeLink(_:) and retry/cancel handling. Route both text-field editing and paste button through it. Add asynchronous tests with a fake importer for stale responses, user edits, failures and successful import. Loading recipes must leave printing disabled until valid values are ready.
4. Run complete tests and UI paste flow against the actual user-provided recipe without printing. Independent review; fix important findings. Build/install, preserve database, publish signed/notarized DMG using the already authorized workflow.

## Review focus
- Pasting a new recipe over an existing one must not retain mismatched nutrition.
- Manual typing, clearing, loading history, and late network responses must remain coherent.
- Untrusted/malformed source data must not become printable made-up nutrition.
- Link identifiers and personal recipe data must not leak to unrelated hosts or committed research files.
- Imported recipe basis and portion conversion must agree with the source app.
