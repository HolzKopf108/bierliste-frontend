# bierliste-frontend

Flutter-Frontend für die Bierlisten-App. Nutzer können sich registrieren/anmelden, Gruppen ansehen, Striche erfassen und ihr Profil/Settings verwalten. Das Frontend spricht ein REST-Backend; insbesondere die Gruppenfunktionen sind teilweise nur UI-Prototypen oder nutzen Platzhalter-APIs (siehe Feature-Status und "Unklar / TBD").

## Projektüberblick
Die App ist als klassisches Mobile-Frontend aufgebaut (Material 3, Provider + ChangeNotifier). Der Fokus liegt aktuell auf Authentifizierung, Nutzerprofil/Settings, einem globalen Bier-Zähler mit Offline-Sync und ersten Gruppen-Screens. Die Backend-Integration ist für Auth, User/Settings und Counter vorhanden; Gruppen-Features sind teilweise nicht angebunden.

**Screens & Flows (Textbeschreibung)**
- **App-Start**: `LoadingPage` initialisiert Auth/Settings und routed je nach Status zu Login oder (derzeit) direkt zu einer festen Gruppe ("Bierfreunde"). `lib/screens/loading_page.dart`
- **Auth**: Login, Registrierung, E-Mail-Verifizierung, Passwort-Reset (Code anfordern, Code eingeben, neues Passwort). Google Sign-In ist integriert, Apple Sign-In UI ist deaktiviert. `lib/screens/login_page.dart`, `lib/screens/register_page.dart`, `lib/screens/verify_page.dart`, `lib/screens/forgot_password_page.dart`, `lib/screens/password_verify_page.dart`, `lib/screens/reset_password_page.dart`
- **Gruppen**: Gruppenübersicht, Gruppendetail, Mitgliederliste, Verlauf, Gruppeneinstellungen. Aktuell vor allem UI + lokale Daten/Platzhalter. `lib/screens/group_*`
- **Counter**: Globaler Bier-Zähler mit Offline-Puffer und Auto-Sync. `lib/screens/counter_page.dart`
- **Settings**: Profil, Passwortänderung, Theme, Auto-Sync. `lib/screens/settings_*`

## Feature-Status

### Implementiert (UI/Logik vorhanden)
- Auth: Registrierung, Login, E-Mail-Verify, Logout, Passwort-Reset-Flow (UI + API-Calls)
- Token-Handling inkl. Refresh und Secure Storage
- User-Profil (Username/Passwort) und Account-Löschen
- Theme (Hell/Dunkel/System) + Speicherung/Synchronisierung
- Auto-Sync/Offline für den globalen Counter
- Toasts & Custom Input-Formatter

### Teilweise / Geplant / Fehlt
- Gruppenverwaltung (Erstellen/Beitreten/Liste) ist aktuell lokal/statisch
- Gruppendetail/Strichliste pro Gruppe ist aktuell lokal und nicht persistiert
- Gruppenmitglieder, Rollen und Salden sind Dummy-Daten
- Gruppenaktivitäten und -einstellungen sind nicht sauber ans Backend angebunden
- Lokalisierung (i18n), Accessibility-Optimierung und Responsive-Breakpoints fehlen
- Tests/CI fehlen

### Feature-Matrix (Implementiert/Teilweise/Fehlt)
| Bereich | Status | Evidenz (Dateien/Klassen) |
| --- | --- | --- |
| Auth (Register/Login/Verify/Reset) | Implementiert | `lib/screens/login_page.dart`, `lib/services/auth_api_service.dart` |
| Google Sign-In | Implementiert (UI + API Call) | `lib/screens/login_page.dart`, `.env` |
| Token Storage + Refresh | Implementiert | `lib/services/token_service.dart`, `lib/services/http_service.dart` |
| User-Profil (Username/Passwort) | Implementiert | `lib/screens/settings_profil_page.dart`, `lib/services/user_service.dart` |
| User-Settings (Theme/Auto-Sync) | Implementiert | `lib/providers/theme_provider.dart`, `lib/services/user_settings_service.dart` |
| Globaler Counter + Offline Sync | Implementiert | `lib/screens/counter_page.dart`, `lib/services/offline_strich_service.dart` |
| Gruppenliste/Erstellen | Teilweise (lokal, ohne Backend) | `lib/screens/group_overview_page.dart` |
| Gruppendetail/Striche | Teilweise (lokal, ohne Backend) | `lib/screens/group_home_page.dart` |
| Gruppenmitglieder/Rollen/Saldo | Teilweise (Dummy-Daten) | `lib/screens/group_users_page.dart` |
| Gruppenaktivitäten | Teilweise (API unklar) | `lib/screens/group_activity_page.dart` |
| Gruppeneinstellungen | Teilweise (Platzhalter-API) | `lib/screens/group_settings_page.dart` |
| Lokalisierung (i18n) | Fehlt | keine `l10n/` oder ARB-Dateien vorhanden |
| Tests/CI | Fehlt | keine `test/` oder `.github/` |

## Architektur & Struktur

**State Management**
- Provider + ChangeNotifier (`lib/providers/*`)

**Routing/Navigation**
- Navigator 1.0 mit `onGenerateRoute` in `lib/routes/app_routes.dart`
- `MaterialApp` nutzt `navigatorKey` für globale Navigation (`lib/main.dart`, `lib/utils/navigation_helper.dart`)

