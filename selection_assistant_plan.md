# Selection Assistant — Plan Implementacji (macOS, NSPanel)

> Status: Draft v5
> Data: 2026-03-23
> Zakres: wyłącznie macOS
> Autor: analiza techniczna (nie modyfikować kodu bez osobnej decyzji)

---

## 1. Co to ma robić

Aplikacja działa w tle (tray). Użytkownik zaznacza tekst w **dowolnej innej aplikacji** systemowej. W pobliżu zaznaczenia pojawia się mały floating **Toolbar Panel** z przyciskami — nie kradnie focusu, nie przerywa pracy. Kliknięcie akcji otwiera **Result Panel** z wynikiem bezpośrednio w floating okienku. Oba panele mogą być widoczne jednocześnie — toolbar nie zamyka się automatycznie po kliknięciu akcji. Użytkownik zamyka panele ręcznie lub przez dismiss logic.

### Typy paneli

| Panel | Opis | Rozmiar |
|-------|-------|---------|
| **Toolbar** | Rząd ikon akcji, frosted glass | ~320×48 |
| **Result (standard)** | Tytuł + Markdown + copy/TTS | ~400×auto (dynamiczna wysokość, max 500px ze scrollem) |
| **Result (translation)** | Selektor języka + treść + copy/TTS | ~400×auto |

### Przyciski toolbara

| Przycisk | Akcja | Wynik |
|----------|-------|-------|
| 🌐 Tłumacz | Tłumaczy tekst przez LLM (ChatApiService z promptem tłumaczenia) | Result Panel (wariant tłumaczenia: selektor języka + treść) |
| 🔊 Czytaj | Przekazuje tekst do TtsProvider w toolbar engine | Brak okna — tylko audio |
| 💬 Wyślij do czatu | Focusuje główne okno Kelivo | Otwiera ostatni aktywny czat, wkleja tekst do pola wiadomości |
| ✨ Preset 1–N | Wysyła tekst + prompt do LLM (ChatApiService) | Result Panel (tytuł presetu + Markdown) |

### Predefiniowane presety (MVP — hardcoded)

| Preset | Prompt template | Asystent |
|--------|-----------------|----------|
| Podsumuj | `Podsumuj zwięźle: {{text}}` | domyślny (pierwszy z listy asystentów) |
| Wyjaśnij | `Wyjaśnij prosto: {{text}}` | domyślny |
| Popraw gramatykę | `Popraw gramatykę i styl: {{text}}` | domyślny |
| Przetłumacz i przeczytaj | Translate → TTS sekwencyjnie | domyślny |

> **WAŻNE (lokalizacja):** Nazwy presetów i prompt templates są user-visible — muszą być zlokalizowane przez ARB (4 pliki: en, zh, zh_Hans, zh_Hant). Hardcoded != hardcoded po polsku. Klucze ARB: `saPresetSummarize`, `saPresetExplain`, `saPresetFixGrammar`, `saPresetTranslateAndRead`. Prompt templates również zlokalizowane — LLM dostaje prompt w języku UI użytkownika.

> **Domyślny asystent (MVP):** `AssistantProvider.currentAssistant` — zwraca aktualnie wybranego, a jeśli null to pierwszy z listy (`_assistants.first`). Overlay engine czyta `current_assistant_id_v1` i `assistants_v1` z SharedPreferences.

> **Pełna wersja (post-MVP):** osobna zakładka w ustawieniach — dodawanie/edycja/usuwanie custom akcji (do 10), wybór asystenta per-akcja.

---

## 2. Wymagania systemowe

- macOS 12+ (AXObserver stabilny od 10.x)
- Jednorazowe przyznanie uprawnień **Accessibility** przez użytkownika w Ustawienia systemowe → Prywatność i bezpieczeństwo → Dostępność
- `Info.plist` musi zawierać klucz `NSAccessibilityUsageDescription` z opisem po co to uprawnienie

---

## 3. Architektura

### 3.1 Zasada: osobne FlutterEngine per NSPanel

Flutter macOS **nie wspiera** shared engine z wieloma `runApp()`. `FlutterEngineGroup` jest dostępne tylko na iOS/Android. Flutter multi-view jest eksperymentalne i niestabilne.

Dlatego każdy NSPanel ma **własny FlutterEngine** z osobnym Dart isolatem i własnym entry pointem. To oznacza:
- **Brak współdzielonych providerów** — każdy engine inicjalizuje własny minimalny provider tree
- **Spójność danych** — providery czytają z tych samych SharedPreferences/Hive, więc dane są zgodne
- **Ograniczenie:** zmiana ustawień w głównym oknie (np. język) wymaga restartu overlay engine aby się odzwierciedliła. W MVP akceptowalne.
- **Koszt pamięci:** ~30-50 MB per dodatkowy FlutterEngine. Przy dwóch panelach = ~60-100 MB. Na desktopie akceptowalne.

### 3.2 Rejestracja pluginów w secondary engine (WYMAGANE)

Flutter automatycznie rejestruje pluginy (`flutter_tts`, `shared_preferences`, itp.) **tylko dla głównego engine**. Każdy secondary engine wymaga jawnej rejestracji:

```swift
let resultEngine = FlutterEngine(name: "result", project: nil, allowHeadlessExecution: false)
resultEngine.run(withEntrypoint: "resultOverlay")
GeneratedPluginRegistrant.register(with: resultEngine)  // ← KRYTYCZNE
```

Bez tego żadne pluginy Dart (TTS, SharedPreferences) nie będą działać w overlay engine'ach.

### 3.3 Leniwe tworzenie engine'ów

Engine'y **nie są tworzone przy starcie aplikacji**. Tworzenie następuje dopiero gdy użytkownik włączy Selection Assistant (`sa_enabled = true`). Wyłączenie SA → Swift chowa oba panele, zatrzymuje AXObserver, niszczy engine'y i zwalnia pamięć.

Ponowne włączenie → engine'y tworzone na nowo.

### 3.4 Diagram architektury

