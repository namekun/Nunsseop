<p align="center"><img src="docs/images/icon.png" width="120" alt="Nunsseop-Symbol"></p>

<h1 align="center">Nunsseop</h1>

<p align="center">
  <b>Die Notch deines MacBooks, endlich nützlich.</b><br>
  Musik, Anrufe, Dateien, ein Launcher im Spotlight-Stil, KI-Nutzung, Mitteilungen von Agenten, dein Kalender und System-HUDs, alles nur einen Hover entfernt.
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=111111&label=release" alt="Neueste Version"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 oder neuer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555" alt="MIT-Lizenz"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="Natives Swift">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.es.md">Español</a> · <b>Deutsch</b> · <a href="README.fr.md">Français</a> · <a href="https://namekun.github.io/Nunsseop/">Website</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="Ausgeklappte Notch mit aktueller Wiedergabe und Kalender">
</p>

*Nunsseop* (눈썹) ist Koreanisch für *Augenbraue*, den kleinen Bogen über deinem Bildschirm. Die App ist kostenlos und Open Source, ohne Account, Abo oder Tracking.

## In 30 Sekunden installieren

```sh
brew install --cask namekun/tap/nunsseop
```

Dafür brauchst du [Homebrew](https://brew.sh). Homebrew entfernt das Quarantäne-Flag, sodass sich die App sofort öffnen lässt. Zum Aktualisieren führst du `brew update && brew upgrade --cask nunsseop` aus; sobald ein Update verfügbar ist, kopiert Einstellungen › Allgemein › Updates diesen Befehl in deine Zwischenablage (bei einer App, die aus dem alten dmg installiert wurde, einen Befehl, der sie zu Homebrew umzieht).

Erfordert macOS 14 Sonoma oder neuer. Läuft auf Apple Silicon und Intel sowie auf Bildschirmen ohne Notch.

## Deine erste Minute

1. **Fahre mit dem Zeiger über die Notch.** Sie klappt auf. Bewegst du den Zeiger weg, zieht sie sich wieder zurück.
2. **Spiele etwas ab**, in Music, Spotify, YouTube Music oder einem beliebigen Browser. Die Notch erkennt es, und die eingeklappte Notch zeigt ein kleines Cover und einen Visualizer.
3. **Rechtsklick auf die Notch → Einstellungen**, um deine Tabs, ihre Reihenfolge, die gewünschten Pop-ups und die Größe festzulegen.

Es gibt kein Dock-Symbol. Nunsseop lebt in der Notch.

## Ein Blick ins Innere

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="Suche mit einer App, einem Befehl und einer Einstellung"><br>**Suche.** Ein Launcher für Apps, Dateien, Befehle, Zwischenablage, Emoji und Rechenaufgaben, mit einem Kurzbefehl deiner Wahl. | <img src="docs/images/tab-ai.png" alt="KI-Nutzung für Claude Code und Codex"><br>**KI-Nutzung.** Limits von Claude Code und Codex, ganz ohne Anmeldung. |
| <img src="docs/images/shelf.png" alt="Dateiablage mit AirDrop-Kachel"><br>**Ablage.** Parke Dateien in der Notch oder wirf sie auf AirDrop. | <img src="docs/images/tab-timer.png" alt="Timer-Tab"><br>**Timer.** Countdown, Pomodoro und Stoppuhr, in jeder gewünschten Länge. |
| <img src="docs/images/tab-tools.png" alt="Werkzeuge-Tab"><br>**Werkzeuge.** Audioausgabe, Mikrofon stummschalten, Wach halten, Bildschirmaufnahme, Farbwähler und Texterfassung. | <img src="docs/images/tab-system.png" alt="System-Tab mit Geräte-Akkus"><br>**System.** CPU, Speicher, Festplatte, Netzwerk und Geräte-Akkus. |
| <img src="docs/images/tab-emoji.png" alt="Emoji-Auswahl"><br>**Emoji.** Alle Emoji, durchsuchbar, mit einem Klick kopiert. | <img src="docs/images/hud-headphones.png" alt="HUD für den Kopfhörer-Akku"><br>**HUDs.** Lautstärke, Helligkeit, AirPods-Akku und mehr. |
| <img src="docs/images/collapsed-call.png" alt="Eingeklappte Notch während eines Zoom-Anrufs"><br>**Anrufe.** Die Anruf-App und wie lange du schon sprichst. | <img src="docs/images/collapsed-idle.png" alt="Eingeklappte Notch mit verbleibender Claude-Code-Nutzung und Wetter"><br>**Auf einen Blick.** Wähle, was jede Seite der geschlossenen Notch anzeigt. |

## Alles, was die App kann

**🎵 Musik**
- **Aktuelle Wiedergabe aus jeder App.** Music, Spotify, YouTube Music und Browser wie Safari, Chrome, Arc, Dia und Aside. Cover, Steuerung und eine Fortschrittsleiste zum Ziehen.
- **Synchronisierte Songtexte** von [LRCLIB](https://lrclib.net), unter dem Titel oder unter der Notch, während du arbeitest.
- **Vorschau.** Wechselt der Song, blendet sich kurz sein Titel ein.
- **Podcasts und lange Videos** bekommen 15-Sekunden-Sprünge und eine Geschwindigkeitstaste (1× bis 2×), sofern der Player sie unterstützt.

**🗂️ Dinge erledigen**
- **Ablage.** Ziehe Dateien auf die Notch und später wieder heraus, mit Vorschau für Bilder, PDFs und Videos. Bildschirmfotos und fertige Downloads können automatisch dort landen. Schüttle den Zeiger beim Ziehen von Dateien irgendwo, und direkt neben ihm erscheint ein kleines Ablageziel.
- **Kalender und Erinnerungen.** Der heutige Tag in großen Ziffern, deine Woche mit einem Punkt an vollen Tagen, die heutigen Termine und Erinnerungen zum Abhaken. Jeder in macOS hinzugefügte Account funktioniert (Google, iCloud, Exchange und mehr), und du wählst, welche Kalender angezeigt werden.
- **Anstehende Termine.** Fünf Minuten vor Beginn eines Termins mit Uhrzeit zeigt die Notch seinen Titel und wie bald er startet. Termine mit einem Link zu Zoom, Google Meet, Teams, Webex, FaceTime, Whereby oder Chime erhalten im Start-Tab eine grüne Schaltfläche „Beitreten“, und ein Klick auf die Mitteilung tritt dem Meeting bei.
- **Eine Suche, die Spotlight oder Raycast ersetzen kann.** Apps (auch solche außerhalb des Ordners „Programme“), Dateien, Systembefehle und Einstellungen, Zwischenablage-Verlauf, Emoji (beginne mit `:`) und Rechenaufgaben wie `12*(3+4)`, sortiert danach, was du am häufigsten öffnest. Auch Initialen funktionieren: `vsc` findet Visual Studio Code. Pfeiltasten wählen aus, der Zeilenschalter öffnet.
- **Dein Kurzbefehl.** Standardmäßig <kbd>⇧⌘Leertaste</kbd>, oder nimm in den Einstellungen eine beliebige Kombination auf. Nunsseop sagt dir, wenn macOS oder eine andere App sie schon belegt.
- **Timer, Zwischenablage-Verlauf, Notizen und eine Emoji-Auswahl.** Der Zwischenablage-Verlauf bleibt im Speicher und überspringt alles, was ein Passwortmanager als geheim markiert. Tracking-Parameter wie `utm_` und `fbclid` werden aus kopierten Links entfernt.

**💻 Dein Mac**
- **System-HUDs.** Lautstärke, Helligkeit (auch bei externen DDC-Bildschirmen), Tastaturbeleuchtung, Ladevorgang, Feststelltaste und AirPods-Akku erscheinen in der Notch. Die App kann die Tasten für Lautstärke und Helligkeit übernehmen, damit das System-HUD ausbleibt.
- **Systemwerte und Akkus.** CPU, Speicher, Festplatte, Netzwerk sowie deine Maus, Tastatur und dein Trackpad, mit einer Warnung bei niedrigem Akkustand.
- **Kamera- und Mikrofonanzeige.** Ein Punkt auf der Notch, solange eine App sie verwendet.
- **Werkzeuge.** Audioausgabe wechseln, die Lautstärke jeder App einstellen (experimentell, macOS 14.2+), das Mikrofon stummschalten, den Mac wach halten, den Bildschirm aufnehmen, Laufwerke auswerfen, eine Farbe an beliebiger Stelle des Bildschirms auswählen und den Text aus jedem Bereich des Bildschirms kopieren.
- **Wetter, Downloads, Spiegel und Dock-Apps**, nur einen Hover entfernt.

**📞 Auch wenn sie geschlossen ist**
- **Anrufe.** Bei einem Anruf in Zoom, FaceTime, Teams, Slack, Discord, WhatsApp oder Google Meet zeigt die geschlossene Notch die App und wie lange du schon sprichst. Maßgeblich ist, welche App das Mikrofon nutzt, daher sind keine zusätzlichen Berechtigungen nötig. Bei Zoom, FaceTime und Meet kannst du das Mikrofon stummschalten oder die Kamera ausschalten, direkt von der Notch aus, ohne zum Anruf zu wechseln.
- **Deine Wahl auf jeder Seite.** Wenn nichts abgespielt wird, zeige die verbleibende Nutzung von Claude Code oder Codex, aktive Agenten, Akku, Wetter oder das Datum.
- **Musik und Timer.** Ein kleines Cover und ein Visualizer, solange Musik läuft, und die Restzeit, solange ein Timer läuft.
- **Downloads.** Wie weit ein Download in Safari oder Chrome ist, in Prozent, anhand desselben Fortschritts, den der Finder an der Datei zeigt. Nichts fragt ständig nach.

**🤖 Für Entwickler**
- **KI-Nutzung.** Limits von Claude und Codex mit Zeitpunkten des Zurücksetzens sowie der Token-Verbrauch der letzten 5 Stunden und 7 Tage, gezählt über Claude Code, Codex, gjc, omo und OpenCode hinweg. Gelesen aus Dateien, die diese Tools ohnehin auf deinem Mac ablegen, daher musst du dich nirgends anmelden.
- **Claude-Limits von Claude Code.** Verbinde unter Einstellungen › Dienste › KI-Nutzung die Statuszeile von Claude Code. Claude Code übergibt ihr deine 5-Stunden- und Wochenlimits bei jeder Antwort, sodass der Tab „KI-Nutzung“ aktuell bleibt, während du arbeitest, ohne dass Nunsseop dafür bei Anthropic nachfragt. Die Statuszeile, die du schon hattest, wird wie bisher angezeigt, und „Trennen“ stellt sie wieder her.
- **Claude-Limits live (optional).** Für den Fall, dass du Claude anderswo nutzt, fragt der Tab „KI-Nutzung“ einmal, ob deine 5-Stunden- und Wochenlimits von Claude etwa einmal pro Stunde bei Anthropic abgerufen werden sollen, mit der Anmeldung, die Claude Code im Schlüsselbund ablegt. Aus, bis du zustimmst; später änderbar unter Einstellungen › Dienste. Es gilt die jeweils aktuellste Quelle.
- **Mitteilungen von Agenten und Terminals.** Hooks von Claude Code, Codex, Gemini CLI und OpenCode, Agenten in Muxy, cmux und herdr sowie Glocken von tmux und WezTerm erscheinen in der Notch. Ein Klick auf eine Mitteilung bringt das zugehörige Terminal, den Bereich oder Tab in den Vordergrund ([Einrichtung weiter unten](#mitteilungen-von-agenten-und-terminals)).
- **Tab „Mitteilungen“.** Die letzten 30 Mitteilungen von Agenten, Terminals und deinem Kalender, mit einem Badge für ungesehene; ein Klick führt dich dorthin zurück, woher sie kam. Standardmäßig aus (Einstellungen › Notch) und nur im Speicher gehalten.
- **Aktive Agenten.** Ein Element der geschlossenen Notch, das anzeigt, wie viele Coding-Agenten auf dich warten (eine gelbe Hand) oder, wenn keiner wartet, wie viele arbeiten (ein grüner Blitz). Beobachtet herdr und Claude Code über dessen Hook (verbinden unter Einstellungen › Hinweise), auch Hintergrundsitzungen, die mit `claude --bg` gestartet wurden.

**🧩 Mach sie zu deiner eigenen**
- Wähle deine Tabs und ihre Reihenfolge, was Kopfzeile und eingeklappte Notch zeigen und welche Pop-ups du bekommst. **Alles, was du ausschaltest, läuft nicht mehr.**
- Unter macOS 26 nutzen die ausgeklappte Notch und ihre Karten Liquid Glass, sodass der Hintergrund sanft durchscheint. Du kannst einstellen, wie dunkel das Glas ist, bis hin zu 100 % für eine tiefschwarze Notch, oder das Glas ganz ausschalten.
- Auf Bildschirmen ohne Notch ist die geschlossene Notch eine kleine Pille in der Menüleiste, auf Wunsch aus Glas, mit der Augenbraue als weißem Pinselstrich darauf. Die Augenbraue hebt sich, wenn der Zeiger darüber ist. Nach einer Weile ohne Nutzung (3 bis 60 Sekunden, oder nie) senkt sie sich wie ein sich schließendes Auge und blendet sich aus, und sie kommt zurück, sobald der Zeiger sie erreicht; verweilst du eine halbe Sekunde darauf, öffnet sie sich und setzt sich an den oberen Rand. Dort erscheinen HUDs, Mitteilungen, Songtexte und die Vorschau in einer Zeile, mit dem Symbol direkt neben der Pegelleiste, dem Prozentwert oder dem Text. Ist nur eine Seite der Ruheanzeige eingeschaltet, wird die Pille nur so breit wie dieser Wert, direkt neben der Augenbraue.
- Wähle Bildschirm, Größe und Hover-Verzögerung, starte sie bei der Anmeldung und blende die Notch aus, solange der Deckel geschlossen ist.
- Nach unten wischen zum Öffnen, nach oben zum Schließen, im Start-Tab zur Seite wischen, um Titel zu überspringen.
- Spricht English, 한국어, 日本語, 简体中文, Español, Deutsch und Français, passend zu deinem Mac.

## FAQ

<details>
<summary><b>macOS meldet, dass Nunsseop nicht geöffnet werden kann.</b></summary>

Die App ist noch nicht notarisiert, installiere sie also mit Homebrew (`brew install --cask namekun/tap/nunsseop`). Homebrew entfernt das Quarantäne-Flag, und die App öffnet sich sofort.
</details>

<details>
<summary><b>Beim Abspielen von Musik erscheint nichts.</b></summary>

Nunsseop zeigt, was macOS als „Aktuelle Wiedergabe“ führt, daher muss der Player im Kontrollzentrum auftauchen. Die meisten Apps und Browser tun das. Zur Ausweichlösung siehe [So funktioniert die Anzeige der aktuellen Wiedergabe](#so-funktioniert-die-anzeige-der-aktuellen-wiedergabe).
</details>

<details>
<summary><b>Kann die Suche Spotlight ersetzen?</b></summary>

Ja. Öffne Einstellungen → Dienste, klicke auf den Kurzbefehl und drücke <kbd>⌘Leertaste</kbd>. Nunsseop weist darauf hin, dass Spotlight ihn belegt, und öffnet die Tastaturkurzbefehle, in denen du *Spotlight-Suche einblenden* abwählst. Die Suche öffnet sich auch, wenn ihr Tab ausgeblendet ist.
</details>

<details>
<summary><b>Es gibt zu viele Tabs.</b></summary>

Rechtsklick auf die Notch → Einstellungen → Notch, und schalte aus, was du nicht brauchst. Ausgeschaltete Funktionen laufen gar nicht mehr.
</details>

<details>
<summary><b>Mein Mac hat keine Notch.</b></summary>

Auf einem Bildschirm ohne Notch, etwa einem externen Monitor bei geschlossenem Deckel, ist die geschlossene Notch eine kleine Pille, die in der Menüleiste schwebt, mit der Augenbraue als weißem Pinselstrich darauf. Die Augenbraue hebt sich, wenn der Zeiger darüber ist, und beim Öffnen setzt sich die Notch in der üblichen Größe an den oberen Rand. HUDs, Mitteilungen, Songtexte und die Vorschau erscheinen in einer Zeile statt rund um eine Kamera. Bei Nichtbenutzung senkt sich die Augenbraue wie ein sich schließendes Auge, und die Pille blendet sich aus; schalte das ab oder ändere die Verzögerung in den Einstellungen. Dort wählst du auch, welchen Bildschirm sie nutzt.
</details>

<details>
<summary><b>Warum zeigt die KI-Nutzung veraltete Claude-Limits?</b></summary>

Standardmäßig stammen die 5-Stunden- und Wochenwerte von Claude aus Caches, die andere Tools schreiben: das HUD von [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), während du Claude Code in einem Terminal nutzt, oder gjc. Die Karte zeigt, wann sie zuletzt aktualisiert wurden. Für Limits, die aktuell bleiben, verbinde die Statuszeile von Claude Code unter Einstellungen › Dienste › KI-Nutzung: Claude Code übergibt ihr deine Limits bei jeder Antwort, und deine eigene Statuszeile funktioniert weiter. Wenn du Claude anderswo nutzt, schalte stattdessen die Live-Abfrage der Claude-Limits im Tab „KI-Nutzung“ oder unter Einstellungen › Dienste ein. Es gilt die jeweils aktuellste Quelle. Die Token-Summen sind immer live.
</details>

<details>
<summary><b>Nach einem Update zeigen die Lautstärketasten das HUD von Nunsseop nicht mehr.</b></summary>

Versionen vor 0.8.3 waren so signiert, dass macOS bei jedem Update die Berechtigung für Bedienungshilfen vergaß. Seit 0.8.3 bleibt sie erhalten. Wenn du von einer älteren Version kommst, entferne Nunsseop einmal unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen und erlaube es erneut; es wirkt ohne Neustart.
</details>

## Mitteilungen von Agenten und Terminals

Nunsseop lauscht an `127.0.0.1:47750` auf Mitteilungen von Tools auf deinem Mac. Anfragen müssen das geheime Token mitsenden, das in `~/Library/Application Support/Nunsseop/notify-token` liegt.

Öffne Einstellungen → Hinweise und drücke **Verbinden** neben Claude Code, Codex, Gemini CLI oder OpenCode. Es werden nur Tools aufgelistet, die du auf diesem Mac benutzt hast. Nunsseop ändert die Einstellungsdatei des jeweiligen Tools (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`) oder fügt ein Plugin in `~/.config/opencode/plugins` hinzu und behält die alte Datei mit der Endung `.nunsseop-backup`. Codex erlaubt nur einen `notify`-Befehl, daher läuft ein vorhandener nach dem von Nunsseop weiter. **Trennen** macht es rückgängig. Danach gestartete Sitzungen senden ihre Mitteilungen an die Notch.

Um Claude Code von Hand einzurichten, drücke **Claude-Code-Hook-Befehl kopieren** und füge ihn in `~/.claude/settings.json` ein:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<paste the copied command here>" }] }
    ]
  }
}
```

Terminals und Agenten-Apps brauchen keinen Hook:

- **Muxy** und **cmux:** ihre eigenen Mitteilungen werden aus der App gelesen und nicht angezeigt, solange sie im Vordergrund ist.
- **herdr:** Agenten, die fertig sind oder auf Eingabe warten, in jeder Sitzung, gelesen aus dem Socket von herdr.
- **tmux:** Glocken aus jedem Fenster. Nunsseop fügt nur dem laufenden tmux-Server einen Hook hinzu; `tmux.conf` bleibt unverändert.
- **WezTerm:** Glocken, über Zeilen, die du aus Einstellungen › Hinweise kopierst und in `~/.wezterm.lua` einfügst.

Jedes hat unter Einstellungen › Hinweise einen Schalter (bei WezTerm eine Schaltfläche, die stattdessen seine Konfigurationszeilen kopiert), der nur erscheint, wenn das Tool installiert ist. Tools, die bereits über ihren eigenen Hook verbunden sind, werden nicht doppelt angezeigt.

Auch jedes Skript kann eine Mitteilung senden:

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

## Berechtigungen

Nunsseop bittet erst dann um eine Berechtigung, wenn du die Funktion zum ersten Mal nutzt, die sie braucht.

| Funktion | Berechtigung | Wann gefragt wird |
| --- | --- | --- |
| Kalender | Kalender | Wenn du im Start-Tab auf *Zugriff erlauben* drückst |
| Erinnerungen | Erinnerungen | Wenn du im Start-Tab auf *Erinnerungen erlauben* drückst |
| Spiegel | Kamera | Wenn du im Spiegel-Tab auf *Kamera erlauben* drückst |
| Bildschirmaufnahme und Text aus Fenstern anderer Apps kopieren | Bildschirmaufnahme | Beim ersten Start einer Aufnahme oder Texterfassung |
| Aufnahme mit Ton | Mikrofon | Beim ersten Aufnehmen mit eingeschaltetem Mikrofonton |
| Übernahme der Tasten für Lautstärke, Helligkeit und Tastaturbeleuchtung | Bedienungshilfen | Wenn du die Option in den Einstellungen einschaltest |
| Ausweichlösung für die aktuelle Wiedergabe bei Music, Spotify und Browsern | Automation | Nur wenn die MediaRemote-Hilfsbibliothek nicht verfügbar ist |
| Google-Meet-, Zoom- und Teams-Anrufe im Browser anzeigen | Automation (dieser Browser) | Wenn ein Browser zum ersten Mal das Mikrofon nutzt |
| Bei der Anmeldung öffnen | Anmeldeobjekte | Wenn du es in den Einstellungen einschaltest |

## Datenschutz

Nunsseop sammelt und sendet keine persönlichen Daten. Es geht nur für Folgendes online:

- einmal täglich bei `api.github.com` nach einer neueren Version fragen (abschaltbar);
- synchronisierte Songtexte auf `lrclib.net` nachschlagen (abschaltbar);
- das Wetter von `open-meteo.com` für die von dir eingegebene Stadt abrufen (aus, bis du eine eingibst), wobei Apples Geocoder nach dem Standort der Stadt gefragt wird, wenn Open-Meteo sie nicht findet;
- Cover per HTTPS von bekannten Musikdiensten laden, nur wenn die MediaRemote-Hilfsbibliothek nicht verfügbar ist;
- bei `api.anthropic.com` etwa einmal pro Stunde deine Claude-Limits abfragen, mit der Anmeldung von Claude Code aus dem Schlüsselbund, nur wenn du die Live-Abfrage der Claude-Limits einschaltest.

Alles andere bleibt auf deinem Mac. Der Mitteilungsserver nimmt nur Verbindungen von diesem Mac an. Die KI-Nutzung wird aus lokalen Dateien gelesen, auch aus den Limits, die die Statuszeile von Claude Code auf diesem Mac ablegt, solange du die Live-Abfrage der Claude-Limits nicht einschaltest. Mitteilungen im Tab „Mitteilungen“ werden nur im Speicher gehalten. Aufnahmen werden neben deinen Bildschirmfotos gesichert. Die Kameravorschau läuft nur, solange der Spiegel-Tab geöffnet ist, und wird nie aufgezeichnet. Der Zwischenablage-Verlauf wird geleert, wenn Nunsseop beendet wird.

## So funktioniert die Anzeige der aktuellen Wiedergabe

Seit macOS 15.4 antwortet das private MediaRemote-Framework nur noch Prozessen, die von Apple signiert sind. Nunsseop liefert eine kleine Hilfsbibliothek (`Sources/NowPlayingHelper`) mit, die innerhalb von `/usr/bin/perl` des Systems läuft, den Zustand der aktuellen Wiedergabe liest, Befehle für Wiedergabe, Pause, Überspringen und Spulen sendet und JSON-Zeilen an die App zurückstreamt.

Das beruht auf einer privaten API, daher kann ein künftiges macOS-Update sie unbrauchbar machen. In dem Fall weicht Nunsseop für Music und Spotify auf AppleScript aus und liest bei Browsern Medien-Tabs aus. Diese Ausweichlösung braucht in jedem Browser die eingeschaltete Option *JavaScript von Apple Events erlauben*. Dia hat dafür keinen Menüpunkt, deshalb bietet Nunsseop an, es mit `--enable-applescript-javascript` neu zu starten.

## Aus dem Quellcode bauen

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

Du brauchst die Xcode Command Line Tools mit Swift 5.10 oder neuer. `scripts/bundle.sh` baut das Swift-Paket und verpackt es in ein ad-hoc signiertes App-Bundle.

## Lizenz

[MIT](LICENSE). Issues und Pull Requests sind willkommen.
