# Briefing: Proxies mit Robotmk, RCC und Browser Library

14.10.2026 · Simon Meggle

Ein RCC-Proxyprofil leitet Python-Traffic über den Proxy, den Browser der Browser Library aber nicht: Der braucht `proxy=` in `New Browser`. Dieses Briefing fasst die Messungen aus dem Projekt rf-web-proxytest für einen Blogartikel an Robotmk-Anwender zusammen.

**Wichtig für den Artikel:** Alle Messungen laufen ausschließlich mit Browser Library 20.6.0. Versionen vor 20.4.0 hatten einen Fehler, durch den die interne gRPC-Kommunikation ohne `NO_PROXY=localhost` nicht funktionierte ([robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Der Artikel sollte das ausdrücklich sagen und mindestens 20.4.0 voraussetzen.

## Kernbotschaften

1. **Ein RCC-Profil setzt nur Umgebungsvariablen.** rcc schreibt `HTTP_PROXY`, `HTTPS_PROXY` und `NO_PROXY` (groß und klein) in den Robot-Prozess. Mit denselben Variablen ohne rcc ist das Verhalten identisch.
2. **Python folgt dem Profil, der Browser nicht.** urllib, requests und die RequestsLibrary nutzen die Variablen. Chromium in der Browser Library ignoriert sie.
3. **Den Browser-Proxy immer in `New Browser` setzen.** `proxy=` hat Vorrang vor allem anderen, mit Zugangsdaten in `username` und `password`.
4. **Ohne `proxy=` folgt Chromium dem Betriebssystem.** Unter Windows sind das die WinINET-Einstellungen des ausführenden Benutzers, bei Robotmk oft SYSTEM.
5. **Browser Library ab 20.4.0 verwenden.** Ältere Versionen scheiterten ohne `NO_PROXY=localhost` an ihrer internen gRPC-Verbindung ([#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Mit 20.6.0 läuft der Test auch ohne `NO_PROXY`; `no-proxy` im Profil bleibt trotzdem sinnvoll.
6. **`rcc task script` erbt die Umgebung des Aufrufers.** Ohne Profil entfernt rcc keine vorhandenen Proxy-Variablen, und `rcc ht vars` zeigt sie nicht an.
7. **Proxy-Auth über die URL funktioniert im Profil, nicht im Browser.** `http://user:pass@host:port` reicht rcc unverändert an Python durch; der Browser braucht die Felder `username` und `password`.

## Zielgruppe und Ton

Der Artikel richtet sich an Robotmk-Anwender, die E2E-Tests mit der Browser Library hinter einem Firmen-Proxy betreiben. Sie kennen RCC-Profile aus der Robotmk-Regel, wissen aber nicht, welche Teile des Tests das Profil tatsächlich betrifft.

Typische Annahmen, die der Artikel korrigiert:

- „Im RCC-Profil steht der Proxy, also geht der Browser darüber.“ Falsch: Chromium ignoriert die Variablen.
- „Ohne `NO_PROXY=localhost` geht die Browser Library kaputt.“ Nur vor 20.4.0; mit aktueller Version nicht mehr. Wer ältere Environments hat, sollte aktualisieren.
- „Ohne Profil ist kein Proxy aktiv.“ Nicht unbedingt: Variablen aus der Umgebung des Schedulers kommen trotzdem an.

Ton: sachlich, messbasiert, mit kopierbaren Snippets. Jede Aussage stützt sich auf ein Szenario aus dem Versuch.

## Wer liest welche Proxy-Einstellung

![Schichtenmodell: wer welche Proxy-Einstellung liest](schichtenmodell.png)

Das RCC-Profil wirkt nur über Umgebungsvariablen. Python folgt ihnen, Chromium nicht. Die interne gRPC-Verbindung der Browser Library ist seit 20.4.0 vom Proxy ausgenommen. Dieses Bild eignet sich als Leitgrafik für den Artikel.

## Versuchsaufbau

Zwei mitmproxy-Instanzen protokollieren jeden Request, auch HTTPS; so ist pro Szenario belegt, welcher Traffic welchen Weg nimmt.

| Komponente | Rolle |
| --- | --- |
| Proxy A, `localhost:3128` | wird per RCC-Profil bzw. `HTTP(S)_PROXY` gesetzt |
| Proxy B, `localhost:3129` | wird nur in `New Browser … proxy=` gesetzt |
| `proxy.robot` | loggt die Proxy-Variablen, schickt einen Python-Request (urllib), öffnet `http://example.com` und `https://example.org` im Browser |
| `run_scenarios.sh` (macOS/Linux) | Proxies in Docker; ohne Option setzt es die Variablen selbst, mit `--rcc` nutzt es RCC-Profil und `rcc task script` |
| `run_scenarios.ps1` (Windows) | Proxies als lokale mitmdump-Prozesse aus einem rcc-Environment, kein Docker |

Optionen beider Skripte: `--rcc`, `--auth` (Proxies verlangen Benutzer/Passwort) und `--fail` (zusätzlich Szenario 5, `NO_PROXY` fehlt). Alle Szenarien laufen mit Browser Library 20.6.0.

| # | Proxy A | `NO_PROXY` | `New Browser` |
| --- | --- | --- | --- |
| 1 | ja | gesetzt | ohne `proxy` |
| 2 | ja | gesetzt | Proxy B |
| 3 | nein | – | ohne `proxy` |
| 4 | nein | – | Proxy B |
| 5 | ja | fehlt | ohne `proxy` |

Im Docker-Container zeigt `127.0.0.1` auf den Container selbst, wie bei einem echten Proxy auf einem anderen Host. Unter Windows stellt ein mitmproxy-Addon dieses Verhalten nach (502 für Ziele auf localhost).

## Messergebnisse

Alle 20 Szenarien sind grün (Browser Library 20.6.0, macOS, kein Systemproxy): je fünf in den Läufen `env`, `rcc`, `env-auth` und `rcc-auth`. Mit rcc und mit selbst gesetzten Variablen sind die Ergebnisse identisch.

| # | Proxy A | `NO_PROXY` | `New Browser` | Python-Request | Browser-Traffic |
| --- | --- | --- | --- | --- | --- |
| 1 | ja | gesetzt | ohne `proxy` | Proxy A | direkt |
| 2 | ja | gesetzt | Proxy B | Proxy A | Proxy B |
| 3 | nein | – | ohne `proxy` | direkt | direkt |
| 4 | nein | – | Proxy B | direkt | Proxy B |
| 5 | ja | fehlt | ohne `proxy` | Proxy A | direkt, Test läuft |

Mit Authentifizierung nehmen alle Requests dieselben Wege. Python schickt die Zugangsdaten aus der URL sofort mit (0× 407), Chromium erhält einmal 407 und authentifiziert sich dann über `username`/`password`.

Log-Auszug Szenario 2, gut als Abbildung für den Artikel:

```text
Proxy A:  http://example.com/?via=python-urllib
Proxy B:  http://example.com/  http://example.com/s.js  https://example.org/  https://example.org/s.js
```

## Fallstricke

### `NO_PROXY` und die gRPC-Verbindung: behoben seit 20.4.0

Die Browser Library spricht per gRPC mit ihrem Node-Prozess auf `127.0.0.1:<port>`. grpc-python schickt auch lokale Verbindungen über `http_proxy`/`https_proxy`, wenn `no_proxy` sie nicht ausnimmt. Vor 20.4.0 scheiterte die Library deshalb ohne `NO_PROXY=localhost` mit `Could not connect to the playwright process` ([#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)).

Seit 20.4.0 ist das behoben; in 20.6.0 setzt `grpc_channel_options` (`Browser/playwright.py`) dafür `grpc.enable_http_proxy=0`. Szenario 5 (Proxy gesetzt, `NO_PROXY` fehlt) läuft mit 20.6.0 durch. Für den Artikel: mindestens 20.4.0 empfehlen und den alten Fehler nur als Hinweis für ältere Environments erwähnen.

### Geerbte Umgebung

`rcc task script` gibt die Umgebung des aufrufenden Prozesses an den Test weiter. Ohne RCC-Profil setzt rcc keine Proxy-Variablen, entfernt aber auch keine vorhandenen. `rcc ht vars` listet nur, was rcc selbst setzt, und zeigt geerbte Variablen deshalb nicht an. Im Versuch hat genau das einen Lauf verfälscht: Die Shell hatte noch `HTTP_PROXY` aus einer früheren Sitzung. Für Robotmk heißt das: Systemweite Variablen oder die des Scheduler-Dienstes wirken auch ohne Profil.

### Zugangsdaten an zwei Stellen

Im RCC-Profil und in den Variablen stehen sie in der URL: `http://proxyuser:s3cr3t@proxy:3128`. rcc reicht das unverändert durch. Der Browser braucht sie dagegen als `username` und `password` im `proxy`-Dictionary.

### Windows: der Systemproxy

Ohne `proxy=` nutzt Chromium unter Windows die WinINET-Einstellungen (Internetoptionen, PAC, WPAD) des Benutzers, unter dem der Test läuft. Läuft der Robotmk-Scheduler als SYSTEM, sind es dessen Einstellungen, nicht die des angemeldeten Admins. Auch Python-urllib liest unter Windows ohne Env-Variablen die Registry.

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

- [ ] `no-proxy` im RCC-Profil enthält mindestens `localhost,127.0.0.1`
- [ ] Jeder `New Browser` mit Proxy-Bedarf bekommt `proxy=` mit `server` und `bypass`
- [ ] Zugangsdaten für den Browser in `username`/`password`, nicht in der URL
- [ ] Browser Library mindestens 20.4.0 (getestet: 20.6.0)
- [ ] Proxy-Variablen in der Umgebung des Schedulers kennen (Dienst, System, Benutzer)
- [ ] Unter Windows WinINET-Proxy des Ausführungsbenutzers prüfen, bei SYSTEM besonders
- [ ] Im Test einmal die Proxy-Variablen loggen, wie `proxy.robot` es tut

## Vorschlag für den Artikel

Arbeitstitel zur Auswahl:

- „RCC-Proxyprofil gesetzt – und der Browser geht trotzdem direkt raus“
- „Proxies in Robotmk: Wer liest was?“
- „Drei Zeilen, die Ihre Browser-Tests hinter dem Proxy retten“

Gliederung (ca. 1.500–2.000 Wörter):

1. Einstieg mit dem typischen Fehlerbild: Profil gesetzt, Browser-Traffic taucht im Proxy-Log nicht auf.
2. Das Schichtenmodell (Diagramm oben): welche Komponente welche Einstellung liest.
3. Der Versuch in Kürze, mit Link auf das Repo und die Skripte.
4. Ergebnisse als Tabelle, Szenario 1 bis 4.
5. `NO_PROXY` und gRPC: früher ein Fallstrick, seit 20.4.0 behoben (Szenario 5, Issue #1037).
6. Authentifizierung: URL im Profil, Felder im Browser.
7. Windows und SYSTEM-Benutzer.
8. Checkliste und Snippets zum Kopieren.

Grafiken:

- Schichtenmodell als Diagramm (Vorlage im Abschnitt oben)
- Ausschnitt der mitmproxy-Logs aus Szenario 2: Python-Request in Proxy A, Browser-Traffic nur in Proxy B
- Ergebnis-Matrix der Szenarien

## Offene Punkte und Quellen

- [ ] `run_scenarios.ps1` auf einem Windows-Host ausführen; bisher nur auf macOS gemessen
- [ ] Windows mit gesetztem WinINET-Proxy und mit PAC-Datei prüfen (Szenario 1 und 3 sollten dann über den Systemproxy laufen)
- [ ] Robotmk-Scheduler als SYSTEM gegen einen angemeldeten Benutzer vergleichen
- [ ] Sonderzeichen im Proxy-Passwort (URL-Kodierung im RCC-Profil) testen
- [ ] Linux ohne Desktop: liest Chromium dort `http_proxy`?

Quellen (lokal im Projekt rf-web-proxytest):

- `README.md`, `run_scenarios.sh`, `run_scenarios.ps1`, `results/<env|rcc>[-auth]/summary.txt`
- Browser Library 20.6.0: `Browser/playwright.py`, Funktion `grpc_channel_options` (setzt `grpc.enable_http_proxy=0` für lokale Hosts)
- [robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037): gRPC ohne `NO_PROXY=localhost`, behoben in 20.4.0
- rcc v17.29.1: `rcc ht vars`, `rcc config import/switch`, `rcc task script`