```
┌──────────────────────────────────────────────────────────────┐
│                     WARSTWA SWIFT (macOS)                     │
│                                                              │
│  SelectionWatcher.swift                                      │
│    - AXObserver subskrybuje kAXSelectedTextChangedNotif.     │
│      na aktywnej aplikacji (NSWorkspace.didActivateApp)      │
│    - Debounce 300ms — nie reaguje na każdy znak              │
│    - Odczytuje kAXSelectedTextAttribute                      │
│    - Odczytuje NSEvent.mouseLocation                         │
│    - Sprawdza UserDefaults: flutter.sa_enabled, minLength    │
│    - Filtruje: < 3 znaków, > sa_maxTextLength, whitespace   │
│    - Jeśli tekst OK → wywołuje ToolbarWindowManager.show()   │
│                                                              │
│  ToolbarWindowManager.swift                                  │
│    - Tworzy NSPanel + FlutterEngine (entry: toolbarOverlay)  │
│    - GeneratedPluginRegistrant.register(with: engine)        │
│    - NSWindowStyleMask: .nonactivatingPanel + .borderless    │
│    - NSWindowLevel: .floating                                │
│    - Smart positioning przy kursorze                         │
│    - Wysyła tekst do toolbar Dart przez MethodChannel        │
│    - Dismiss: globalMonitor (ignoruje kliknięcia w obu       │
│      panelach) + timer (wstrzymany gdy result widoczny)      │
│    - Engine tworzony leniwie, niszczony przy sa_enabled=false│
│                                                              │
│  ResultWindowManager.swift                                   │
│    - NSPanel + FlutterEngine (entry: resultOverlay)          │
│    - GeneratedPluginRegistrant.register(with: engine)        │
│    - Nowa akcja zamyka poprzedni result i otwiera nowy       │
│    - Toolbar pozostaje widoczny                              │
│    - Dynamiczny resize: Dart raportuje contentHeight →       │
│      Swift resizuje NSPanel frame (max 500px)                │
│    - Engine tworzony leniwie, niszczony przy sa_enabled=false│
│                                                              │
│  Swift pełni rolę ROUTERA między engine'ami:                 │
│    - Toolbar Dart → (akcja) → Swift → Result Dart            │
│    - Toolbar Dart → (chat) → Swift → Main Dart               │
│    - Nowe zaznaczenie → zamknij result + przesuń toolbar     │
└──────────────────┬───────────────────────────────────────────┘
                   │
     ┌─────────────┼─────────────────────────────┐
     │             │                             │
     ▼             ▼                             ▼
┌─────────┐  ┌──────────┐               ┌──────────────┐
│ MAIN    │  │ TOOLBAR  │               │ RESULT       │
│ ENGINE  │  │ ENGINE   │               │ ENGINE       │
│         │  │          │               │              │
│ main()  │  │ toolbar  │               │ result       │
│         │  │ Overlay  │               │ Overlay      │
│ Pełna   │  │ ()       │               │ ()           │
│ apka    │  │          │               │              │
│ Kelivo  │  │ Overlay  │               │ Overlay      │
│         │  │ Settings │               │ Settings     │
│         │  │ Provider │               │ Provider +   │
│         │  │ +        │               │ ChatApi +    │
│         │  │ Tts      │               │ TtsProvider  │
│         │  │ Provider │               │              │
└─────────┘  └──────────┘               └──────────────┘
```

### 3.5 Kanały komunikacji (MethodChannel)

Każdy engine ma **własny** MethodChannel. Swift trzyma referencje do binaryMessenger każdego engine.

**Toolbar engine ↔ Swift:**
```
Channel: "app.selectionAssistant/toolbar"
  Swift → Dart:
    setText(text)              // przekazuje zaznaczony tekst
  Dart → Swift:
    onAction(action, text)     // użytkownik kliknął akcję
      action: "translate" | "tts" | "chat" | "preset:<name>"
    dismiss()                  // toolbar chce się zamknąć
```

**Result engine ↔ Swift:**
```
Channel: "app.selectionAssistant/result"
  Swift → Dart:
    showResult(title, type, sourceText, targetLang?)
      type: "standard" | "translation"
    hideResult()
  Dart → Swift:
    reportHeight(height)       // dynamiczny resize panelu
    dismiss()                  // result chce się zamknąć
```

**Main engine (istniejący) ↔ Swift:**
```
Channel: "app.selectionAssistant/main"
  Swift → Dart:
    focusAndSetText(text)      // "wyślij do czatu" — focus okna + tekst w polu
```

---

## 4. Kluczowe decyzje techniczne

### 4.1 NSPanel — dlaczego nie NSWindow

| Właściwość | NSWindow | NSPanel (nonactivatingPanel) |
|------------|----------|------------------------------|
| Kradnie focus | Tak | Nie |
| Pojawia się w Mission Control | Tak | Nie |
| Widoczny gdy inna app na wierzchu | Nie | Tak (floating level) |
| Właściwy dla overlay UI | Nie | Tak |

### 4.2 Dwa osobne FlutterEngine — osobne entry points

Każdy NSPanel ma własny `FlutterEngine` z osobnym Dart isolatem. Brak współdzielonego stanu w runtime — dane spójne przez wspólny storage (SharedPreferences/Hive).

Entry points w Dart:

```dart
// main.dart
@pragma('vm:entry-point')
void toolbarOverlay() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OverlaySettingsProvider()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
      ],
      child: const ToolbarOverlayApp(),
    ),
  );
}

@pragma('vm:entry-point')
void resultOverlay() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OverlaySettingsProvider()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
        // ChatApiService jest statyczny — nie potrzebuje providera
      ],
      child: const ResultOverlayApp(),
    ),
  );
}
```

Po stronie Swift:
```swift
// Engine'y tworzone LENIWIE — dopiero przy sa_enabled = true
func createEngines() {
    let toolbarEngine = FlutterEngine(name: "toolbar", project: nil, allowHeadlessExecution: false)
    toolbarEngine.run(withEntrypoint: "toolbarOverlay")
    GeneratedPluginRegistrant.register(with: toolbarEngine)

    let resultEngine = FlutterEngine(name: "result", project: nil, allowHeadlessExecution: false)
    resultEngine.run(withEntrypoint: "resultOverlay")
    GeneratedPluginRegistrant.register(with: resultEngine)
}
```

### 4.3 OverlaySettingsProvider — lekki wariant

Pełny `SettingsProvider` ma ~3900 linii i ładuje 50+ kluczy. Overlay'e nie potrzebują tego wszystkiego.

