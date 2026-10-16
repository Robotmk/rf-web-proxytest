# Proxytest: RCC-Proxyprofil, Env-Variablen und Browser Library

Frage: Über welchen Proxy geht der Traffic eines Robot-Tests mit der Browser Library (Playwright),
wenn ein RCC-Proxyprofil bzw. `HTTP(S)_PROXY`/`NO_PROXY` gesetzt sind? Und was passiert, wenn
`NO_PROXY` fehlt oder der Proxy Benutzer/Passwort verlangt?

Getestet wird ausschließlich **Browser Library 20.6.0**. Ältere Versionen (vor 20.4.0) hatten einen Fehler,
durch den die interne gRPC-Kommunikation ohne `NO_PROXY=localhost` nicht mehr funktionierte
([robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)).

## Aufbau

| Komponente | Beschreibung |
|---|---|
| Proxy A | `mitmdump` auf `localhost:3128`, wird per RCC-Profil bzw. `HTTP(S)_PROXY` gesetzt |
| Proxy B | `mitmdump` auf `localhost:3129`, wird nur explizit in `New Browser … proxy=` gesetzt |
| `proxy.robot` | loggt die Proxy-Variablen, macht einen Python-Kontrollrequest (urllib) und öffnet `http://example.com` + `https://example.org` im Browser |
| `resources/browser_noproxy.resource` | `New Browser` ohne `proxy` |
| `resources/browser_proxyB.resource` | `New Browser` mit `proxy={"server": "http://localhost:3129", "bypass": "localhost,127.0.0.1"}`, bei `${PROXY_USER}` zusätzlich `username`/`password` |
| `robot.yaml` / `conda.yaml` | Browser Library 20.6.0 |
| `profiles/` | von den Skripten erzeugte RCC-Profile (`proxytest-a[-auth][-nonoproxy].yaml`) |
| `mitmproxy/` | rcc-Environment und Addon für die Proxies unter Windows (ohne Docker) |

mitmdump bricht TLS auf, damit auch HTTPS-Requests im Log erscheinen. Im Browser ist deshalb `ignoreHTTPSErrors=True` gesetzt.

## Ausführen

Beide Skripte setzen rcc voraus: rcc baut und aktiviert das Environment (Browser Library 20.6.0), und robot
läuft immer über `rcc task script`. Die Modi unterscheiden sich nur darin, **woher die Proxy-Variablen für
Proxy A kommen**:

| Modus | Proxy A kommt aus | Zweck |
|---|---|---|
| `profile` (Default) | RCC-Proxyprofil (`rcc config import`/`switch`) | der Robotmk-Weg |
| `env` | `HTTP(S)_PROXY`/`NO_PROXY` in der Umgebung des Aufrufers, kein RCC-Profil; `rcc task script` vererbt sie | Gegenprobe: Wirkt das Profil nur über diese Variablen? |

### macOS/Linux: `run_scenarios.sh` (Docker + rcc)

```bash
./run_scenarios.sh                          # Szenarien 1-4, Proxy A per RCC-Profil
./run_scenarios.sh --proxy-from env         # Proxy A per Variablen des Aufrufers, ohne Profil
./run_scenarios.sh --auth                   # Proxies mit Benutzer/Passwort
./run_scenarios.sh --fail                   # zusätzlich Szenario 5 (NO_PROXY fehlt)
./run_scenarios.sh --proxy-from env --auth --fail 5   # kombinierbar, Nummern wählen einzelne Szenarien
```

- **`profile`:** Das Skript erzeugt das passende Profil unter `profiles/`, importiert und aktiviert es. Am Ende
  wird das vorher aktive Profil wiederhergestellt.
- **`env`:** Kein Profil aktiv (`rcc config switch -n`). Das Skript setzt `HTTP_PROXY`, `HTTPS_PROXY`, `http_proxy`,
  `https_proxy` und ggf. `NO_PROXY`/`no_proxy` (dieselben Variablen, die rcc mit dem Profil setzt) für den
  rcc-Prozess.
