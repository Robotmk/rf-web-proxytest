# Am Proxy vorbei

Proxy-Probleme gehören zu den Fällen, bei denen ich innerlich kurz seufze. Nicht, weil sie schwer wären, sondern weil sie so schwer zu greifen sind. Seit heute weiß ich auch, warum.

Ich wollte das Verhalten von Browser Library und RequestsLibrary mal "kurz" in einem Test nachstellen. Herausgekommen ist ein nettes kleines Testprojekt mit zwei Proxies, die jeden Request mitschreiben, und eine interessante Erkenntnis.

<!--more-->

## Der Testaufbau

### Testcase

Zur Demonstration dient ein ganz einfacher Testcase, der zuerst per **REST-Aufruf** prüft, ob ein Backend antwortet, und dann eine Weboberfläche im **Browser** öffnet:

```
Python Request
    GET    url=http://example.com/?via=python-requests    expected_status=200

Open HTTP And HTTPS Page
    Open Scenario Browser
    New Page    http://example.com
    Get Title    ==    Example Domain
    Go To    https://example.org
    Get Title    ==    Example Domain
```

`Open Scenario Browser` ist ein Keyword, das die Browser Library startet.  
Es ist in allen Läufen identisch, nur die Proxy-Konfiguration variiert.

Wie sich die beiden oben genannten Libraries daran halten, wollte ich genau wissen.

### Proxies

Ich habe mit **zwei Docker-Instanzen** von [mitmproxy](https://www.mitmproxy.org) aufgesetzt. 

- **Proxy A** ist vorgesehen für die Umgebungsvariablen des Betriebssystems.  
- **Proxy B** wird im Test selbst an die Browser-Instanz im Keyword `New Browser` übergeben, um die Proxy-Config A ggf. zu überschreiben.

### Proxy-Umgebungsvariablen

Ich wollte auch wissen, was passiert, wenn beim Aufruf von RObot Framework bereits Proxy-Umgebungsvariablen gesetzt sind.  

Diese gibt es: 

- `HTTP_PROXY` = Proxy-Server für HTTP-Ziele  
- `HTTPS_PROXY` = Proxy-Server für HTTPS-Ziele     
- `NO_PROXY` = Hosts, die direkt erreicht werden sollen (Proxy-Bypass)

> Viele Programme verstehen diese Variablen als Proxy-Konfiguration. 
> Ein Standard ist das aber nicht: Jedes Programm entscheidet selbst, ob und wie es sie liest.


Aus Netzwerksicht sind das aber schon mal zwei Paar Schuhe. 
Der REST-Aufruf **RequestsLibrary** läuft im Python-Prozess von Robot Framework.  
Die **BrowserLibrary** hingegen startet dafür einen Nodejs-Prozess, der dann über Playwright z. B. den **Chromium**-Browser steuert.

### Der Testablauf

Testen wollte ich fünf Kombinationen:

| #   | Proxy-Env-Variablen (A) | `NO_PROXY` | `proxy=` im Browser (B) |
| --- | ----------------------- | ---------- | ----------------------- |
| 1   | ☑️                      | ☑️         | nein                    |
| 2   | ☑️                      | ☑️         | ☑️                      |
| 3   | –                       | –          | nein                    |
| 4   | –                       | –          | ☑️                      |
| 5   | ☑️                      | fehlt      | nein                    |
Zu testen 

Damit ich nicht alles von Hand ausführen muss, habe ich mir ein kleiens Script für Linux und Windows geschrieben.  
Für jedes Szenario startet es beide Proxies als Docker-Container), setzt die Proxy-Variablen (oder lässt sie weg), wählt die Browser-Konfiguration mit oder ohne `proxy=` und führt den Test aus.
Danach sammelt es die Logs beider Proxies ein und hält in einer Zusammenfassung fest, welcher Request über welchen Proxy lief.


Jede Kombination lief einmal ohne und einmal mit Proxy-Anmeldung (Benutzer und Passwort), auf macOS und auf Windows Server 2022.
Außerdem kamen die Proxy-Variablen einmal aus einem RCC-Profil und einmal direkt aus der Umgebung – dazu mehr im Abschnitt über Robotmk am Ende.
Unter Windows kam ein weiterer Lauf hinzu, bei dem zusätzlich der Systemproxy des Benutzers auf Proxy A zeigte.
Insgesamt waren das 45 Testläufe, alle grün. Spannend war also nicht, *ob* der Test durchläuft, sondern *welchen Weg* er dabei nimmt.