`OverlaySettingsProvider` czyta z SharedPreferences **tylko**:
- `provider_configs_v1` — konfiguracja providerów LLM (wymagane dla ChatApiService)
- `selected_model_v1` — aktywny model
- `assistants_v1` + `current_assistant_id_v1` — asystenci (dla presetów)
- `flutter.sa_translateTargetLanguage` — język tłumaczenia
- `enable_math_rendering` — dla MarkdownWithCodeHighlight
- `enable_dollar_latex` — j.w.
- `custom_font_family` — j.w.
- `theme_mode_v1` — motyw

To ~8 kluczy zamiast 50+. Inicjalizacja szybka i lekka.

### 4.4 Uproszczony przepływ (Swift zarządza show/hide)

```
1. Użytkownik zaznacza tekst w dowolnej aplikacji
2. AXObserver → SelectionWatcher wykrywa zmianę
3. SelectionWatcher sprawdza UserDefaults (flutter.sa_enabled, flutter.sa_maxTextLength)
4. Filtruje: < 3 znaków, > maxTextLength (domyślnie 5000), czysty whitespace
5. Swift → ToolbarWindowManager.show(text, x, y)
6. Swift → toolbar MethodChannel: setText(text)
7. Toolbar Dart renderuje przyciski

8a. Użytkownik klika "Tłumacz":
    Toolbar Dart → onAction("translate", text) → Swift
    Swift → ResultWindowManager.show(obok toolbara)
    Swift → result MethodChannel: showResult("Tłumacz", "translation", text, "pl")
    Result Dart wywołuje ChatApiService z promptem tłumaczenia → renderuje Markdown

8b. Użytkownik klika "Czytaj":
    Toolbar Dart → onAction("tts", text) → Swift
    Swift potwierdza → Toolbar Dart → TtsProvider.speak(text)
    (Toolbar engine ma własny TtsProvider zarejestrowany przez GeneratedPluginRegistrant)

8c. Użytkownik klika "Wyślij do czatu":
    Toolbar Dart → onAction("chat", text) → Swift
    Swift → pokazuje/odtwarza główne okno (NSApp.activate + window.makeKeyAndOrderFront)
    Swift → main MethodChannel: focusAndSetText(text)
    Main Dart → ChatActionBus.fire(ChatAction.focusInputWithText(text))

8d. Użytkownik klika preset:
    Toolbar Dart → onAction("preset:summarize", text) → Swift
    Swift → ResultWindowManager.show(obok toolbara)
    Swift → result MethodChannel: showResult("Podsumuj", "standard", text)
    Result Dart wywołuje ChatApiService z promptem → renderuje Markdown

9. Nowe zaznaczenie tekstu:
    → Zamknij result panel (jeśli otwarty)
    → Przesuń toolbar do nowej pozycji
    → Wyślij nowy tekst do toolbar Dart
```

### 4.5 Pozycjonowanie paneli

**WAŻNE:** Używać `NSScreen.main?.visibleFrame` (bez Dock i menu bar) zamiast `screen.frame` (cały ekran). Inaczej panele mogą pojawić się pod Dock lub menu bar.

```swift
// Swift — poprawne pozycjonowanie
guard let screen = NSScreen.main else { return }
let vf = screen.visibleFrame  // wyklucza Dock + menu bar

// macOS: Y=0 to dół ekranu, Y rośnie w górę
let panelX = max(vf.minX, min(mouseX + 12, vf.maxX - panelWidth))
let panelY = max(vf.minY, min(mouseY + 8, vf.maxY - panelHeight))

// Jeśli toolbar wyszedłby powyżej visibleFrame → umieść PONIŻEJ kursora
if mouseY + 8 + panelHeight > vf.maxY {
    panelY = mouseY - panelHeight - 8
}
```

```
Result panel: obok toolbara, z offsetem w dół (macOS Y: poniżej = mniejszy Y)
  panel.x = toolbarX
  panel.y = toolbarY - resultHeight - 8
  // jeśli wychodzi poniżej visibleFrame.minY: odbij powyżej toolbara

Multi-monitor: Użyć screen na której jest kursor (NSScreen.screens.first(where: frame.contains(mouseLocation))),
  nie NSScreen.main (main = screen z kluczową fokusową aplikacją, nie zawsze z kursorem).
  backingScaleFactor per screen dla poprawnego DPI.
```

### 4.6 Dismiss logic

**Toolbar znika gdy:**
1. Użytkownik kliknie poza toolbarem I poza result panelem (NSEvent globalMonitor `.leftMouseDown` — sprawdza `NSPointInRect` dla obu paneli)
2. Upłynie `dismissDelay` ms bez interakcji (domyślnie 4000ms, timer w Swift) — **timer wstrzymany gdy result panel jest widoczny**
3. Nowy event zaznaczenia → toolbar się przesuwa (nie znika, ale result się zamyka)
4. `sa_enabled` zmieniony na `false` → natychmiastowe zamknięcie obu paneli

**Toolbar NIE znika gdy:**
- Użytkownik kliknie akcję — toolbar pozostaje widoczny
- Użytkownik kliknie wewnątrz result panelu

**Result panel znika gdy:**
1. Nowa akcja z toolbara — zamknij stary result, otwórz nowy
2. Kliknięcie poza oboma panelami
3. Escape lub przycisk ✕ w widgecie
4. Toolbar zostanie zamknięty — result też się zamyka
5. Nowe zaznaczenie tekstu — result się zamyka, toolbar się przesuwa

### 4.7 Wywołanie LLM dla presetów

MVP: wywołanie przez `ChatApiService` (w pełni statyczny — żadna metoda nie wymaga instancji, `BuildContext`, ani providerów). `OverlaySettingsProvider` czyta `ProviderConfig` z SharedPreferences klucz `provider_configs_v1`.

**⚠️ Shared static state:** `ChatApiService` ma mutowalny `_activeCancelTokens: Map<String, CancelToken>` oraz korzysta z singletona `ApiKeyManager` (round-robin index). Na macOS Flutter uruchamia wszystkie engine'y **w tym samym procesie i izolalcie Dart** — więc main engine i result engine **współdzielą te same static fields**. Konsekwencje:
- `requestId` musi być globalnie unikalny (np. prefiks `sa_` dla overlay) aby `cancelRequest()` z jednego engine'a nie anulował requestu drugiego.
- `ApiKeyManager` round-robin jest współdzielony — akceptowalne, a nawet pożądane (sprawiedliwy rozkład kluczy).

