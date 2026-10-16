# Briefing: Proxies mit Robotmk, RCC und Browser Library

15.10.2026 · Simon Meggle

Ein RCC-Proxyprofil leitet Python-Traffic über den Proxy, den Browser der Browser Library aber nicht: Der braucht `proxy=` in `New Browser`. Dieses Briefing fasst die Messungen aus dem Projekt rf-web-proxytest für einen Blogartikel an Robotmk-Anwender zusammen. Grundlage sind 45 Testläufe auf macOS und Windows, alle grün.

**Wichtig für den Artikel:** Alle Messungen laufen ausschließlich mit Browser Library 20.6.0. Versionen vor 20.4.0 hatten einen Fehler, durch den die interne gRPC-Kommunikation ohne `NO_PROXY=localhost` nicht funktionierte ([robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Der Artikel sollte das ausdrücklich sagen und mindestens 20.4.0 voraussetzen.

## Kernbotschaften

1. **Ein RCC-Profil setzt nur Umgebungsvariablen.** rcc schreibt `HTTP_PROXY`, `HTTPS_PROXY` und `NO_PROXY` in den Robot-Prozess. Setzt man dieselben Variablen ohne Profil, ist das Ergebnis auf beiden Plattformen identisch.
2. **Python folgt dem Profil, der Browser nicht.** urllib, requests und die RequestsLibrary nutzen die Variablen. Chromium in der Browser Library ignoriert sie.
3. **Ohne `proxy=` ging der Browser in jeder Messung direkt ins Netz.** Das gilt auch unter Windows mit gesetztem Systemproxy (WinINET): Python und andere Programme nutzten ihn, der headless gestartete Chromium nicht.
4. **Den Browser-Proxy deshalb immer in `New Browser` setzen.** `proxy=` wirkte in allen Läufen, unabhängig von Profil, Variablen und Systemproxy. Zugangsdaten gehören in `username` und `password`.
5. **Browser Library ab 20.4.0 verwenden.** Ältere Versionen scheiterten ohne `NO_PROXY=localhost` an ihrer internen gRPC-Verbindung ([#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Mit 20.6.0 läuft der Test auch ohne `NO_PROXY`; `no-proxy` im Profil bleibt trotzdem sinnvoll.
6. **`rcc task script` erbt die Umgebung des Aufrufers, und `rcc ht vars` zeigt das nicht.** Ohne Profil entfernt rcc keine vorhandenen Proxy-Variablen; sie kommen im Test an, tauchen in `rcc ht vars` aber nicht auf.
7. **Proxy-Auth über die URL funktioniert im Profil, nicht im Browser.** `http://user:pass@host:port` reicht rcc unverändert an Python durch; der Browser braucht die Felder `username` und `password`.

## Zielgruppe und Ton

Der Artikel richtet sich an Robotmk-Anwender, die E2E-Tests mit der Browser Library hinter einem Firmen-Proxy betreiben. Sie kennen RCC-Profile aus der Robotmk-Regel, wissen aber nicht, welche Teile des Tests das Profil tatsächlich betrifft.

Typische Annahmen, die der Artikel korrigiert:

- „Im RCC-Profil steht der Proxy, also geht der Browser darüber.“ Falsch: Chromium ignoriert die Variablen.
- „Dann nimmt der Browser eben den Systemproxy von Windows.“ In unserer Messung nicht: Auch mit gesetztem WinINET-Proxy ging der headless Browser direkt.
- „Ohne `NO_PROXY=localhost` geht die Browser Library kaputt.“ Nur vor 20.4.0; mit aktueller Version nicht mehr. Wer ältere Environments hat, sollte aktualisieren.
- „Ohne Profil ist kein Proxy aktiv.“ Nicht unbedingt: Variablen aus der Umgebung des Schedulers kommen trotzdem an.

Ton: sachlich, messbasiert, mit kopierbaren Snippets. Jede Aussage stützt sich auf ein Szenario aus dem Versuch.

## Wer liest welche Proxy-Einstellung

![Schichtenmodell: wer welche Proxy-Einstellung liest](schichtenmodell.png)

Das RCC-Profil wirkt nur über Umgebungsvariablen. Python folgt ihnen und liest unter Windows ohne Variablen den Systemproxy aus der Registry. Chromium liest nur `proxy=` und geht sonst direkt, auch bei gesetztem Windows-Systemproxy. Die interne gRPC-Verbindung der Browser Library ist seit 20.4.0 vom Proxy ausgenommen. Dieses Bild eignet sich als Leitgrafik für den Artikel.

## Versuchsaufbau

Zwei mitmproxy-Instanzen protokollieren jeden Request, auch HTTPS. So ist pro Szenario belegt, welcher Traffic welchen Weg nimmt.

| Komponente | Rolle |
| --- | --- |
| Proxy A, `localhost:3128` | kommt aus dem RCC-Profil bzw. aus `HTTP(S)_PROXY`, im Lauf `sysproxy` zusätzlich aus WinINET |
| Proxy B, `localhost:3129` | wird nur in `New Browser … proxy=` gesetzt |
| `proxy.robot` | loggt die Proxy-Variablen, schickt einen Python-Request (urllib), öffnet `http://example.com` und `https://example.org` im Browser (Chromium, `headless=True`) |
| `run_scenarios.sh` (macOS) | Proxies in Docker |
| `run_scenarios.ps1` (Windows) | Proxies als lokale mitmdump-Prozesse aus einem rcc-Environment, kein Docker |

rcc baut in beiden Skripten das Environment, und robot läuft immer über `rcc task script`, wie unter Robotmk. Die Läufe unterscheiden sich darin, woher Proxy A kommt:

- `profile`: aus einem RCC-Proxyprofil, der Robotmk-Weg.
- `env`: ohne Profil aus `HTTP(S)_PROXY`/`NO_PROXY` in der Umgebung des Aufrufers, die `rcc task script` an den Test vererbt. Das ist die Gegenprobe: Liefern beide Läufe dasselbe, wirkt das Profil nur über diese Variablen.
- `-auth`: Beide Proxies verlangen Benutzer und Passwort.
- `windows-profile-sysproxy`: wie `profile`, zusätzlich zeigt der WinINET-Proxy des Benutzers (Internetoptionen) auf Proxy A.

| # | Proxy A (Profil/Variablen) | `NO_PROXY` | `New Browser` |
| --- | --- | --- | --- |
| 1 | ja | gesetzt | ohne `proxy` |
| 2 | ja | gesetzt | Proxy B |
| 3 | nein | – | ohne `proxy` |
| 4 | nein | – | Proxy B |
| 5 | ja | fehlt | ohne `proxy` |

Im Docker-Container zeigt `127.0.0.1` auf den Container selbst, wie bei einem echten Proxy auf einem anderen Host. Unter Windows stellt ein mitmproxy-Addon dieses Verhalten nach (502 für Ziele auf localhost).

Umgebungen: macOS mit Docker; Windows Server 2022 als Administrator. Beide mit rcc v17.29.1, Browser Library 20.6.0 (Playwright 1.63).

## Messergebnisse

Neun Läufe mit je fünf Szenarien, 45 von 45 grün:

| Plattform | Läufe |
| --- | --- |
| macOS, kein Systemproxy | `profile`, `env`, `profile-auth`, `env-auth` |
| Windows, kein Systemproxy (WinINET `ProxyEnable=0`, keine PAC-Datei, WinHTTP direkt) | `windows-profile`, `windows-env`, `windows-profile-auth`, `windows-env-auth` |
| Windows, WinINET-Proxy → Proxy A | `windows-profile-sysproxy` |

### Ohne Systemproxy: auf beiden Plattformen identisch

Alle acht Läufe ohne Systemproxy liefern dieselben Wege, egal ob Proxy A aus dem Profil oder aus geerbten Variablen kommt:

| # | Proxy A | `NO_PROXY` | `New Browser` | Python-Request | Browser-Traffic |
| --- | --- | --- | --- | --- | --- |
| 1 | ja | gesetzt | ohne `proxy` | Proxy A | direkt |
| 2 | ja | gesetzt | Proxy B | Proxy A | Proxy B |
| 3 | nein | – | ohne `proxy` | direkt | direkt |
| 4 | nein | – | Proxy B | direkt | Proxy B |
| 5 | ja | fehlt | ohne `proxy` | Proxy A | direkt, Test läuft |

Mit Authentifizierung nehmen alle Requests dieselben Wege. Python schickt die Zugangsdaten aus der URL sofort mit (0× 407 an Proxy A). Chromium erhält beim ersten Request an Proxy B einmal 407 und authentifiziert sich dann über `username`/`password`. Das gilt für macOS und Windows.

Log-Auszug Szenario 2, gut als Abbildung für den Artikel:

```text
Proxy A:  http://example.com/?via=python-urllib
Proxy B:  http://example.com/  http://example.com/s.js  https://example.org/  https://example.org/s.js
```

### Profil und geerbte Variablen: `rcc ht vars` als Beleg

Im Test kommen in beiden Modi dieselben Variablen an. `rcc ht vars`, mit derselben Umgebung aufgerufen, unterscheidet sich aber:

| Lauf | `HTTP(S)_PROXY` im Test | `rcc ht vars` zeigt Proxy-Variablen |
| --- | --- | --- |
| `profile` | `http://localhost:3128` | ja (`export HTTPS_PROXY=…` bzw. unter Windows `SET HTTPS_PROXY=…`) |
| `env` | `http://localhost:3128` | nein |

Wer mit `rcc ht vars` prüft, welcher Proxy im Test wirkt, sieht geerbte Variablen also nicht.

### Windows mit Systemproxy: Browser ignoriert ihn ebenfalls

Im Lauf `windows-profile-sysproxy` war der WinINET-Proxy des Benutzers aktiv (`ProxyEnable=1`, `ProxyServer=localhost:3128`, Ausnahme `<local>`):

| # | Proxy A (Profil) | `New Browser` | Python-Request | Browser-Traffic |
| --- | --- | --- | --- | --- |
| 1 | ja | ohne `proxy` | Proxy A | **direkt** |
| 2 | ja | Proxy B | Proxy A | Proxy B |
| 3 | nein | ohne `proxy` | **Proxy A** (aus der Registry) | **direkt** |
| 4 | nein | Proxy B | **Proxy A** (aus der Registry) | Proxy B |
| 5 | ja, ohne `NO_PROXY` | ohne `proxy` | Proxy A | **direkt** |

Der Systemproxy war nachweislich wirksam:

- In den Szenarien 3 und 4 gibt es weder Profil noch Variablen. Python-urllib ging trotzdem über Proxy A, weil es unter Windows ohne Env-Variablen die Registry liest.
- Im Log von Proxy A erscheinen zusätzlich Verbindungen anderer Programme des Benutzers, etwa VS Code zu `main.vscode-cdn.net`.

Chromium ging trotzdem in den Szenarien 1, 3 und 5 direkt. Playwright gibt Chromium ohne `proxy=` kein Proxy-Flag mit (geprüft im Playwright-Code der Browser Library 20.6.0). Warum der Browser den WinINET-Proxy dennoch nicht nutzt, ist nicht geklärt. Naheliegend ist, dass Playwright für `headless=True` die schlanke Chromium-Variante „headless shell“ startet; das ist nicht geprüft. Für den Artikel reicht die messbare Aussage: **Auf den Systemproxy ist kein Verlass, `proxy=` schon.**

## Fallstricke

### `NO_PROXY` und die gRPC-Verbindung: behoben seit 20.4.0

Die Browser Library spricht per gRPC mit ihrem Node-Prozess auf `127.0.0.1:<port>`. grpc-python schickt auch lokale Verbindungen über `http_proxy`/`https_proxy`, wenn `no_proxy` sie nicht ausnimmt. Vor 20.4.0 scheiterte die Library deshalb ohne `NO_PROXY=localhost` mit `Could not connect to the playwright process` ([#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)).

Seit 20.4.0 ist das behoben; in 20.6.0 setzt `grpc_channel_options` (`Browser/playwright.py`) dafür `grpc.enable_http_proxy=0`. Szenario 5 (Proxy gesetzt, `NO_PROXY` fehlt) läuft mit 20.6.0 in allen neun Läufen durch, auch mit Authentifizierung und Systemproxy. Für den Artikel: mindestens 20.4.0 empfehlen und den alten Fehler nur als Hinweis für ältere Environments erwähnen.

### Geerbte Umgebung

`rcc task script` gibt die Umgebung des aufrufenden Prozesses an den Test weiter. Ohne RCC-Profil setzt rcc keine Proxy-Variablen, entfernt aber auch keine vorhandenen. Die `env`-Läufe belegen das auf beiden Plattformen: Die Variablen des Aufrufers kommen im Test an, `rcc ht vars` zeigt sie nicht. Im Versuch hat genau das zu Beginn einen Lauf verfälscht: Die Shell hatte noch `HTTP_PROXY` aus einer früheren Sitzung. Für Robotmk heißt das: Systemweite Variablen oder die des Scheduler-Dienstes wirken auch ohne Profil.

### Zugangsdaten an zwei Stellen

Im RCC-Profil und in den Variablen stehen sie in der URL: `http://proxyuser:s3cr3t@proxy:3128`. rcc reicht das unverändert durch. Der Browser braucht sie dagegen als `username` und `password` im `proxy`-Dictionary.

### Windows: der Systemproxy hilft dem Browser nicht, aber Python

Unter Windows liest Python ohne Env-Variablen die WinINET-Einstellungen aus der Registry. Ein Systemproxy kann also Python-Traffic umleiten, auch wenn kein RCC-Profil aktiv ist (Szenarien 3 und 4 im Lauf `sysproxy`). Der Browser folgte ihm in der Messung nicht.

Für Robotmk relevant: WinINET-Einstellungen gelten pro Benutzer. Läuft der Scheduler als SYSTEM, gelten dessen Einstellungen, nicht die des angemeldeten Admins. Gemessen wurde als Administrator, nicht als SYSTEM.

## Empfehlungen und Snippets

Den Browser-Proxy ausdrücklich setzen, das RCC-Profil nur für Python-Traffic und Environment-Bau nutzen, `no-proxy` nie leer lassen.

RCC-Profil (so erzeugen es die Skripte, `rcc config import -f …` und `rcc config switch -p …`):

```yaml
name: proxytest-a-auth
settings:
  certificates:
    verify-ssl: false
  network:
    no-proxy: 'localhost,127.0.0.1'
    https-proxy: 'http://proxyuser:s3cr3t@localhost:3128'
    http-proxy: 'http://proxyuser:s3cr3t@localhost:3128'
```

Browser mit Proxy und Zugangsdaten:

```robotframework
*** Settings ***
Library    Browser
Library    Collections    # für Set To Dictionary

*** Keywords ***
Open Browser Behind Proxy
    &{proxy}=    Create Dictionary    server=http://proxy.example:3128    bypass=localhost,127.0.0.1
    IF    $PROXY_USER
        Set To Dictionary    ${proxy}    username=${PROXY_USER}    password=${PROXY_PASS}
    END
    New Browser    chromium    proxy=${proxy}
```

Checkliste für Robotmk-Anwender:

- [ ] Jeder `New Browser` mit Proxy-Bedarf bekommt `proxy=` mit `server` und `bypass`, auch wenn ein RCC-Profil oder ein Systemproxy gesetzt ist
- [ ] Zugangsdaten für den Browser in `username`/`password`, nicht in der URL
- [ ] `no-proxy` im RCC-Profil enthält mindestens `localhost,127.0.0.1`
- [ ] Browser Library mindestens 20.4.0 (getestet: 20.6.0)
- [ ] Proxy-Variablen in der Umgebung des Schedulers kennen (Dienst, System, Benutzer); `rcc ht vars` zeigt sie nicht
- [ ] Unter Windows den WinINET-Proxy des Ausführungsbenutzers kennen: Python folgt ihm ohne Env-Variablen
- [ ] Im Test einmal die Proxy-Variablen loggen, wie `proxy.robot` es tut

## Vorschlag für den Artikel

Arbeitstitel zur Auswahl:

- „RCC-Proxyprofil gesetzt – und der Browser geht trotzdem direkt raus“
- „Proxies in Robotmk: Wer liest was?“
- „Drei Zeilen, die Ihre Browser-Tests hinter dem Proxy retten“

Gliederung (ca. 1.500–2.000 Wörter):

1. Einstieg mit dem typischen Fehlerbild: Profil gesetzt, Browser-Traffic taucht im Proxy-Log nicht auf.
2. Das Schichtenmodell (Diagramm oben): welche Komponente welche Einstellung liest.
3. Der Versuch in Kürze: zwei Proxies, fünf Szenarien, macOS und Windows, mit Link auf das Repo.
4. Ergebnisse als Tabelle, Szenario 1 bis 4: Python über Proxy A, Browser direkt oder über `proxy=`.
5. Gegenprobe ohne Profil: gleiche Ergebnisse, also wirkt das Profil nur über Variablen; `rcc ht vars` zeigt geerbte Variablen nicht.
6. Windows-Systemproxy: Python folgt ihm, der Browser nicht.
7. `NO_PROXY` und gRPC: früher ein Fallstrick, seit 20.4.0 behoben (Szenario 5, Issue #1037).
8. Authentifizierung: URL im Profil, Felder im Browser.
9. Checkliste und Snippets zum Kopieren.

Grafiken:

- Schichtenmodell als Diagramm (Vorlage im Abschnitt oben)
- Ausschnitt der mitmproxy-Logs aus Szenario 2: Python-Request in Proxy A, Browser-Traffic nur in Proxy B
- Ergebnis-Matrix der Szenarien, ergänzt um die Spalte „mit Windows-Systemproxy“

## Offene Punkte und Quellen

- [x] `run_scenarios.ps1` auf einem Windows-Host ausführen (Windows Server 2022, alle Läufe vollständig)
- [x] Windows mit gesetztem WinINET-Proxy (Lauf `windows-profile-sysproxy`): Browser ignoriert ihn, Python folgt ihm
- [ ] Ursache klären, warum Chromium den WinINET-Proxy ignoriert: Systemproxy-Lauf mit `headless=False` bzw. `channel=chrome` wiederholen. Folgt der Browser dann dem Systemproxy, betrifft die Aussage nur headless
- [ ] Windows mit PAC-Datei statt festem Proxy
- [ ] Robotmk-Scheduler als SYSTEM gegen einen angemeldeten Benutzer vergleichen
- [ ] Sonderzeichen im Proxy-Passwort (URL-Kodierung im RCC-Profil) testen
- [ ] Linux ohne Desktop: liest Chromium dort `http_proxy`?

Quellen (lokal im Projekt rf-web-proxytest):

- `README.md`, `run_scenarios.sh`, `run_scenarios.ps1`
- `results/<profile|env>[-auth]/summary.txt` (macOS), `results/windows-<profile|env>[-auth][-sysproxy]/summary.txt` (Windows); pro Szenario zusätzlich `proxyA.log`, `proxyB.log`, `htvars.txt`, `caller_env.txt`
- Browser Library 20.6.0: `Browser/playwright.py`, Funktion `grpc_channel_options` (setzt `grpc.enable_http_proxy=0` für lokale Hosts); Playwright 1.63 `coreBundle.js`: `--proxy-server` nur, wenn `proxy` übergeben wird
- [robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037): gRPC ohne `NO_PROXY=localhost`, behoben in 20.4.0
- rcc v17.29.1: `rcc ht vars`, `rcc config import/switch`, `rcc task script`