- **`--auth`:** Beide Proxies verlangen `proxyuser:s3cr3t`. Proxy A bekommt die Zugangsdaten über die URL
  (`http://proxyuser:s3cr3t@localhost:3128`, im RCC-Profil bzw. in den Variablen), der Browser für Proxy B
  über `username`/`password` im `proxy`-Dictionary.
- Vor dem ersten Szenario baut bzw. prüft das Skript das Environment (`rcc ht vars` ohne Profil).
- Die Proxy-Variablen der aufrufenden Shell werden vorher entfernt (siehe Erkenntnis 5).
- Jeder robot-Lauf wird nach `TIMEOUT` Sekunden (Default 120) samt Kindprozessen beendet.

Ergebnisse: `results/<profile|env>[-auth]/scenarioN/` und `results/<profile|env>[-auth]/summary.txt`. Pro Szenario:
robot-Logs, Proxy-Logs, `caller_env.txt` (vom Skript gesetzte Variablen), `rcc_profile.txt` und `htvars.txt`
(`rcc ht vars` mit derselben Umgebung wie der Test).

### Windows: `run_scenarios.ps1` (rcc, ohne Docker)

```powershell
.\run_scenarios.ps1                            # Szenarien 1-4, Proxy A per RCC-Profil
.\run_scenarios.ps1 -ProxyFrom env -Auth
.\run_scenarios.ps1 -Fail 5
.\run_scenarios.ps1 -SystemProxy -Fail         # WinINET-Proxy des Benutzers zeigt auf Proxy A
```

- Optionen wie oben: `-ProxyFrom profile|env`, `-Auth`, `-Fail`, Szenarionummern, `-Timeout`.
- Die Proxies sind `mitmdump`-Prozesse aus einem eigenen rcc-Environment (`mitmproxy/robot.yaml`).
- Das Addon `mitmproxy/block_loopback.py` weist Ziele auf `127.0.0.1`/`localhost` mit 502 ab. So verhält sich der
  lokale Proxy wie ein Firmen-Proxy auf einem anderen Host (unter Docker ergibt sich das von selbst, weil
  `127.0.0.1` im Container der Container ist).
- **`-SystemProxy`:** setzt für die Dauer des Laufs den WinINET-Proxy des Benutzers (HKCU, Internetoptionen)
  auf `localhost:3128` mit Ausnahme `<local>` und stellt danach den vorherigen Zustand wieder her. Damit lässt
  sich messen, welchem Proxy Chromium ohne `proxy=` folgt. Nicht mit `-Auth` kombinierbar. Während des Laufs
  geht auch anderer WinINET-Traffic des Benutzers über Proxy A.
- Die Zusammenfassung enthält die Windows-Proxy-Einstellungen (WinINET des Benutzers und WinHTTP).
- Ergebnisse unter `results/windows-<profile|env>[-auth][-sysproxy]/`.

## Szenarien

Alle Szenarien mit Browser Library 20.6.0:

| # | Proxy A (Env/RCC) | `NO_PROXY` | `New Browser` | Erwartung |
|---|---|---|---|---|
| 1 | ja | `localhost,127.0.0.1` | ohne `proxy` | PASS |
| 2 | ja | `localhost,127.0.0.1` | Proxy B | PASS |
| 3 | nein | – | ohne `proxy` | PASS |
| 4 | nein | – | Proxy B | PASS |
| 5 (`--fail`) | ja | **fehlt** | ohne `proxy` | PASS (vor 20.4.0: FAIL) |

## Ergebnisse

Browser Library 20.6.0 (Playwright 1.63), rcc v17.29.1. Neun Läufe mit je fünf Szenarien (`--fail`), 45 von 45 PASS:

| Plattform | Läufe |
|---|---|
| macOS, kein System-Proxy | `profile`, `env`, `profile-auth`, `env-auth` |
| Windows Server 2022 (Administrator), kein System-Proxy | `windows-profile`, `windows-env`, `windows-profile-auth`, `windows-env-auth` |
| Windows Server 2022, WinINET-Proxy → Proxy A | `windows-profile-sysproxy` |

### Ohne System-Proxy (macOS und Windows identisch)

`profile` und `env` liefern identische Zusammenfassungen, ebenso `profile-auth` und `env-auth`, auf beiden Plattformen.

| # | Proxy A | `NO_PROXY` | `New Browser` | Env im Test | Python-Request | Browser-Traffic |
|---|---|---|---|---|---|---|
| 1 | ja | gesetzt | ohne `proxy` | `HTTP(S)_PROXY=…:3128` | **Proxy A** | **direkt** (weder A noch B) |
| 2 | ja | gesetzt | Proxy B | `HTTP(S)_PROXY=…:3128` | **Proxy A** | **Proxy B** |
| 3 | nein | – | ohne `proxy` | nicht gesetzt | direkt | **direkt** |
| 4 | nein | – | Proxy B | nicht gesetzt | direkt | **Proxy B** |
| 5 | ja | fehlt | ohne `proxy` | `HTTP(S)_PROXY=…:3128` | **Proxy A** | **direkt**, Test läuft |

Mit `--auth`: identische Wege. Python schickt die Zugangsdaten aus der Proxy-URL gleich mit (0× 407 an Proxy A),
Chromium bekommt beim ersten Request an Proxy B einmal 407 und authentifiziert sich dann mit `username`/`password`.

`htvars.txt` (`rcc ht vars` mit derselben Umgebung wie der Test) enthält die Proxy-Variablen nur in den
`profile`-Läufen, in den `env`-Läufen nicht, obwohl sie dort im Test ankommen (siehe Erkenntnis 5).

Die Logs zeigen z. B. für Szenario 2:

```text
Proxy A:  http://example.com/?via=python-urllib
Proxy B:  http://example.com/  http://example.com/s.js  https://example.org/  https://example.org/s.js
```

### Windows mit System-Proxy (`windows-profile-sysproxy`)

WinINET (HKCU): `ProxyEnable=1`, `ProxyServer=localhost:3128`, Ausnahme `<local>`.

| # | Proxy A (Profil) | `New Browser` | Python-Request | Browser-Traffic |
|---|---|---|---|---|
| 1 | ja | ohne `proxy` | Proxy A | **direkt** |
| 2 | ja | Proxy B | Proxy A | Proxy B |
| 3 | nein | ohne `proxy` | **Proxy A** (Registry) | **direkt** |
| 4 | nein | Proxy B | **Proxy A** (Registry) | Proxy B |
| 5 | ja, ohne `NO_PROXY` | ohne `proxy` | Proxy A | **direkt** |

Der System-Proxy war wirksam: Python ging in Szenario 3 und 4 ohne Profil und ohne Variablen über Proxy A, und im
Log von Proxy A erscheint auch Traffic anderer Programme des Benutzers (VS Code). Chromium (`headless=True`) ging
trotzdem direkt. Playwright setzt ohne `proxy=` kein Proxy-Flag; warum Chromium den WinINET-Proxy nicht nutzt,
ist nicht geklärt (Vermutung: headless shell, nicht geprüft).

## Erkenntnisse

1. **RCC setzt `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` (groß und klein) in die Umgebung des Robot-Prozesses.**
   Python (requests, urllib, RequestsLibrary …) nutzt den RCC-Proxy daher automatisch (Kontrollrequest in A).
   Das RCC-Profil wirkt ausschließlich über diese Variablen: Mit denselben Variablen ohne rcc ist das Verhalten
   identisch (`results/env` = `results/profile`).