**Obsługa błędów w result panel (WYMAGANE w MVP):**
- Brak skonfigurowanego providera LLM → komunikat: „Skonfiguruj providera LLM w ustawieniach Kelivo" (zlokalizowany przez ARB)
- Timeout (30s domyślnie) → komunikat z opcją retry
- Brak internetu / błąd sieciowy → komunikat z opisem błędu
- Invalid API key / rate limit → komunikat z kodem błędu
- Każdy error state: przycisk "Zamknij" + opcjonalnie "Spróbuj ponownie"

**Streaming:** W MVP brak pełnego streaming, ale **WYMAGANY jest loading indicator** — spinner lub pulsujący tekst "Przetwarzanie..." z możliwością anulowania. Bez tego użytkownik widzi pusty panel przez 5-15 sekund na dłuższych tekstach. Pełny streaming w post-MVP.

### 4.8 Tłumaczenie — ChatApiService z promptem (bez TranslationService)

`TranslationService` z `lib/features/home/services/translation_service.dart` wymaga `BuildContext` i `ChatService` — nie nadaje się do overlay. Zamiast tego result engine wywołuje `ChatApiService` bezpośrednio z promptem tłumaczenia:

```
Translate the following text to {targetLanguage}. Return only the translation, no explanations:

{sourceText}
```

Zmiana języka w selektorze → nowe wywołanie ChatApiService z nowym `targetLanguage`.

### 4.9 Dynamiczna wysokość result panelu

Result panel ma zmienną wysokość zależną od treści. Dart raportuje wysokość contentu do Swifta przez MethodChannel `reportHeight(height)`. Swift resizuje NSPanel frame. Max height: 500px — powyżej scroll wewnątrz widgeta.

### 4.10 Preset „Przetłumacz i przeczytaj"

To nie jest standardowy LLM preset — to orkiestracja dwóch kroków:
1. Wywołaj tłumaczenie (jak akcja "Tłumacz") → pokaż result panel
2. Po zakończeniu → automatycznie `TtsProvider.speak(translatedText)` w result engine

Cała sekwencja odbywa się w result engine (ma własny TtsProvider).

### 4.11 MarkdownWithCodeHighlight w overlay — ROZSTRZYGNIĘTE

`MarkdownWithCodeHighlight` ma **4 call site'y** `context.watch/read<SettingsProvider>()` rozłożone w 3 klasach (`MarkdownWithCodeHighlight.build`, `_CodeBlockWidgetState`, `_headingTextStyle`). Łącznie czyta **9 getterów**:

| Getter | Typ |
|--------|-----|
| `enableMathRendering` | `bool` |
| `enableDollarLatex` | `bool` |
| `codeFontFamily` | `String?` |
| `codeFontIsGoogle` | `bool` |
| `appFontFamily` | `String?` |
| `appFontIsGoogle` | `bool` |
| `mobileCodeBlockWrap` | `bool` |
| `autoCollapseCodeBlock` | `bool` |
| `autoCollapseCodeBlockLines` | `int` |

**Decyzja: Opcja B — wyekstrahować interfejs `MarkdownSettings`.**

```dart
abstract interface class MarkdownSettings {
  bool get enableMathRendering;
  bool get enableDollarLatex;
  String? get codeFontFamily;
  bool get codeFontIsGoogle;
  String? get appFontFamily;
  bool get appFontIsGoogle;
  bool get mobileCodeBlockWrap;
  bool get autoCollapseCodeBlock;
  int get autoCollapseCodeBlockLines;
}
```

- `SettingsProvider` implementuje `MarkdownSettings` (dodanie `implements MarkdownSettings` — zero zmian w getterach, już istnieją).
- `OverlaySettingsProvider` również implementuje `MarkdownSettings` — czyta 9 kluczy z SharedPreferences.
- `MarkdownWithCodeHighlight` zmienia `context.watch<SettingsProvider>()` → `context.watch<MarkdownSettings>()` (lub przyjmuje jako parametr).
- **Reaktywność:** Parent widget w overlay robi `context.watch<OverlaySettingsProvider>()` i przekazuje snapshot — w MVP nie ma runtime zmian ustawień w overlay, więc jednokrotny read wystarczy.
- **Impact na istniejący kod:** Minimalny — `SettingsProvider` zyskuje `implements MarkdownSettings`, reszta aplikacji bez zmian.

### 4.12 Limit długości zaznaczonego tekstu

`sa_maxTextLength` (UserDefaults, domyślnie 5000 znaków). SelectionWatcher w Swift sprawdza długość **przed** pokazaniem toolbara. Tekst dłuższy niż limit → toolbar się nie pojawia. W ustawieniach użytkownik może zmienić limit.

### 4.13 „Wyślij do czatu" — odtwarzanie zamkniętego okna — ROZSTRZYGNIĘTE

Na macOS zamknięcie okna (⌘W) ≠ zamknięcie aplikacji. Istniejący kod w `DesktopTrayController` już obsługuje ten scenariusz: `onWindowClose()` przechwytuje zamknięcie i wywołuje `windowManager.hide()` zamiast faktycznego `close()` (gdy `_minimizeToTrayOnClose = true`). Czyli okno NIE jest niszczone — jest tylko ukrywane.

**Strategia (bazuje na istniejącym `DesktopTrayController._showWindow()`):**

```swift
// Swift — "Wyślij do czatu"
// 1. Pokaż/przywróć główne okno (analogicznie do kliknięcia w tray icon)
NSApp.activate(ignoringOtherApps: true)
if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "FlutterWindow" }) {
    mainWindow.makeKeyAndOrderFront(nil)
}
// 2. Wyślij tekst przez MethodChannel do main engine
mainEngineMessenger.invoke("focusAndSetText", arguments: text)
```

**Edge case:** Jeśli `minimizeToTrayOnClose` jest wyłączony, ⌘W naprawdę zamyka okno (`windowManager.destroy()`). W tym przypadku okno nie istnieje i `windowManager.show()` może nie wystarczyć. **Mitygacja MVP:** Selection Assistant wymaga `minimizeToTrayOnClose = true` (tray musi być aktywny). Jeśli tray jest wyłączony, przycisk "Wyślij do czatu" pokazuje komunikat: "Włącz opcję 'Minimalizuj do tray przy zamknięciu' aby używać tej funkcji".

**Istniejący tray controller:** `DesktopTrayController` jest singletonem, `_showWindow()` już robi `windowManager.show()` + `windowManager.focus()`. Reuse tej logiki zamiast duplikowania.

---

## 5. Nowe pliki