## Python hält sich an die Regeln

Beginnen wir mit dem unkomplizierten Teil. Sobald `HTTP_PROXY` und `HTTPS_PROXY` gesetzt waren, landete der Python-Request in jedem Lauf bei Proxy A. Fehlten die Variablen, ging er direkt. Keine Überraschungen.

Die RequestsLibrary baut auf requests auf, und requests ermittelt den Proxy mit der Funktion `getproxies()` aus dem Modul `urllib.request` der Standardbibliothek. Die eigentliche Verbindung baut requests dann über urllib3 auf. Für den REST-Teil deines Tests bedeutet das: Wenn du die Variablen setzt, musst du im Test nichts weiter tun.

```robotframework
*** Settings ***
Library    RequestsLibrary

*** Test Cases ***
Backend Antwortet
    ${resp}=    GET    https://example.org    expected_status=200
```

Willst du den Proxy lieber ausdrücklich im Test festlegen, etwa weil der Test auf verschiedenen Maschinen laufen soll, übergibst du ihn der Session:

```robotframework
*** Settings ***
Library    RequestsLibrary

*** Test Cases ***
Backend Antwortet Über Proxy
    &{proxies}=    Create Dictionary    http=http://proxy.example:3128    https=http://proxy.example:3128
    Create Session    api    https://example.org    proxies=${proxies}
    ${resp}=    GET On Session    api    /    expected_status=200
```

Eine Eigenheit zeigte sich unter Windows. Im Lauf mit gesetztem Systemproxy (Internetoptionen bzw. WinINET) gab es Szenarien ganz **ohne** Proxy-Variablen, und trotzdem ging der Python-Request über Proxy A. Der Grund: Findet `getproxies()` unter Windows keine Variablen, liest es die Proxy-Einstellungen des Benutzers aus der Registry. Das ist praktisch, kann aber verwirren, wenn du „nichts konfiguriert“ hast.

**Mein Fazit für Python:** Es folgt den Umgebungsvariablen und unter Windows ersatzweise dem Systemproxy. Das Verhalten ist dokumentiert und vorhersagbar. Du musst nur wissen, welche Umgebung der Test tatsächlich sieht.

## Der Browser geht seinen eigenen Weg

Da wurde es richtig interessant... 

In allen Läufen mit gesetzten Proxy-Variablen (A), aber ohne `proxy=` in `New Browser` (B), lief über den Proxy A nur der Python-Request.  
Der Browser-Traffic hingegen fehlte vollständig.

Warum ist das so? 

**Playwright startet Chromium nur dann mit einem Proxy, wenn man ihm explizit einen übergibt.**  
Ohne `proxy` setzt es kein `--proxy-server`-Flag, und die Proxy-Variablen wertet Chromium auf macOS und Windows nicht aus.  
Und ich bin mir sicher, warum das so gebaut wurde: Der Browser soll sich ja in jedem Test gleich verhalten, ganz unabhängig von der Umgebung, in der er zufällig gestartet wird.


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

## Gleiche Zugangsdaten, zwei Formate

Viele Firmen-Proxies verlangen eine Anmeldung. Auch hier erwarten Python und Browser die Daten in unterschiedlicher Form.

Python erwartet die Zugangsdaten in der URL der Umgebungsvariable:

```text
HTTPS_PROXY=http://proxyuser:s3cr3t@proxy.example:3128
```

In den Proxy-Logs war schön zu sehen, wie gut das funktioniert: Python schickte die Zugangsdaten gleich mit der ersten Anfrage mit. Proxy A musste kein einziges Mal mit `407 Proxy Authentication Required` antworten.

Der Browser braucht dagegen die eigenen Felder `username` und `password` im `proxy`-Dictionary:

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

Chromium fragt zunächst ohne Anmeldung an, erhält einmal 407 und meldet sich dann an. Danach lief der Traffic in allen Läufen ohne weitere Rückfragen durch.

Zwei Hinweise aus der Praxis: Die Zugangsdaten gehören nicht in die `.robot`-Datei, sondern in Umgebungsvariablen oder einen Tresor. Und wenn dein Passwort Sonderzeichen enthält, musst du sie in der URL für Python kodieren, aus `@` wird zum Beispiel `%40`. Diesen Fall habe ich nicht eigens gemessen, er folgt aber aus den Regeln für URLs.

