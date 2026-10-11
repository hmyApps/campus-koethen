<!-- Campus Köthen App · AGPL-3.0-only · Copyright © 2026 Leviora Studio and Jona Loreen Sommer -->

# @campus/map

Kanonischer Kartenkatalog, SVG-Validator und Generator der gebündelten Flutter-Kartenassets.

Der Katalog enthält vier klar gekennzeichnete Kartenbereiche:

- das **Ratke-Gebäude** als vereinfachte, nicht maßstabsgetreue Übertragung der bereitgestellten
  Etagenübersichten (EG und 1. OG, 58 Raumflächen),
- das **Rote Gebäude (01)** mit Keller, 1.–3. OG und Dachgeschoss (92 Raumflächen),
- das **Grüne Gebäude (02)** mit Keller, EG sowie 1.–2. OG (87 Raumflächen),
- das **Weiße Gebäude (03)** mit EG sowie 1.–2. OG (55 Raumflächen).

Plangrundlage aller vier Gebäude: **Hochschule Anhalt**. Die SVG-Umsetzungen wurden für dieses
Projekt selbst erstellt. Die Bearbeitung und öffentliche Verwendung der Grundlagen wurden
bestätigt.

Schematische Pläne sind keine Flucht-, Rettungs- oder amtlichen Lagepläne. Die sichtbare Aussage
der App wird pro Gebäude über `planKind` gesteuert.

## Inhalt

```text
buildings/ratke-gebaeude/          kanonische Geometriequellen, EG und 1. OG
buildings/koethen-01/              Rotes Gebäude, Keller, 1.–3. OG, Dach
buildings/koethen-02/              Grünes Gebäude, Keller, EG, 1.–2. OG
buildings/koethen-03/              Weißes Gebäude, EG, 1.–2. OG
catalog/campus-map.catalog.json   kanonische strukturierte Quelle
src/
  svg-reader.mjs                  strikter Allowlist-Parser für den genutzten XML-Ausschnitt
  validate.mjs                    Querprüfung Katalog ↔ SVG
  generate.mjs                    erzeugt die App-Assets (rein, deterministisch)
  cli.mjs                         validate | generate | check
```

Erzeugt wird nach `apps/mobile/assets/maps/`: `map_catalog.json` und das bereinigte Etagen-SVG.

## Kommandos

```bash
pnpm --filter @campus/map validate   # Katalog gegen das SVG prüfen
pnpm --filter @campus/map generate   # App-Assets neu schreiben
pnpm --filter @campus/map check      # prüfen und Drift, verwaiste Dateien sowie fehlende pubspec-Einträge melden (CI-Gate)
pnpm --filter @campus/map test       # 62 Tests
```

## Warum dependency-frei

Wie `packages/openapi`: Die Kette von der kanonischen Zeichnung bis zum Asset im App-Bundle soll
vollständig überprüfbar bleiben, ohne dass ein XML-Parser eines Drittanbieters dazwischen steht.
Der Reader ist deshalb eine **Allowlist** — DOCTYPE, CDATA und alles andere, was er nicht
ausdrücklich versteht, wird abgelehnt statt bestmöglich geraten. Damit existiert die
Entity-Expansion-Angriffsfläche gar nicht erst.

## Warum das generierte SVG anders aussieht

Zwei Gründe, beide durch Tests festgehalten:

- Die kanonischen Zeichnungen enthalten **deutsche** Überschriften, Legenden und Beschriftungen.
  Sie bleiben als Bestandteil des jeweiligen Plans im generierten Asset erhalten und werden auch
  bei englischer App-Sprache auf Deutsch angezeigt.
- `flutter_svg` unterstützt **keine** `<style>`-Blöcke und verwirft die gesamte Stylesheet. Die
  CSS-Klassenregeln werden deshalb in Präsentationsattribute aufgelöst; `<marker>` und `marker-*`
  entfallen, weil der Renderer sie ignoriert.

Vollständige Beschreibung inklusive CMS-Sync und Rechteprozess:
[`docs/campus-map.md`](../../docs/campus-map.md).