### Swift (macOS)

```
macos/Runner/
  SelectionWatcher.swift         # AXObserver, debounce, odczyt tekstu i pozycji, filtrowanie
  ToolbarWindowManager.swift     # NSPanel toolbara, FlutterEngine, MethodChannel, dismiss logic
  ResultWindowManager.swift      # NSPanel wyników, FlutterEngine, MethodChannel, resize
```

### Dart / Flutter

```
lib/shared/interfaces/
  markdown_settings.dart                 # Interfejs MarkdownSettings (9 getterów) — używany przez MarkdownWithCodeHighlight

lib/desktop/selection_assistant/
  selection_assistant_presets.dart      # Hardcoded presety (MVP) — nazwy z ARB
  overlay_settings_provider.dart       # Lekki SettingsProvider dla overlay engine'ów, implements MarkdownSettings
  toolbar_overlay_app.dart             # Entry point + widget toolbara
  result_overlay_app.dart              # Entry point + widget wyników (standard + translation + loading + error)

lib/desktop/setting/
  selection_assistant_settings_pane.dart  # UI ustawień w desktop settings
```

### Zmiany w istniejących plikach (minimalne)

| Plik | Zmiana |
|------|--------|
| `macos/Runner/AppDelegate.swift` | Inicjalizacja `SelectionWatcher`, `ToolbarWindowManager`, `ResultWindowManager`, routing MethodChannel między engine'ami, leniwe tworzenie/niszczenie engine'ów |
| `macos/Runner/Info.plist` | Dodanie `NSAccessibilityUsageDescription` |
| `lib/main.dart` | Dodanie entry points `toolbarOverlay()` i `resultOverlay()` |
| `lib/desktop/desktop_settings_page.dart` | Dodanie sekcji Selection Assistant |
| `lib/desktop/desktop_home_page.dart` | Nasłuchiwanie `focusAndSetText` z MethodChannel → `ChatActionBus` |
| `lib/desktop/hotkeys/chat_action_bus.dart` | Nowy variant `ChatAction.focusInputWithText(String)` (do istniejących 7 wartości enum) |
| `lib/shared/widgets/markdown_with_highlight.dart` | Zmiana 4 call site'ów: `SettingsProvider` → `MarkdownSettings` |
| `lib/core/providers/settings_provider.dart` | Dodanie `implements MarkdownSettings` |
| `lib/desktop/desktop_tray_controller.dart` | Nowa pozycja menu: toggle "Selection Assistant", sync z `sa_enabled` |
| `lib/l10n/app_en.arb` + `app_zh.arb` + `app_zh_Hans.arb` + `app_zh_Hant.arb` | Klucze SA: presety, komunikaty błędów, UI ustawień, onboarding, tray menu |

---

## 6. Ustawienia

MVP: **bez Hive** — ustawienia w `UserDefaults` (macOS) / `SharedPreferences` (Dart), ponieważ muszą być czytelne zarówno po stronie Swift jak i Dart.

**WAŻNE:** SharedPreferences na macOS zapisuje klucze z prefixem `flutter.`. Swift musi czytać klucze z tym prefixem:

```
// Dart: prefs.setBool('sa_enabled', true)
// Swift: UserDefaults.standard.bool(forKey: "flutter.sa_enabled")
```

```
SelectionAssistantSettings (UserDefaults / SharedPreferences):
  sa_enabled: bool                    // główny toggle (domyślnie false)
  sa_showTtsButton: bool              // domyślnie true
  sa_showTranslateButton: bool        // domyślnie true
  sa_showChatButton: bool             // domyślnie true
  sa_showPresets: bool                // domyślnie true
  sa_dismissDelay: int                // ms, domyślnie 4000
  sa_translateTargetLanguage: String  // domyślnie "pl"
  sa_maxTextLength: int               // domyślnie 5000 znaków
```

Swift czyta `flutter.sa_enabled`, `flutter.sa_dismissDelay`, `flutter.sa_maxTextLength` bezpośrednio z `UserDefaults` — nie potrzebuje Dart round-trip.

Zmiana `sa_enabled` na `false` w main Dart → zapis do SharedPreferences → Swift obserwuje `UserDefaults.didChangeNotification` → natychmiastowe zamknięcie paneli i niszczenie engine'ów.

> **Post-MVP:** migracja do HiveObject z `customActions: List<CustomAction>` jeśli ustawienia staną się bardziej złożone (custom akcje, wybór asystenta per-akcja). HiveType ID = **2** (0 i 1 zajęte przez ChatMessage i Conversation).

---

## 7. Onboarding uprawnień Accessibility

Pierwsze uruchomienie z włączonym Selection Assistant:

1. Kelivo sprawdza `AXIsProcessTrusted()` → false
2. **Jeśli główne okno jest ukryte (tryb tray-only):** najpierw `NSApp.activate(ignoringOtherApps: true)` + `window.makeKeyAndOrderFront(nil)` aby użytkownik widział dialog
3. Wyświetla dialog: "Selection Assistant potrzebuje dostępu do Accessibility aby wykrywać zaznaczony tekst. Żadne dane nie są wysyłane bez twojej akcji."
4. Przycisk "Otwórz ustawienia systemowe" → `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
5. Po przyznaniu uprawnień: watcher startuje automatycznie (polluje `AXIsProcessTrusted()` co 2s przez max 60s)

---

## 8. Plan implementacji krok po kroku

### Krok 1 — SelectionWatcher.swift + Toolbar NSPanel (od razu działający)

**Cel:** Na koniec tego kroku użytkownik zaznacza tekst w dowolnej aplikacji i widzi toolbar przy kursorze. To jest sedno całej funkcji — bez tego nic nie ma sensu.

**Ten krok łączy SelectionWatcher + ToolbarWindowManager + minimalny ToolbarOverlayApp w jednym przebiegu:**

**1a. SelectionWatcher.swift:**

- `AXObserver` rejestruje callback na `kAXSelectedTextChangedNotification`
- Przy `NSWorkspace.didActivateApplicationNotification` — przełącza obserwowany proces
- Debounce 300ms przez `DispatchWorkItem`
- **Edge case debounce:** Jeśli app się przełączy w trakcie debounce (300ms) — anuluj pending debounce, nie wykonuj odczytu dla poprzedniej app
- Odczyt tekstu: `AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute)`
- Odczyt pozycji: `NSEvent.mouseLocation`
- Sprawdza `UserDefaults` → `flutter.sa_enabled`, filtruje tekst < 3 znaków, > `flutter.sa_maxTextLength`, czysty whitespace
- Wywołuje `ToolbarWindowManager.show(text, x, y)`
- **Graceful degradation:** Jeśli `AXUIElementCopyAttributeValue` zwraca błąd (np. sandboxed app, Secure Input, Electron z niestandardową hierarchią AX) → cichy fail, nie pokazuj toolbara. Nie loguj do konsoli w release (spam). Opcjonalny debug log w development.

**1b. ToolbarWindowManager.swift + ToolbarOverlayApp (w tym samym kroku):**

- Tworzy NSPanel z `FlutterViewController` (engine: `toolbarOverlay`)
- **`GeneratedPluginRegistrant.register(with: toolbarEngine)`** ← obowiązkowe
- Engine tworzony leniwie (przy pierwszym `sa_enabled = true`), niszczony przy wyłączeniu
- MethodChannel `app.selectionAssistant/toolbar` — wysyła `setText(text)` do Dart
- Smart positioning przy kursorze (`visibleFrame`, screen pod kursorem)
- globalMonitor dla dismiss: `NSPointInRect`, timer z `UserDefaults.flutter.sa_dismissDelay`
- Entry point `toolbarOverlay()` w `main.dart`
- Widget `ToolbarOverlayApp`: frosted glass, `IosIconButton`y
- Kliknięcie → `onAction(action, text)` przez MethodChannel → Swift routuje

**1c. Weryfikacja wbudowana (nie osobna faza):**

Na koniec kroku 1 weryfikujemy te krytyczne aspekty multi-engine — ale jako naturalną część pracy, nie jako gate:
- [ ] `GeneratedPluginRegistrant.register(with: toolbarEngine)` — pluginy działają
- [ ] `SharedPreferences` read w toolbar engine — odczytuje dane
- [ ] MethodChannel roundtrip Swift↔Dart — toolbar dostaje tekst
- [ ] NSPanel pojawia się przy zaznaczeniu, nie kradnie focusu
- [ ] Pamięć: zmierzyć RSS przed/po (baseline do dokumentacji)

**Jeśli multi-engine nie zadziała** — nie zatrzymujemy się, tylko pivotujemy w ramach tego samego kroku:
- Fallback A: toolbar jako **native macOS NSView** (SwiftUI/AppKit) bez FlutterEngine — przyciski natywne, akcje przez MethodChannel do main engine
- Fallback B: `desktop_multi_window` plugin
- Decyzja natychmiastowa, nie osobny "research sprint"

### Krok 2 — ResultWindowManager.swift + ResultOverlayApp

- Tworzy NSPanel z `FlutterViewController` (engine: `resultOverlay`)
- **`GeneratedPluginRegistrant.register(with: resultEngine)`** ← obowiązkowe
- Engine tworzony leniwie, niszczony przy wyłączeniu SA
- MethodChannel `app.selectionAssistant/result`
- Odbiera `showResult(title, type, sourceText, targetLang?)` → przekazuje do Dart
- Dart raportuje `reportHeight(h)` → Swift resizuje panel (max 500px)
- Entry point `resultOverlay()` w `main.dart`
- Widget `ResultOverlayApp`:
  - Wariant `standard`: tytuł + `MarkdownBody` + copy button + TTS button
  - Wariant `translation`: selektor języka + treść + copy button + TTS button
  - Własny `OverlaySettingsProvider` + `TtsProvider`
  - `ChatApiService` (statyczny) do wywołań LLM
  - Loading indicator z opcją anulowania (obowiązkowy)
  - Obsługa błędów: brak providera, timeout, sieć, invalid key → zlokalizowane komunikaty + retry

### Krok 3 — OverlaySettingsProvider + interfejs MarkdownSettings

**3a. Interfejs `MarkdownSettings`** (nowy plik: `lib/shared/interfaces/markdown_settings.dart`):
- Wyekstrahować 9 getterów z `SettingsProvider` (patrz §4.11)
- `SettingsProvider` dodaje `implements MarkdownSettings` — zero zmian w istniejących getterach
- `MarkdownWithCodeHighlight` zmienia 4 call site'y: `context.watch<SettingsProvider>()` → `context.watch<MarkdownSettings>()`
- Zweryfikować że reszta aplikacji nie łamie się po zmianie (compile check + `flutter analyze`)

**3b. `OverlaySettingsProvider`** (nowy plik: `lib/desktop/selection_assistant/overlay_settings_provider.dart`):
- Implementuje `MarkdownSettings`
- Czyta ~11 kluczy z SharedPreferences (9 dla Markdown + `provider_configs_v1` + `selected_model_v1` + `assistants_v1` + `current_assistant_id_v1` + `sa_translateTargetLanguage` + `theme_mode_v1`)
- Udostępnia `ProviderConfig` i `Assistant` dla ChatApiService
- Czytany jednorazowo przy starcie engine'a (MVP: brak runtime refresh)

### Krok 4 — Akcje (routing w Swift)

- **Tłumacz:** Swift → ResultWindowManager.show → result MethodChannel `showResult("translation", text, targetLang)` → ChatApiService z promptem tłumaczenia
- **TTS:** toolbar Dart → `TtsProvider.speak(text)` bezpośrednio (toolbar engine ma własny TtsProvider)
- **Wyślij do czatu:** Swift → `NSApp.activate` + odtwarza/focusuje główne okno → main MethodChannel `focusAndSetText(text)` → `ChatActionBus.fire(ChatAction.focusInputWithText(text))`
- **Preset:** Swift → ResultWindowManager.show → result MethodChannel `showResult("standard", text)` → ChatApiService z promptem
- **Przetłumacz i przeczytaj:** result engine: ChatApiService translate → po zakończeniu → `TtsProvider.speak(result)` sekwencyjnie

### Krok 5 — Ustawienia (UserDefaults / SharedPreferences)

- Pane w desktop settings (`selection_assistant_settings_pane.dart`): toggle + checkboxy przycisków + wybór języka tłumaczenia + limit tekstu
- Zapis do SharedPreferences → automatycznie w `UserDefaults` z prefixem `flutter.`
- Swift obserwuje `UserDefaults.didChangeNotification` → reaguje na zmianę `flutter.sa_enabled` (tworzy/niszczy engine'y, start/stop AXObserver)

### Krok 6 — Onboarding Accessibility

- W desktop settings: toggle „Selection Assistant" → sprawdza `AXIsProcessTrusted()`
- Jeśli brak uprawnień: dialog z wyjaśnieniem + przycisk do System Preferences
- Jeśli okno ukryte: najpierw `NSApp.activate` + show window
- Polling `AXIsProcessTrusted()` co 2s / max 60s → auto-start watcher

### Krok 7 — Integracja z DesktopHomePage + Tray

- Nowy MethodChannel `app.selectionAssistant/main` w `DesktopHomePage`
- Handler `focusAndSetText(text)` → `ChatActionBus.fire(ChatAction.focusInputWithText(text))`
- Nowy `ChatAction` variant: `focusInputWithText(String text)` (dodać do istniejącego enum z 7 wartościami: `newTopic`, `toggleLeftPanelAssistants`, `toggleLeftPanelTopics`, `focusInput`, `switchModel`, `enterGlobalSearch`, `exitGlobalSearch`)
- `HomePageController` lub widget input nasłuchuje i wkleja tekst do pola wiadomości
- **Integracja z tray:** `DesktopTrayController` jest singletonem z 2 pozycjami menu (Show Window, Exit). Dodać trzecią pozycję: toggle "Selection Assistant" (on/off) — zsynchronizowany z `sa_enabled`. Ikona w tray opcjonalnie zmienia się gdy SA jest aktywny (np. inna tint). Nie wymaga nowego controllera — rozszerzenie istniejącego `syncFromSettings()`.

### Krok 7.5 — Crash recovery dla overlay engine'ów

- **Problem:** Jeśli secondary FlutterEngine crashuje (np. uncaught exception w Dart), NSPanel staje się zombie — widoczny ale niereaktywny.
- **Mitygacja:** Swift monitoruje `engine.isolateId` lub MethodChannel heartbeat (co 5s). Jeśli brak odpowiedzi przez 15s → niszcz engine + panel, loguj error, ustaw `sa_enabled = false` z komunikatem w main engine: "Selection Assistant został wyłączony z powodu błędu. Włącz ponownie w ustawieniach."
- **Prostsze MVP fallback:** `try-catch` wokół krytycznych operacji w overlay Dart (ChatApiService call, TTS). Uncaught → `FlutterError.onError` loguje + wysyła `dismiss()` przez MethodChannel do Swift.

### Krok 8 — Weryfikacja

```bash
flutter build macos
flutter run -d macos

