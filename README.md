# WhatPrice

An app for costing and pricing baked goods based on ingredients, oven energy use,
and (optionally) labour. Built with Flutter — runs on Android and Windows.

## What it does

- Save **ingredients** with the pack size and what you paid (e.g. 1500 g flour for $4.50).
- Save **recipes**: yield (pieces), bake time, labour time, and ingredient quantities.
- See a live **cost breakdown** per recipe: ingredients + energy + labour.
- Get the **cost per piece** and a **suggested sale price** based on your target margin.
- **Settings**: electricity rate, oven kW, hourly wage, margin %, currency symbol,
  toggle to include or exclude labour from the cost.

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
(`whatprice.db`). No accounts, no cloud — single user, on-device.

## Project layout

```
lib/
  main.dart                    app entry, theme
  models.dart                  Ingredient, Recipe, RecipeIngredient, AppSettings
  database.dart                SQLite open + schema
  app_state.dart               ChangeNotifier wrapping CRUD
  cost.dart                    pure cost calculation
  format.dart                  money / number formatting
  screens/
    home_screen.dart           bottom-nav shell
    recipes_screen.dart        recipes list with cost preview
    recipe_edit_screen.dart    recipe editor with live cost breakdown
    ingredients_screen.dart    ingredients list
    ingredient_edit_screen.dart
    settings_screen.dart
```