2. **Der Browser ignoriert diese Variablen.** Playwright gibt Chromium nur dann `--proxy-server=…` mit,
   wenn `New Browser` einen `proxy` bekommt. Ohne `proxy` ging Chromium in allen Messungen direkt, unter
   Windows auch bei gesetztem WinINET-Proxy (gemessen mit `headless=True`).
3. **`proxy` in `New Browser` hat immer Vorrang**, egal was im RCC-Profil oder im System steht (Szenario 2 = Szenario 4).
   Zugangsdaten gehören dort in `username`/`password`.
4. Der RCC-Proxy wirkt beim Browser nur indirekt: beim **Bauen des Environments** (conda/pip-Downloads,
   `rfbrowser init` lädt Node-Pakete und Browser-Binaries über den Proxy).
5. **`rcc task script` vererbt die Umgebung des aufrufenden Prozesses.** Ohne Profil setzt RCC keine
   Proxy-Variablen, entfernt aber auch keine bereits vorhandenen. Sind `HTTP(S)_PROXY` in der Shell
   (bzw. beim Robotmk-Scheduler/Dienst oder systemweit) gesetzt, landen sie im Test, obwohl
   `rcc ht vars` nichts davon zeigt (es listet nur die von RCC selbst gesetzten Variablen).
6. **Fehlendes `NO_PROXY` bricht die Browser Library seit 20.4.0 nicht mehr.** Die Library spricht per gRPC
   mit ihrem eigenen Node-Prozess auf `127.0.0.1:<port>`. grpc-python schickt auch diese lokale Verbindung über
   `http_proxy`/`https_proxy`, sofern `no_proxy` sie nicht ausnimmt. Vor 20.4.0 endete das mit
   `Could not connect to the playwright process`
   ([#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Seit dem Fix in 20.4.0 nimmt die
   Library lokale gRPC-Kanäle vom Proxy aus; in 20.6.0 setzt `grpc_channel_options` (`Browser/playwright.py`)
   dafür `grpc.enable_http_proxy=0`. Szenario 5 läuft deshalb durch. `NO_PROXY=localhost,127.0.0.1` bleibt trotzdem sinnvoll, z. B. für
   Python-Requests an lokale Dienste und für ältere Environments.
7. **Proxy-Authentifizierung über die URL funktioniert in RCC-Profil und Env-Variablen**
   (`http://user:pass@host:port`); rcc reicht sie unverändert durch. Für den Browser gilt das nicht, er braucht
   `username`/`password` im `proxy`-Dictionary.

## Empfehlung für die Browser Library

Soll der Browser über einen Proxy gehen, ihn **immer explizit** setzen und sich nicht auf das RCC-Profil verlassen:

```robotframework
&{proxy}=    Create Dictionary    server=http://proxy.example:3128    bypass=localhost,127.0.0.1
...          username=${PROXY_USER}    password=${PROXY_PASS}
New Browser    chromium    proxy=${proxy}
```

Browser Library mindestens 20.4.0 verwenden (getestet: 20.6.0) und im RCC-Profil trotzdem `no-proxy` mit
mindestens `localhost,127.0.0.1` pflegen.

## Einschränkung / Plattformunterschiede

- Gemessen als normaler Benutzer bzw. Administrator, nicht als SYSTEM. WinINET-Einstellungen gelten pro Benutzer;
  läuft der Robotmk-Scheduler als SYSTEM, gelten dessen Einstellungen (für Python relevant, siehe oben).
- Der System-Proxy-Lauf nutzt `headless=True`. Ob ein sichtbarer Browser (`headless=False`) oder `channel=chrome`
  dem WinINET-Proxy folgt, ist nicht gemessen. PAC-Dateien ebenfalls nicht.
- **Linux** ohne Desktop-Umgebung: Chromium liest dort möglicherweise `http_proxy`/`https_proxy` aus der Umgebung.
  Nicht gemessen; ein weiterer Grund, `proxy` explizit zu setzen.