# === Testy manualne — Happy path ===
# 1. Zaznacz tekst w TextEdit → toolbar pojawia się
# 2. Kliknij preset → result panel obok toolbara, toolbar widoczny
# 3. Kliknij inny preset → stary result zamyka się, nowy otwiera
# 4. Kliknij TTS w toolbar → audio bez okna
# 5. Kliknij TTS w result panel → odczytuje treść wyniku
# 6. Kliknij "Wyślij do czatu" → główne okno focusuje + tekst w polu
# 7. Zaznacz nowy tekst → result zamyka się, toolbar przesuwa
# 8. Kliknij poza oboma panelami → oba znikają
# 9. Wyłącz SA w ustawieniach → oba panele natychmiast znikają
# 10. Tekst > 5000 znaków → toolbar nie pojawia się
# 11. Przetłumacz i przeczytaj → result z tłumaczeniem + automatyczny TTS

# === Testy manualne — Error handling ===
# 12. Brak skonfigurowanego providera LLM → result panel z komunikatem błędu (zlokalizowanym)
# 13. Wyłącz internet → kliknij preset → result panel z komunikatem o braku sieci + retry
# 14. Loading indicator widoczny podczas przetwarzania (nie pusty panel)
# 15. Anuluj przetwarzanie (przycisk cancel w loading state)

# === Testy manualne — Edge cases ===
# 16. Zaznacz tekst w polu hasła (Secure Input) → toolbar NIE pojawia się
# 17. Tray toggle: włącz/wyłącz SA z menu tray → synchronizacja z ustawieniami
# 18. Zaznacz tekst przy krawędzi ekranu → panel nie wychodzi poza visibleFrame
# 19. Multi-monitor: zaznacz tekst na drugim ekranie → panel na właściwym ekranie
# 20. Wyłącz tray → kliknij "Wyślij do czatu" → komunikat o wymaganiu tray
# 21. App switch w trakcie debounce (szybkie przełączanie) → brak ghost toolbara
# 22. Engine tworzony → niszczony (sa_enabled toggle) → tworzony ponownie → działa

