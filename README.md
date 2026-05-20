# WhatPrice

An app for costing and pricing baked goods based on ingredients, oven energy use,
and (optionally) labour. Built with Flutter — runs on Android and Windows.

## What it does

- Save **ingredients** (identity: name, unit, allergen flags) and a **price per
  pantry** (e.g. 1500 g flour for $4.50 at Home, $4.20 at Work).
- Save **recipes**: yield (pieces), bake time, labour time, multi-image carousel,
  notes, and ingredient quantities. Recipes are shared across pantries.
- **Calculate tab**: pick a recipe and pantry, tweak margin % and labour
  inclusion, see the cost breakdown, and save the result as a snapshot. The
  Recipes list and recipe page read the most recent snapshot per (recipe, pantry).
- **Production tracking**: log when a recipe was made, in which pantry, with how
  many batches and free-text notes. Per-recipe history is visible on the
  recipe page; the recipe list shows a "Made N×" chip.
- **Bulk PDF export**: multi-select recipes on the list, share/save them as a
  single zip containing one A4 PDF per recipe.
- **Allergens**: tag ingredients with allergen flags (gluten, dairy, egg, soy,
  peanut, tree nut, sesame, sulphite, fish, crustacean, mollusc, celery,
  mustard, lupin). Recipes display the union of their ingredients' allergens.
- **Multi-pantry**: separate workspaces with their own prices. Switch via the
  app-bar pantry chip. Settings → Pantries to rename / add / delete.
- **Cloud sync (optional)**: bidirectional sync with a self-hosted PocketBase
  instance over your network. Off by default; see [Cloud sync](#cloud-sync) below.

Pricing formula: `suggested_price = cost ÷ (1 − margin%)`.
Energy cost: `(bake_minutes / 60) × oven_kW × electricity_rate`.

## First-time setup

You need the Flutter SDK installed: <https://docs.flutter.dev/get-started/install>.

The repo only contains `pubspec.yaml` and `lib/` — the platform folders
(`android/`, `windows/`) need to be generated once:

```bash
flutter create --platforms=android,windows --org com.whatprice -t app .
flutter pub get
```

If `flutter create` asks to overwrite `pubspec.yaml` or `lib/main.dart`, **say no**
(or run it before pulling, then re-apply this repo's files).

## Run

```bash
# Windows desktop
flutter run -d windows

# Android (device plugged in or emulator running)
flutter run -d android

# List available devices
flutter devices
```

## Build release artifacts

```bash
# Windows .exe (output in build/windows/x64/runner/Release/)
flutter build windows

# Android APK (output in build/app/outputs/flutter-apk/)
flutter build apk --release
```

## Where data lives

A local SQLite database at the platform's app-documents directory
(`whatprice.db`). Images live alongside under `whatprice_images/`. If cloud sync
is configured, the same data is mirrored to a PocketBase instance.

## Cloud sync

Sync is optional and aimed at running PocketBase on your own server (e.g. a
Proxmox LXC or VM reachable over your private network — TLS is not required if
the network itself is trusted, but the Android build allows cleartext HTTP).

### Server setup

1. Download a PocketBase binary from <https://pocketbase.io/docs>.
2. Start it: `./pocketbase serve --http=0.0.0.0:8090`.
3. Open the admin UI at `http://<server-ip>:8090/_/` and create an admin user.
4. Create the collections listed below. **For each one**, set the API rules
   (List/View/Create/Update/Delete) to an empty string so the app can read/write
   without an auth token.

### Collections to create

Every collection has these common fields in addition to the ones listed:

- `sync_id` — text, **unique**, required
- `updated_at` — text (we store ISO 8601 UTC)
- `deleted_at` — text, nullable (tombstone)

| Collection            | Other fields                                                                                                                                                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pantries`            | `name` (text)                                                                                                                                                                                                                         |
| `ingredients`         | `name` (text), `unit` (text), `allergen_flags` (number)                                                                                                                                                                               |
| `ingredient_prices`   | `pack_size` (number), `pack_cost` (number), `ingredient_sync_id` (text), `pantry_sync_id` (text)                                                                                                                                       |
| `recipes`             | `name` (text), `yield_pieces` (number), `oven_minutes` (number), `labour_minutes` (number), `notes` (text)                                                                                                                            |
| `recipe_ingredients`  | `quantity` (number), `recipe_sync_id` (text), `ingredient_sync_id` (text)                                                                                                                                                             |
| `recipe_images`       | `sort_order` (number), `recipe_sync_id` (text), `image` (file — single file, allow common image MIME types)                                                                                                                            |
| `recipe_cost_snapshots` | `margin_percent` (number), `include_labour` (number), `ingredients_cost` (number), `energy_cost` (number), `labour_cost` (number), `cost_per_piece` (number), `suggested_price_per_piece` (number), `suggested_batch_price` (number), `computed_at` (text), `recipe_sync_id` (text), `pantry_sync_id` (text) |
| `productions`         | `made_at` (text), `batches` (number), `cost_per_piece` (number), `notes` (text), `recipe_sync_id` (text), `pantry_sync_id` (text)                                                                                                     |

The `*_sync_id` text fields are how the app cross-references records between
devices — they store the *target row's* `sync_id`. The app maps them to local
integer foreign keys on pull.

### App configuration

In Settings → Cloud sync:

1. Enter your server URL (e.g. `http://10.144.1.5:8090`).
2. Tap **Save URL**.
3. Tap **Sync now**. The first run uploads everything you have locally and pulls
   anything that's already on the server.

Subsequent syncs only move the rows that changed since last time. Last-write-
wins on conflict (newer `updated_at` wins). Soft deletes propagate via the
`deleted_at` column.

### What's not synced

- App settings (currency symbol, electricity rate, oven kW, hourly wage) are
  intentionally device-local — each device can have its own electrical setup.

## Project layout

```
lib/
  main.dart                    app entry, startup error UI
  models.dart                  data classes
  database.dart                SQLite open + migrations
  app_state.dart               ChangeNotifier wrapping CRUD + soft-delete
  cost.dart                    pure cost calculation
  format.dart                  money / number formatting
  allergens.dart               Allergen enum + bitmask
  screens/                     all top-level screens
  services/
    image_storage.dart         picking + saving recipe images
    pdf_export.dart            per-recipe PDF generation
    bulk_export.dart           zip + share/save
  widgets/                     reusable UI bits
  sync/
    collection_defs.dart       per-collection sync schema
    sync_service.dart          push/pull engine + image upload
```
