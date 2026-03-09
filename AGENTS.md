# AGENTS.md

## Projekt
Dieses Repository enthält das Flutter-Frontend der Bierliste-App.

Tech-Stack / Architektur:
- Flutter
- Dart
- Material 3
- Provider + ChangeNotifier
- REST-Backend
- Secure Storage für Tokens
- Offline-/Auto-Sync-Logik in Teilen vorhanden

## Ziel
Arbeite so, dass bestehende Architektur, Namenskonventionen, Navigation und State-Management-Patterns des Repos beibehalten werden.

## Harte Arbeitsregel
Bevor du neue Klassen, Screens, Services, Provider oder Modelle anlegst:
1. prüfe, ob es bereits ähnliche Implementierungen im Repo gibt
2. orientiere dich an vorhandenen Patterns und Dateinamen
3. ändere nur den Scope des aktuellen Issues
4. vermeide unnötige Refactorings

## Bestehende Architektur respektieren
- State Management bleibt standardmäßig bei Provider + ChangeNotifier
- Navigation orientiert sich an der bestehenden Routing-Struktur
- API-Zugriffe sollen vorhandene Services/HTTP-Helfer wiederverwenden
- Token-/Auth-Handling nicht neu erfinden, sondern bestehende Mechanismen nutzen
- Offline-/Sync-Logik nur erweitern/refactorn, nicht parallel neu aufbauen

## Wichtige Konventionen
- Bestehende Ordnerstruktur beibehalten:
  - `lib/screens`
  - `lib/services`
  - `lib/providers`
  - `lib/models`
  - `lib/widgets`
  - `lib/utils`
  - `lib/config`
- Neue Dateien konsistent zu bestehenden Namen benennen
- Keine neuen Architekturmuster einführen (z. B. Riverpod, Bloc, Redux), wenn nicht ausdrücklich verlangt
- Keine großen Umstrukturierungen ohne ausdrückliche Aufforderung
- Bestehendes UI-Pattern und bestehende UX-Entscheidungen respektieren

## API- und Backend-Integration
- Vor neuen API-Calls immer prüfen, ob es bereits einen passenden Service gibt
- Bestehende HTTP-/Auth-/Refresh-Mechanismen wiederverwenden
- Keine direkten HTTP-Calls an zufälligen Stellen im UI, wenn bereits Service-Schichten existieren
- Request-/Response-Verarbeitung am bestehenden Backend orientieren
- Fehlerbehandlung konsistent zur bestehenden App umsetzen
- Gruppenfunktionen möglichst so anbinden, dass spätere Backend-Integration leicht bleibt
- Schaue immer in die openapi.json im root Verzeichnis, dort stehen die APIs des Backends drin und wie genau die implementiert sind!

## UI / Screens
- Screens schlank halten
- Business-Logik nicht unnötig in Widgets mischen
- Wiederverwendbare UI-Teile in Widgets oder bestehende Hilfsstrukturen auslagern
- Material-3-Stil und bestehende App-Gestaltung respektieren
- Keine überkomplizierten Animationen oder neue UI-Systeme einführen
- UX pragmatisch halten: klar, mobilfreundlich, wenige überraschende Interaktionen

## Provider / State
- State dort halten, wo er im bestehenden Projekt sinnvoll liegt
- Keine doppelte State-Haltung zwischen Screen, Service und Provider einführen
- ChangeNotifier nur gezielt erweitern
- Vor neuen Providern prüfen, ob bestehende Provider erweitert werden sollten

## Services
- API-Logik in Services, nicht direkt in Screens
- Bestehende Services zuerst prüfen und erweitern
- Keine parallelen/duplizierten Services für ähnliche Endpunkte bauen
- Response-Mapping und Error-Handling konsistent halten

## Modelle / DTO-nahe Klassen
- Bestehende Model-Strukturen respektieren
- Keine unnötigen neuen Datenstrukturen, wenn vorhandene Models erweitert werden können
- Serialisierung/Deserialisierung konsistent lösen
- Bei temporären Platzhalterdaten klar zwischen Dummy-Daten und echter Backend-Integration trennen

## Offline / Sync
- Vor Änderungen immer bestehende Offline-/Sync-Logik prüfen
- Keine konkurrierenden Sync-Mechanismen einführen
- Pending-/Unsynced-Status für User nachvollziehbar halten
- Konfliktanfällige Schreiblogik nicht nur UI-seitig „lösen“, sondern mit Backend-Vertrag zusammendenken

## Fehlerbehandlung
- Nutzerfreundliche Fehlermeldungen anzeigen
- Keine stillen Fehler verschlucken
- Technische Details nur intern/logisch behandeln, nicht ungefiltert im UI anzeigen
- Vorhandene Toasts/Feedback-Mechanismen bevorzugt wiederverwenden

## Tests
- Wenn neue Tests ergänzt werden:
  - vorhandene Projektstruktur respektieren
  - Tests einfach und gezielt halten
  - Fokus auf kritische Logik (Services, Provider, zentrale Flows)
- Wenn noch keine Tests vorhanden sind, keine riesige Testarchitektur einführen ohne Auftrag
- Für neue Features möglichst mindestens die wichtigste Logik testbar halten

## Code-Stil
- Bestehenden Stil des Repos nachahmen
- Kleine, fokussierte Änderungen bevorzugen
- Keine inline Kommentare
- Keine neuen Packages einführen, wenn nicht nötig
- Imports, Benennungen und Dateiablage konsistent halten

## GitHub-Issue-Umsetzung
Wenn ein GitHub-Issue umgesetzt wird:
1. zuerst ähnliche bestehende Implementierungen im Repo suchen
2. Akzeptanzkriterien vollständig lesen
3. nur den Scope dieses Issues umsetzen
4. keine Folgefeatures „gleich mit erledigen“, außer sie sind technisch zwingend
5. am Ende kurz prüfen:
   - ist die UI konsistent?
   - nutzt es bestehende Services/Provider?
   - passt es zur Backend-API?
   - wurden Platzhalter klar vermieden oder markiert?

## Bei Unklarheit
- Erst im Repo nach bestehenden Mustern suchen
- Lieber konsistent mit dem Projekt als generisch „schön“
- Bei Architekturentscheidungen bestehende Implementierung priorisieren