**Wichtige Module (Auszug)**
- `lib/main.dart` / `lib/app.dart`: App-Start, Provider-Setup, Themes, Routing
- `lib/config/`: Theme (`app_theme.dart`), API-Konfiguration (`app_config.dart`)
- `lib/services/`: API-Clients, HTTP, Token, Offline-Sync
- `lib/providers/`: Auth, User, Theme, Sync
- `lib/screens/`: UI-Flows
- `lib/models/`: Hive-Modelle (`User`, `UserSettings`, `Counter`)
- `lib/utils/`: Navigation-Helper, Money-Formatter
- `lib/widgets/`: Toast

## Konfiguration

- **Dart SDK**: `^3.8.1` (siehe `pubspec.yaml`)
- **Flutter SDK**: keine feste Version im Repo; kompatible Flutter-Version mit Dart 3.8.x verwenden
- **Unterstützte Plattformen (im Repo angelegt)**: Android, iOS, Web, Windows, macOS, Linux
- **Flavors/Build-Varianten**: keine konfiguriert
- **Environment/Secrets**
  - `.env` wird geladen (`flutter_dotenv`), Variable: `GOOGLE_WEB_CLIENT_ID`
  - `.env.example` vorhanden als Vorlage
  - `lib/config/app_config.dart` enthält statische API-Endpoints (Base-URL im Repo gesetzt, hier nicht ausgeschrieben)

## Backend-Integration

**API-Base-URL**
- In `lib/config/app_config.dart` als `AppConfig.apiBaseUrl` hinterlegt (Wert hier absichtlich nicht ausgeschrieben).
- Beispiel-Form: `https://<backend-host>/api` + `apiVersion` (z. B. `/v1`)

**Auth-Mechanik**
- Login/Verify liefert `accessToken` + `refreshToken`
- Speicherung in `FlutterSecureStorage` (`lib/services/token_service.dart`)
- `HttpService.authorizedRequest` setzt `Authorization: Bearer <token>` und refresht bei 401 automatisch (`lib/services/http_service.dart`)

**Wichtige API-Clients/Services**
- `AuthApiService`: `/auth/*` (login, register, verify, refresh, resetPassword, google, etc.)
- `UserApiService`: `/user`, `/user/updatePassword`, `/user/settings`, `/user/logout`, `/user/delete/account`
- `CounterApiService`: `/counter`
- `ConnectivityService`: `/ping`
- `UserSettingsApiService`: `/user/settings`, `/user/settings/verifyPassword`
- `GroupActivityPage` nutzt `/activities` direkt (ohne HttpService) -> siehe TBD

**Error-Handling/Retry**
- Fehlermeldungen werden als String zur UI zurückgegeben (Dialog/Toast)
- Automatisches Retry nur für Token-Refresh (401)
- Timeout nur im Connectivity-Check (3s) in `ConnectivityService`

**Mocking/Stubbing**
- Kein Mocking/Stubbing im Repo vorhanden

## UI/UX

**Wichtigste Screens**
- Login / Register / Verify / Passwort Reset (`lib/screens/*_page.dart`)
- Gruppen: Übersicht, Detail, Mitglieder, Verlauf, Einstellungen (`lib/screens/group_*`)
- Counter: globaler Bier-Zähler (`lib/screens/counter_page.dart`)
- Settings: Profil, Theme, Auto-Sync (`lib/screens/settings_*`)

**Designsystem/Theme**
- `AppTheme.light` und `AppTheme.dark` mit Material 3 (`lib/config/app_theme.dart`)
- Wiederverwendbar: `Toast`, `MoneyInputFormatter`

**Lokalisierung & Accessibility**
- Texte sind aktuell fest auf Deutsch, keine i18n-Struktur vorhanden
- Keine expliziten Accessibility-Optimierungen (Semantics, grössere Fonts) dokumentiert

**Responsiveness**
- Standard Flutter-Layouts, keine spezifischen Breakpoints

## Setup & Run

**Voraussetzungen**
- Flutter SDK (kompatibel zu Dart 3.8.x)
- Android Studio (Android) / Xcode (iOS)
- Optional: FVM (nicht konfiguriert)

**Installation**
```bash
flutter pub get
```

**Environment**
```bash
cp .env.example .env
# GOOGLE_WEB_CLIENT_ID setzen (für Google Sign-In)
```

**Starten**
```bash
flutter run
# optional: flutter run -d chrome
```

**Build/Release (Beispiele)**
```bash
flutter build apk --release
flutter build ios --release
flutter build web --release
```

**Assets-Generierung (falls Logos geändert)**
```bash
dart run flutter_native_splash:create
flutter pub run flutter_launcher_icons:main
```

## Tests
- Keine dedizierten Unit-/Widget-/Integration-Tests vorhanden (`test/` und `integration_test/` fehlen).

## Assets & Lizenzen
- App-Icons & Splash: `assets/` (u. a. `bierliste_icon.png`, `bierliste_logo_kreis_padding.png`)
- Web-Icons & Splash: `web/`

## Roadmap (priorisiert)
1. Gruppen-Backend-Integration: echte Gruppenliste, Join/Create, Details, Rollen, Preise
2. Strich-Logik pro Gruppe inkl. Sync, Rollenberechtigungen und Salden
3. Gruppenaktivitäten & Einstellungen über `HttpService` inkl. Auth
4. Tests (Unit für Services/Provider, Widget-Tests für Auth/Settings)