flutter analyze
flutter test
```

---

## 9. Ryzyka

| Ryzyko | Ocena | Mitygacja | Status |
|--------|-------|-----------|--------|
| **GeneratedPluginRegistrant na secondary engine** — pluginy mogą mieć zależności od main window | **WYSOKIE** | flutter_tts używa NSSpeechSynthesizer (niezależny od window). Weryfikowane w Kroku 1 razem z budową toolbara. Jeśli nie działa → natychmiastowy pivot na native toolbar (SwiftUI/AppKit). | ⏳ Weryfikacja w Kroku 1 |
| **ChatApiService shared static state** — `_activeCancelTokens` współdzielony między engine'ami | Średnie | Prefiks `sa_` w `requestId` dla overlay. `ApiKeyManager` round-robin współdzielony — akceptowalne. | ✅ Rozstrzygnięte |
| **Brak streaming w MVP** — pusty panel przez 5-15s | Średnie | Loading indicator + anulowanie obowiązkowe w MVP. Pełny streaming w post-MVP. | ✅ Rozstrzygnięte |
| Aplikacje w Secure Input mode (pola haseł) blokują AX | Niskie | AX zwraca pusty tekst — graceful fail, nie pokazuj toolbara | ✅ OK |
| Dwa dodatkowe FlutterEngine — ~60-100 MB pamięci | Niskie | Leniwe tworzenie. **Zmierzyć RSS w Kroku 1.** Niszczone przy sa_enabled=false | ⏳ Pomiar w Kroku 1 |
| Pozycja panelu na multi-monitor z różnymi DPI | Średnie | Używać `NSScreen` na której jest kursor (nie `NSScreen.main`). `visibleFrame` zamiast `frame`. `backingScaleFactor` per screen. | ✅ Rozstrzygnięte |
| LLM call — brak providera / timeout / sieć / invalid key | Średnie | Pełna obsługa błędów w result panel: komunikat + retry + zamknij. Zlokalizowane komunikaty. | ✅ Rozstrzygnięte |
| AXObserver nie przełączy się na nową app szybko | Niskie | `NSWorkspace.didActivateApplicationNotification` jest natychmiastowy. Debounce anulowany przy app switch. | ✅ OK |
| Zmiana ustawień w main → overlay engine nieświadomy | Niskie | MVP: akceptowalne (engine'y czytają przy starcie). Post-MVP: `UserDefaults.didChangeNotification` | ✅ OK |
| Dismiss globalMonitor — kliknięcie w result panel nie powinno zamykać toolbara | Średnie | `NSPointInRect` sprawdza obie ramki paneli | ✅ OK |
| **Odtworzenie głównego okna** po ⌘W dla "Wyślij do czatu" | Średnie | Istniejący `DesktopTrayController` ukrywa zamiast zamykać (gdy tray aktywny). SA wymaga tray aktywny. Bez tray → komunikat. | ✅ Rozstrzygnięte |
| MarkdownWithCodeHighlight — kompatybilność z OverlaySettingsProvider | Niskie | Interfejs `MarkdownSettings` (9 getterów). `SettingsProvider` i `OverlaySettingsProvider` implementują. | ✅ Rozstrzygnięte |
| **Electron/niestandardowe apps** — AX hierarchy niestandardowa | Niskie | Graceful fail. Niektóre Electron apps (VS Code, Slack) mogą nie eksponować `kAXSelectedTextAttribute` poprawnie. Cichy fail. | ✅ OK |
| **Overlay engine crash** — zombie NSPanel | Średnie | `FlutterError.onError` → dismiss MethodChannel. Heartbeat fallback w post-MVP. | ✅ Rozstrzygnięte |

---

## 10. Referencje

- [Apple AXObserver documentation](https://developer.apple.com/documentation/applicationservices/axobserver)
- `AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute, &value)`
- [PopClip](https://www.popclip.app/) — wzorzec UX na macOS
- [Cherry Studio Selection Assistant](https://github.com/CherryHQ/cherry-studio) — inspiracja funkcjonalna i wizualna
- [Flutter multiple engines (official docs)](https://docs.flutter.dev/add-to-app/multiple-flutters)
- [desktop_multi_window plugin](https://pub.dev/packages/desktop_multi_window) — referencyjna implementacja multi-window
- [NSPanel non-activating floating](https://levelup.gitconnected.com/swiftui-macos-floating-window-panel-4eef94a20647)

---

## 11. Zakres wersji

### MVP
- SelectionWatcher + toolbar panel (NSPanel + FlutterEngine, leniwe tworzenie) — **Krok 1 od razu dostarcza toolbar przy zaznaczeniu** (weryfikacja multi-engine wbudowana, fallback do native toolbar jeśli potrzebny)
- Result panel (NSPanel + FlutterEngine, leniwe tworzenie) — standard + translation
- Oba panele mogą być widoczne jednocześnie
- GeneratedPluginRegistrant na obu secondary engine'ach
- OverlaySettingsProvider (lekki, ~9 kluczy) + interfejs `MarkdownSettings`
- Hardcoded presety (Podsumuj, Wyjaśnij, Popraw gramatykę, Przetłumacz i przeczytaj) — **zlokalizowane przez ARB ×4**
- TTS w toolbar (bez okna) + TTS w result panel (odczytuje wynik)
- Tłumaczenie przez ChatApiService z promptem (bez TranslationService)
- **Loading indicator** z opcją anulowania w result panel (wymagany zamiast pustego panelu)
- **Obsługa błędów** w result panel (brak providera, timeout, sieć, invalid key) — zlokalizowane komunikaty
- "Wyślij do czatu" — focus/odtworzenie głównego okna + wklejenie tekstu do pola (wymaga aktywnego tray)
- **Tray toggle** — pozycja "Selection Assistant" w menu tray
- Ustawienia: toggle + wybór języka + limit tekstu (UserDefaults/SharedPreferences z prefixem `flutter.`)
- Onboarding Accessibility (z obsługą trybu tray-only)
- Dismiss logic: timer wstrzymany przy otwartym result, nowe zaznaczenie zamyka result
- Limit zaznaczonego tekstu (sa_maxTextLength, domyślnie 5000)
- **Crash recovery** — `FlutterError.onError` → dismiss, nie zombie panel
- `requestId` z prefixem `sa_` dla overlay (unikanie kolizji z main engine w shared `_activeCancelTokens`)

### Post-MVP
- Streaming odpowiedzi w result panel
- Edytowalne custom akcje (do 10) z osobną zakładką w settings
- Wybór asystenta per-akcja
- Migracja ustawień do HiveObject (TypeId = 2) jeśli złożoność rośnie
- Historia wyników
- Propagacja zmian ustawień do overlay engines w runtime (UserDefaults.didChangeNotification → MethodChannel do Dart)

---

## 12. Szacunkowy nakład pracy (MVP)

| Krok | Szacunek | Uwagi |
|------|---------|-------|
| Krok 1: SelectionWatcher + ToolbarWindowManager + ToolbarOverlayApp | 2–3 dni | Najważniejszy krok — od razu toolbar przy zaznaczeniu. Weryfikacja multi-engine wbudowana. |
| Krok 2: ResultWindowManager + ResultOverlayApp (+ loading + error) | 2–3 dni | Includes loading indicator i obsługa błędów |
| Krok 3: OverlaySettingsProvider + interfejs `MarkdownSettings` | 1–1.5 dnia | Refaktor `MarkdownWithCodeHighlight` (4 call site'y) |
| Krok 4: Routing akcji w Swift (toolbar→result, toolbar→main, dismiss) | 1 dzień | |
| Krok 5: Ustawienia + UserDefaults obserwacja | 0.5–1 dzień | |
| Krok 6: Onboarding Accessibility | 0.5 dnia | |
| Krok 7: Integracja DesktopHomePage + ChatActionBus + tray | 1–1.5 dnia | Rozszerzone o tray toggle |
| Lokalizacja (ARB ×4: nazwy presetów, komunikaty błędów, UI) | 0.5–1 dzień | |
| Krok 8: Testy manualne + poprawki (22 scenariusze) | 2–3 dni | Rozszerzone o error + edge case scenarios |
| **Łącznie** | **11–16 dni roboczych** | |