## Die unsichtbare Verbindung: gRPC und `NO_PROXY`

Neben Python und dem Browser gibt es noch eine dritte Verbindung, die man leicht übersieht, weil sie gar nicht ins Internet will. Die Browser Library verbindet sich per gRPC mit ihrem Node-Prozess auf `127.0.0.1` und einem zufälligen Port.

> **Info:** gRPC ist ein Protokoll für Aufrufe zwischen Prozessen. Die Browser Library nutzt es, damit die Python-Seite (die Keywords) und die Node-Seite (Playwright) miteinander sprechen können.

Lange war genau das eine Stolperfalle. Die gRPC-Bibliothek für Python schickt auch lokale Verbindungen über den Proxy aus den Umgebungsvariablen, wenn `NO_PROXY` sie nicht ausnimmt. Ein Proxy auf einem anderen Rechner kann `127.0.0.1` aber nicht erreichen, denn dort zeigt die Adresse auf ihn selbst. Das Ergebnis war eine Fehlermeldung, die viele in der Community kennen dürften: `Could not connect to the playwright process`.

Seit Browser Library 20.4.0 ist das behoben ([robotframework-browser#1037](https://github.com/MarketSquare/robotframework-browser/issues/1037)). Die Library schaltet den Proxy für ihren internen Kanal selbst ab (`grpc.enable_http_proxy=0`). Im Versuch lief deshalb auch das Szenario ohne `NO_PROXY` in allen Läufen durch, mit und ohne Anmeldung, auf beiden Plattformen.

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

Python folgt den Umgebungsvariablen und unter Windows ersatzweise dem Systemproxy. Chromium liest nur `proxy=` aus `New Browser`. Die interne gRPC-Verbindung der Browser Library ist seit 20.4.0 vom Proxy ausgenommen.

## Die Checkliste für den nächsten Proxy-Fall

Aus den Messungen ist eine kurze Liste geworden, die ich inzwischen bei jedem neuen Projekt hinter einem Proxy durchgehe:

- Jeder `New Browser`, der durch den Proxy muss, bekommt `proxy=` mit `server` und `bypass`, auch wenn Variablen oder ein Systemproxy gesetzt sind.
- Zugangsdaten für den Browser stehen in `username` und `password`, für Python in der URL der Variable.
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

Die Zugangsdaten in der Proxy-URL reicht RCC unverändert an Python weiter. Für den Browser gilt wie oben: `username` und `password` im `proxy`-Dictionary.

## Was bleibt

Als ich mit den Messungen begann, hatte ich eine einfache Frage im Kopf: Geht der Test über den Proxy oder nicht? Am Ende stand eine bessere Frage: **Welcher Teil des Tests geht über welchen Proxy, und wer hat ihm das gesagt?** Mit dieser Frage im Hinterkopf lösen sich die meisten Proxy-Rätsel fast von selbst.

Das Verhalten von Python und Chromium ist dabei keine Laune, sondern folgt nachvollziehbaren Entscheidungen der jeweiligen Projekte. Unbequem wird es erst, wenn man es nicht kennt. Deshalb finde ich es wertvoll, solche Erfahrungen in der Community zu teilen. Viele der Fallstricke, etwa die gRPC-Verbindung vor 20.4.0, wurden nur deshalb behoben, weil jemand sie gemeldet und reproduzierbar beschrieben hat. Mein Dank gilt allen, die daran mitgewirkt haben.

Ein paar Fragen sind noch offen. Folgt Chromium dem Windows-Systemproxy, wenn er nicht headless läuft? Wie verhält er sich bei einer PAC-Datei? Und was ändert sich, wenn der Scheduler als SYSTEM statt als angemeldeter Benutzer läuft? Das Testprojekt liegt unter [github.com/Robotmk/rf-web-proxytest](https://github.com/Robotmk/rf-web-proxytest), du kannst die Messungen also auf deinen eigenen Maschinen wiederholen.

Und damit zu dir: Welchen Proxy-Fallstrick hast du in deinen Robot-Framework-Projekten schon erlebt, und wie bist du ihm auf die Spur gekommen?
