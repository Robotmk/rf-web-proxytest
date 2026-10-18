# Am Proxy vorbei

Proxy-Probleme gehören zu den Fällen, bei denen ich innerlich kurz seufze. Nicht, weil sie schwer wären, sondern weil sie so schwer zu greifen sind. Seit heute weiß ich auch, warum.

Ich wollte das Verhalten von Browser Library und RequestsLibrary mal "kurz" in einem Test nachstellen. Herausgekommen ist ein nettes kleines Testprojekt mit zwei Proxies, die jeden Request mitschreiben, und eine interessante Erkenntnis.

<!--more-->

## Der Testaufbau

### Testcase

Zur Demonstration dient ein ganz einfacher Testcase, der zuerst per **REST-Aufruf** prüft, ob ein Backend antwortet, und dann eine Weboberfläche im **Browser** öffnet:

```robotframework
Python Request
    Scenario GET    http://example.com/?via=python-requests

Open HTTP And HTTPS Page
    Open Scenario Browser
    New Page    http://example.com
    Get Title    ==    Example Domain
    Go To    https://example.org
    Get Title    ==    Example Domain
```

`Scenario GET` und `Open Scenario Browser` stammen aus einer Resource-Datei, die je nach Szenario wechselt.  
In der einen rufen sie `GET` und `New Browser` ohne Proxy auf, in der anderen mit einem explizit angegebenen Proxy.  
Der Test selbst ist in allen Läufen identisch, nur die Proxy-Konfiguration variiert.

Wie sich die beiden oben genannten Libraries daran halten, wollte ich genau wissen.

### Proxies

