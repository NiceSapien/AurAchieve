# GitHub Copilot Instructions for AurAchieve

## Project Overview
AurAchieve is a Flutter application focused on productivity and habit tracking.
It uses **Appwrite** for backend services (Auth, Database, Functions) and **Material 3** for UI.

## Tech Stack & Dependencies
- **Framework**: Flutter (Dart 3.x)
- **Backend**: Appwrite (`appwrite` package)
- **Local Storage**: `shared_preferences`, `flutter_secure_storage`
- **UI/Theming**: `dynamic_color`, `google_fonts` (Gabarito), `flutter_svg`
- **Features**:
  - `wakelock_plus` for Timer/Focus modes.
  - `flutter_local_notifications` for reminders.
  - `confetti` for celebrations.

## Code Style & Conventions
- **State Management**: Prefer simple state management (`setState`, `ValueNotifier`) for local widget state. Avoid complex boilerplate unless necessary.
- **UI Components**:
  - Use **Material 3** widgets.
  - Font: **Gabarito** (via `GoogleFonts.gabarito()`).
  - Use `ConstrainedBox(maxWidth: 460)` for centered layouts on larger screens (web/desktop).
- **Asynchronous Operations**:
  - Handle "Offline Mode" gracefully (see `social_blocker.dart`).
  - Sync local state with Appwrite when online.

## Specific Patterns
- **Timer/Stopwatch**: Uses `Timer.periodic` and `CustomPainter` for rings/dots.
- **Appwrite Integration**:
  - Auth flow is in `main.dart` and `onboard.dart`.
  - Use `ApiService` (if available) or direct Appwrite calls.
- **Offline Logic**:
  - Check connectivity before Appwrite calls.
  - Fallback to `SharedPreferences` for critical user data (e.g., "Give Up" counts).

## Common Tasks
- **Adding Dependencies**: Always check `pubspec.yaml` and run `flutter pub get`.
- **Fixing Build Errors**: If `GeneratedPluginRegistrant` fails, run `flutter clean` and check for transitive dependency conflicts (especially `_plus` packages).
