# BUG: `applicationDidFinishLaunching` nie odpala się w Flutter 3.41.5 macOS

**Priorytet:** BLOCKER — bez tego Selection Assistant nie startuje  
**Odkryto:** 2026-03-24 00:55 UTC  
**Flutter:** 3.41.5 (stable, channel stable, revision 2c9eb20739, 2026-03-17)  
**macOS:** 26.3 (Tahoe) ARM64  
**Projekt:** `/Volumes/My Shared Files/git-main/kelivo`  
**Branch:** `SelectionAssistant`

---

## Problem

`AppDelegate.applicationDidFinishLaunching(_:)` w pliku `macos/Runner/AppDelegate.swift` **nigdy się nie wykonuje**. Żadne logi NSLog ani write-to-file testy nie potwierdzają wywołania.

To oznacza, że cały kod inicjalizacyjny Selection Assistant (AXObserver, FlutterEngine dla toolbar/result overlay) **nigdy się nie uruchamia**, mimo że app się normalnie odpala i pokazuje główne okno Flutter.

---

## Co zostało przetestowane

### 1. NSLog w `applicationDidFinishLaunching` — NIE pojawia się
Dodano `NSLog("[SA] startSelectionAssistant called")` i inne logi w key points. Zero output w stderr/stdout.

### 2. Write-to-file test — NIE tworzy pliku
```swift
// W applicationDidFinishLaunching:
try? "LAUNCHED".write(toFile: "/tmp/sa_test_didlaunch.txt", atomically: true, encoding: .utf8)
```
Plik `/tmp/sa_test_didlaunch.txt` nie został stworzony po starcie appki.

### 3. Uruchomienie bezpośrednie (nie przez `open`)
```bash
"/Volumes/.../kelivo.app/Contents/MacOS/kelivo" &
```
Ten sam wynik — brak logów.

### 4. `log show` — brak naszych logów
```bash
/usr/bin/log show --predicate 'process == "kelivo"' --last 6s
```
Tylko systemowe logi AppKit/XPC, zero `[SA]`.

### 5. Weryfikacja kompilacji
- `AppDelegate.o` istnieje w build intermediates
- `AppDelegate.swift` jest w `project.pbxproj` Sources
- `@main` attribute jest na klasie `AppDelegate`
- `nm` na binary pokazuje debug-related main symbols ale brak `_main` symbolu
- `strings` na binary nie zawiera stringów z AppDelegate (np. "startSelection")

### 6. Build się udaje
```
✓ Built build/macos/Build/Products/Debug/kelivo.app
flutter analyze: 0 errors
```

---

## Architektura projektu (relewantne pliki)

```
macos/Runner/
├── AppDelegate.swift          ← @main, applicationDidFinishLaunching (NIE ODPAŁA)
├── MainFlutterWindow.swift    ← awakeFromNib() tworzy FlutterViewController
├── SelectionWatcher.swift     ← AXObserver z 300ms debounce
├── ToolbarWindowManager.swift ← NSPanel floating toolbar
└── ResultWindowManager.swift  ← NSPanel result panel
```

**Brak `main.swift`** — projekt używa `@main` attribute na AppDelegate.

---

## Hipotezy

### 1. Flutter 3.41.5 zmienił sposób inicjalizacji AppDelegate
Nowy Flutter macOS template może używać innego mechanizmu niż `@main` + `FlutterAppDelegate`. Możliwe że `@main` macro generuje entry point, ale Flutter przejmuje NSApplication delegate setup przed `applicationDidFinishLaunching`.

### 2. `MainFlutterWindow.awakeFromNib()` przejmuje kontrolę
`MainFlutterWindow.awakeFromNib()` tworzy własny `FlutterViewController`, wywołuje `RegisterGeneratedPlugins`, ustawia MethodChannel. Może to interferuje z AppDelegate lifecycle.

### 3. `@main` attribute nie generuje `_main` symbol
`nm` nie pokazuje `_main` symbolu — to może oznaczać że `@main` nie jest prawidłowo połączony z entry pointem, a app startuje przez inny mechanizm (np. przez Info.plist `NSPrincipalClass` lub Flutter engine bootstrap).

---

## Co trzeba zrobić

1. **Zrozumieć jak Flutter 3.41.5 bootstrapuje macOS app** — sprawdzić docs/changelog dla Flutter 3.41
2. **Sprawdzić czy `@main` na AppDelegate jest poprawny** w nowym template vs stare `main.swift` + `@NSApplicationMain`
3. **Porównać z czystym nowym projektem** `flutter create --platforms=macos test_app` — czy tam `applicationDidFinishLaunching` odpala
4. **Sprawdzić czy problem jest specyficzny dla tego projektu** (może konflikt z custom `MainFlutterWindow.awakeFromNib()`)
5. **Naprawić inicjalizację** — może trzeba przenieść SA setup do `MainFlutterWindow.awakeFromNib()` albo do dedykowanego punktu

---

## Oczekiwane zachowanie po naprawie

Po starcie appki:
1. `applicationDidFinishLaunching` (lub equivalent) odpala się
2. Sprawdza `AXIsProcessTrusted()` — Accessibility permission
3. Odpala `SelectionWatcher.shared.start()` — AXObserver nasłuchuje zmian selekcji tekstu
4. SA działa od razu (default enabled: `UserDefaults.standard.object(forKey: "flutter.sa_enabled") as? Bool ?? true`)

---

## Kontekst: Selection Assistant

Selection Assistant to floating toolbar dla macOS, która pojawia się gdy użytkownik zaznaczy tekst w dowolnej appce. Oferuje: Translate, TTS, Send to Chat, Presets.

**Architektura flow:**
```
User selects text → AXObserver (SelectionWatcher)
  → ToolbarWindowManager.show() → NSPanel z akcjami
  → Akcja → ResultWindowManager.show()
  → ResultOverlayApp → ChatApiService → streaming Markdown
  → "Send to Chat" → ChatActionBus → DesktopHomePage input field
```

Kod SA jest napisany i reviewed (A rating od code-reviewer). Git commit `ba8ae86` na branch `SelectionAssistant`. **Jedynym blockerem jest ten bug z AppDelegate.**

---

## Pliki do zbadania

- `macos/Runner/AppDelegate.swift` — główny podejrzany, pełny kod SA init
- `macos/Runner/MainFlutterWindow.swift` — custom window setup, potencjalny konflikt
- `macos/Runner.xcodeproj/project.pbxproj` — build config
- `macos/Runner/Info.plist` — check NSPrincipalClass itp.

## Commits

- `ba8ae86` — "feat: Selection Assistant — floating toolbar for text selection actions" (27 files, 3427 insertions) — na GitHub: `leszek3737/kelivo`, branch `SelectionAssistant`
- Po tym commicie dodano NSLog + file-write testy (niezcommitowane) — do zrevertowania po diagnozie