Ich habe **zwei Instanzen** von [mitmproxy](https://www.mitmproxy.org) aufgesetzt, auf macOS als Docker-Container, unter Windows als lokale Prozesse.

- **Proxy A** ist vorgesehen für die Umgebungsvariablen des Betriebssystems.  
- **Proxy B** wird im Test selbst explizit angegeben: der RequestsLibrary per `proxies=` in `GET`, der Browser Library per `proxy=` in `New Browser`. So lässt sich sehen, ob der explizite Proxy die Variablen überstimmt.

### Proxy-Umgebungsvariablen

Ich wollte natürlich auch wissen, was passiert, wenn beim Aufruf von Robot Framework bereits Proxy-Umgebungsvariablen gesetzt sind.  

Derlei drei finden sich in allen Betriebssystemen, z. B. in der Shell oder in den Systemeinstellungen:

- `HTTP_PROXY` = Proxy-Server für HTTP-Ziele  
- `HTTPS_PROXY` = Proxy-Server für HTTPS-Ziele     
- `NO_PROXY` = braucht man, sobald ein Proxy gesetzt ist: Es nimmt Ziele aus, die nicht über den Proxy laufen sollen oder können, typischerweise `localhost,127.0.0.1` und interne Hosts. Ohne Proxy hat die Variable nichts zu tun.

> Viele Programme nutzen diese Variablen zur Proxy-Konfiguration. 
> Ein Standard ist das aber nicht: Jedes Programm entscheidet selbst, ob und wie es sie liest.

### Der Testablauf


Testen wollte ich fünf Kombinationen:

| #   | Proxy-Env-Variablen (A) | `NO_PROXY`                   | Proxy explizit im Test (B) | Frage dahinter                                       |
| --- | ----------------------- | ---------------------------- | -------------------------- | ---------------------------------------------------- |
| 1   | ☑️                      | `localhost,127.0.0.1`        | –                          | Folgen beide Libraries den Variablen?                |
| 2   | ☑️                      | `localhost,127.0.0.1`        | ☑️                         | Setzt sich der explizite Proxy gegen die Variablen durch? |
| 3   | –                       | – (ohne Proxy bedeutungslos) | –                          | Gegenprobe: Geht ohne Proxy alles direkt?            |
| 4   | –                       | – (ohne Proxy bedeutungslos) | ☑️                         | Wirkt der explizite Proxy auch ganz allein?          |
| 5   | ☑️                      | **bewusst nicht gesetzt**    | –                          | Was passiert, wenn `NO_PROXY` vergessen wird?        |

„Explizit im Test“ heißt: `proxies=` bei der RequestsLibrary und `proxy=` bei der Browser Library, immer beide zusammen.

Damit ich nicht alles von Hand ausführen muss, habe ich mir ein kleines Skript für macOS (Bash) und Windows (PowerShell) geschrieben.  

Für jedes Szenario 

- startet es beide Proxies mit leerem Log (auf macOS als Docker-Container, unter Windows als lokale `mitmdump`-Prozesse),
- setzt ggf. Proxy-Variablen im Environment (oder lässt sie weg),
- wählt die Resource-Datei mit oder ohne expliziten Proxy
- und führt den Test aus.

Danach sammelt es die Logs beider Proxies ein und hält in einer Zusammenfassung fest, welcher Request über welchen Proxy lief.

Jede Kombination lief auf macOS und auf Windows Server 2022, und zwar einmal ohne und einmal mit Proxy-Anmeldung. Am Weg der Requests hat die Anmeldung nichts geändert; wie man die Zugangsdaten angibt, habe ich deshalb am Ende als Referenz zusammengefasst.

Außerdem kamen die Proxy-Variablen einmal aus einem RCC-Profil und einmal direkt aus der Umgebung (dazu mehr im Abschnitt über Robotmk am Ende).

Unter Windows kam ein weiterer Lauf hinzu, bei dem zusätzlich der Systemproxy des Benutzers auf Proxy A zeigte.

Insgesamt waren das also **45 Testläufe**. Spannend war also nicht, *ob* der Test durchläuft, sondern *welchen Weg* er dabei nimmt.

## Die Ergebnisse

Vorweg die Übersicht, wohin die beiden Libraries ihre Requests geschickt haben:

| #   | Proxy-Env-Variablen (A) | Proxy explizit im Test (B) | RequestsLibrary | Browser Library |
| --- | ----------------------- | -------------------------- | --------------- | --------------- |
| 1   | ☑️                      | –                          | Proxy A         | **direkt**      |
| 2   | ☑️                      | ☑️                         | Proxy B         | Proxy B         |
| 3   | –                       | –                          | direkt          | direkt          |
| 4   | –                       | ☑️                         | Proxy B         | Proxy B         |
| 5   | ☑️ (ohne `NO_PROXY`)    | –                          | Proxy A         | **direkt**      |

Das Ergebnis war auf macOS und Windows gleich, mit und ohne Anmeldung. Die einzige Abweichung brachte der Windows-Systemproxy, dazu unten mehr.

### Python hält sich an die Regeln

Beginnen wir mit dem unkomplizierten Teil. 

Sobald `HTTP_PROXY` und `HTTPS_PROXY` gesetzt waren, richtete die `RequestsLibrary` jeden Aufruf an Proxy A.  
Fehlten die Variablen, ging er direkt, mit einer Ausnahme unter Windows, dazu gleich mehr.  
Bekam `GET` dagegen explizit `proxies=` mit, ging der Request über Proxy B, auch wenn die Variablen auf Proxy A zeigten (Szenario 2). Der explizite Proxy gewinnt.

Für die `RequestsLibrary` bedeutet das: Wenn du die Variablen setzt, musst du im Test nichts weiter tun.

```robotframework
*** Settings ***
Library    RequestsLibrary

*** Test Cases ***
Backend Antwortet
    ${resp}=    GET    https://example.org    expected_status=200
```

Willst du den Proxy lieber ausdrücklich im Test festlegen, etwa weil der Test auf verschiedenen Maschinen laufen soll, übergibst du ihn mit `proxies=`:

```robotframework
*** Settings ***
Library    RequestsLibrary

*** Test Cases ***
Backend Antwortet Über Proxy
    &{proxies}=    Create Dictionary    http=http://proxy.example:3128    https=http://proxy.example:3128
    ${resp}=    GET    https://example.org    proxies=${proxies}    expected_status=200
```

Dasselbe Argument nimmt auch `Create Session` entgegen, dann gilt der Proxy für alle Requests der Session.

Eine Eigenheit zeigte sich unter Windows. Im Lauf mit gesetztem Systemproxy (Internetoptionen bzw. WinINET) ging der Python-Request in Szenario 3, also ganz **ohne** Proxy-Variablen und ohne `proxies=`, trotzdem über Proxy A. Der Grund: Findet `getproxies()` unter Windows keine Variablen, liest es die Proxy-Einstellungen des Benutzers aus der Registry. Das ist praktisch, kann aber verwirren, wenn du „nichts konfiguriert“ hast.

**Mein Fazit für Python:** Ein expliziter Proxy hat Vorrang. Ohne ihn folgt requests den Umgebungsvariablen und unter Windows ersatzweise dem Systemproxy. Das Verhalten ist dokumentiert und vorhersagbar. Du musst nur wissen, welche Umgebung der Test tatsächlich sieht.

### Der Browser geht seinen eigenen Weg

Da wurde es richtig interessant... 

In allen Läufen mit gesetzten Proxy-Variablen (A), aber ohne `proxy=` in `New Browser` (B), lief über den Proxy A nur der Python-Request.  
Der Browser-Traffic hingegen fehlte vollständig: Chromium ging direkt ins Netz (Szenarien 1 und 5).

Warum ist das so? 

**Playwright startet Chromium nur dann mit einem Proxy, wenn man ihm explizit einen übergibt.**  
Ohne `proxy` setzt es kein `--proxy-server`-Flag, und die Proxy-Variablen wertet Chromium auf macOS und Windows nicht aus.  
Ich vermute, das ist Absicht: Der Browser soll sich ja in jedem Test gleich verhalten, ganz unabhängig von der Umgebung, in der er zufällig gestartet wird.


```robotframework
*** Settings ***
Library    Browser

*** Test Cases ***
Startseite Hinter Dem Proxy
    &{proxy}=    Create Dictionary    server=http://proxy.example:3128    bypass=localhost,127.0.0.1
    New Browser    chromium    proxy=${proxy}
    New Page    https://example.org
```

`server` nennt den Proxy, `bypass` die Hosts, die der Browser direkt erreichen soll. Das ist das Gegenstück zu `NO_PROXY`, nur eben für den Browser. `proxy=` hat in allen Läufen gewirkt, unabhängig davon, was in den Variablen oder in der Registry stand.

**Mein Fazit für den Browser:** Er liest nur, was du ihm in `New Browser` sagst. Alles andere ist für ihn Hintergrundrauschen.

## Die unsichtbare Verbindung: gRPC und `NO_PROXY`

Neben Python und dem Browser gibt es noch eine dritte Verbindung, die man leicht übersieht, weil sie gar nicht ins Internet will. Die Browser Library verbindet sich per gRPC mit ihrem Node-Prozess auf `127.0.0.1` und einem zufälligen Port.

> **Info:** gRPC ist ein Protokoll für Aufrufe zwischen Prozessen. Die Browser Library nutzt es, damit die Python-Seite (die Keywords) und die Node-Seite (Playwright) miteinander sprechen können.

Lange war genau das eine Stolperfalle. Die gRPC-Bibliothek für Python schickt auch lokale Verbindungen über den Proxy aus den Umgebungsvariablen, wenn `NO_PROXY` sie nicht ausnimmt. Ein Proxy auf einem anderen Rechner kann `127.0.0.1` aber nicht erreichen, denn dort zeigt die Adresse auf ihn selbst. Das Ergebnis war eine Fehlermeldung, die viele in der Community kennen dürften: `Could not connect to the playwright process`.

Seit Browser Library 20.4.0 ist das behoben ([robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Die Library schaltet den Proxy für ihren internen Kanal selbst ab (`grpc.enable_http_proxy=0`). Im Versuch lief deshalb auch das Szenario ohne `NO_PROXY` in allen Läufen durch, auf beiden Plattformen.

Ich empfehle trotzdem, `NO_PROXY` mindestens auf `localhost,127.0.0.1` zu setzen. Es kostet nichts, schützt ältere Environments und hält auch andere lokale Verbindungen vom Proxy fern. Und falls du noch eine Version vor 20.4.0 im Einsatz hast, ist das ein guter Grund für ein Update.

## Woher kommen die Variablen eigentlich?

Bis hierhin klingt alles übersichtlich: Variablen für Python, `proxy=` für den Browser, `NO_PROXY` für die Sicherheit. Die tückischste Fehlerquelle liegt aber eine Ebene darüber, nämlich bei der Frage, welche Variablen der Test überhaupt sieht.

Ich habe das am eigenen Leib erfahren. Einer meiner ersten Läufe lieferte Ergebnisse, die zu keiner Erwartung passten. Die Ursache: Meine Shell hatte noch ein `HTTP_PROXY` aus einer früheren Sitzung. Der Test hatte es geerbt, ohne dass ich es irgendwo konfiguriert hätte.

In der Produktion ist es genauso, nur schwerer zu sehen. Ein Test erbt die Umgebung des Prozesses, der ihn startet. Das kann eine Shell sein, ein CI-Agent, ein Windows-Dienst oder ein Scheduler. Systemweite Variablen wirken also auch dann, wenn im Projekt nichts steht. Unter Windows kommt noch hinzu, dass der Systemproxy pro Benutzer gilt. Läuft der Test als SYSTEM, gelten dessen Einstellungen und nicht die des Administrators, der gerade angemeldet ist und „doch alles eingestellt“ hat.

Die einfachste Abhilfe sind drei Zeilen Transparenz am Anfang jedes Tests:

```robotframework
*** Test Cases ***
Proxy-Umgebung Protokollieren
    Log    HTTP_PROXY=%{HTTP_PROXY=}
    Log    HTTPS_PROXY=%{HTTPS_PROXY=}
    Log    NO_PROXY=%{NO_PROXY=}
```

Die Syntax `%{NAME=}` liefert einen leeren Wert, wenn die Variable fehlt, statt den Test abzubrechen. Wenn du im Fehlerfall das Log öffnest, siehst du sofort, mit welcher Umgebung der Test tatsächlich lief.

## Das Gesamtbild

Fasst man alle Messungen zusammen, ergibt sich ein klares Bild: Jede Verbindung im Test liest ihre Proxy-Einstellungen aus einer anderen Quelle.

![Schichtenmodell: wer welche Proxy-Einstellung liest](schichtenmodell.png)

Python nimmt einen expliziten Proxy (`proxies=`), sonst die Umgebungsvariablen und unter Windows ersatzweise den Systemproxy. Chromium liest nur `proxy=` aus `New Browser`. Die interne gRPC-Verbindung der Browser Library ist seit 20.4.0 vom Proxy ausgenommen.

## Die Checkliste für den nächsten Proxy-Fall

Aus den Messungen ist eine kurze Liste geworden, die ich inzwischen bei jedem neuen Projekt hinter einem Proxy durchgehe:

- Jeder `New Browser`, der durch den Proxy muss, bekommt `proxy=` mit `server` und `bypass`, auch wenn Variablen oder ein Systemproxy gesetzt sind.
- Die RequestsLibrary bekommt entweder die Umgebungsvariablen oder `proxies=`, wenn der Test unabhängig von der Umgebung laufen soll.
- `NO_PROXY` enthält mindestens `localhost,127.0.0.1`.
- Die Browser Library ist mindestens Version 20.4.0.
- Die Umgebung des startenden Prozesses ist bekannt, also Dienst, Benutzer und systemweite Variablen.
- Unter Windows ist der Systemproxy des ausführenden Benutzers bekannt, denn Python folgt ihm, wenn keine Variablen gesetzt sind.
- Der Test protokolliert seine Proxy-Variablen.

## Sonderfall Robotmk: RCC-Profile

Wenn du Robot Framework mit Robotmk betreibst, kennst du noch eine weitere Stelle für Proxy-Einstellungen: das RCC-Profil. RCC baut die Python-Umgebungen für die Tests und lässt sich über Profile für Unternehmensnetze konfigurieren:

```yaml
name: firmenproxy
description: RCC-Proxyprofil für den Firmen-Proxy
settings:
  certificates:
    verify-ssl: true
  network:
    no-proxy: 'localhost,127.0.0.1'
    https-proxy: 'http://proxyuser:s3cr3t@proxy.example:3128'
    http-proxy: 'http://proxyuser:s3cr3t@proxy.example:3128'
  meta:
    name: firmenproxy
    description: RCC-Proxyprofil für den Firmen-Proxy
    source: Robotmk
```

Die naheliegende Annahme lautet: Im Profil steht der Proxy, also geht der ganze Test darüber. Die Messungen zeigen etwas anderes. Ein RCC-Profil macht für den Test **genau eines**: Es setzt `HTTP_PROXY`, `HTTPS_PROXY` und `NO_PROXY`. Als Gegenprobe habe ich alle Szenarien zusätzlich ohne Profil und nur mit denselben Variablen ausgeführt. Die Ergebnisse waren auf macOS und Windows identisch. Damit gilt alles, was dieser Artikel über die Variablen sagt, auch für RCC-Profile: Python folgt dem Profil, der Browser nicht. `proxy=` in `New Browser` bleibt Pflicht.

Zwei Details sind für Robotmk-Anwender trotzdem wichtig:

- **`rcc task script` erbt die Umgebung des Aufrufers.** Ohne Profil setzt RCC keine Proxy-Variablen, entfernt aber auch keine vorhandenen. Variablen des Schedulers oder des Systems kommen also im Test an.
- **`rcc ht vars` zeigt nur, was das Profil setzt.** Geerbte Variablen tauchen dort nicht auf. Wenn du damit prüfst, welcher Proxy im Test wirkt, siehst du im Zweifel nur die halbe Wahrheit. Das Protokollieren der Variablen im Test ist deshalb auch hier der verlässlichere Weg.

## Referenz: Proxy mit Anmeldung

Viele Firmen-Proxies verlangen Benutzer und Passwort. Am Weg der Requests ändert das nichts, aber jede Stelle erwartet die Zugangsdaten in einer anderen Form. Alle Varianten liefen im Versuch durch.

**Umgebungsvariable** (und damit RequestsLibrary ohne `proxies=`): Zugangsdaten in der URL.

```text
HTTPS_PROXY=http://proxyuser:s3cr3t@proxy.example:3128
```

**RequestsLibrary mit `proxies=`:** ebenfalls in der URL.

```robotframework
*** Settings ***
Library    RequestsLibrary

*** Test Cases ***
Backend Über Proxy Mit Anmeldung
    ${proxy}=    Set Variable    http://%{PROXY_USER}:%{PROXY_PASS}@proxy.example:3128
    &{proxies}=    Create Dictionary    http=${proxy}    https=${proxy}
    ${resp}=    GET    https://example.org    proxies=${proxies}    expected_status=200
```

**Browser Library:** eigene Felder `username` und `password` im `proxy`-Dictionary.

```robotframework
*** Settings ***
Library    Browser

*** Test Cases ***
Startseite Mit Proxy-Anmeldung
    &{proxy}=    Create Dictionary    server=http://proxy.example:3128    bypass=localhost,127.0.0.1
    ...    username=%{PROXY_USER}    password=%{PROXY_PASS}
    New Browser    chromium    proxy=${proxy}
    New Page    https://example.org
```

**RCC-Profil:** wie die Umgebungsvariable, die URL mit Zugangsdaten in `http-proxy` und `https-proxy`. RCC reicht sie unverändert an Python weiter.

In den Proxy-Logs sieht man einen kleinen Unterschied: requests schickt die Zugangsdaten gleich mit der ersten Anfrage mit, der Proxy musste nie mit `407 Proxy Authentication Required` antworten. Chromium fragt zunächst ohne Anmeldung an, erhält einmal 407 und meldet sich dann an.

Zwei Hinweise aus der Praxis: Die Zugangsdaten gehören nicht in die `.robot`-Datei, sondern in Umgebungsvariablen oder einen Tresor. Und wenn dein Passwort Sonderzeichen enthält, musst du sie in der URL kodieren, aus `@` wird zum Beispiel `%40`. Diesen Fall habe ich nicht eigens gemessen, er folgt aber aus den Regeln für URLs.

## Was bleibt

Als ich mit den Messungen begann, hatte ich eine einfache Frage im Kopf: Geht der Test über den Proxy oder nicht? Am Ende stand eine bessere Frage: **Welcher Teil des Tests geht über welchen Proxy, und wer hat ihm das gesagt?** Mit dieser Frage im Hinterkopf lösen sich die meisten Proxy-Rätsel fast von selbst.

Das Verhalten von Python und Chromium ist dabei keine Laune, sondern folgt nachvollziehbaren Entscheidungen der jeweiligen Projekte. Unbequem wird es erst, wenn man es nicht kennt. Deshalb finde ich es wertvoll, solche Erfahrungen in der Community zu teilen. Viele der Fallstricke, etwa die gRPC-Verbindung vor 20.4.0, wurden nur deshalb behoben, weil jemand sie gemeldet und reproduzierbar beschrieben hat. Mein Dank gilt allen, die daran mitgewirkt haben.

Ein paar Fragen sind noch offen. Folgt Chromium dem Windows-Systemproxy, wenn er nicht headless läuft? Wie verhält er sich bei einer PAC-Datei? Und was ändert sich, wenn der Scheduler als SYSTEM statt als angemeldeter Benutzer läuft? Das Testprojekt liegt unter [github.com/Robotmk/rf-web-proxytest](https://github.com/Robotmk/rf-web-proxytest), du kannst die Messungen also auf deinen eigenen Maschinen wiederholen.

Und damit zu dir: Welchen Proxy-Fallstrick hast du in deinen Robot-Framework-Projekten schon erlebt, und wie bist du ihm auf die Spur gekommen?
