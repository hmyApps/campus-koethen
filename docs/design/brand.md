# Campus Köthen Designsystem

Dieses Dokument beschreibt das verbindliche Erscheinungsbild der App. Der
Aufbau und die Informationsarchitektur bleiben bestehen; Farben, Typografie,
Icons und Abstände folgen den mitgelieferten Light- und Dark-Mockups.

## Farbe

Die App besitzt genau zwei feste Paletten. Eine frei wählbare Akzentfarbe oder
ein Systemmodus werden nicht angeboten.

Davon getrennt sind semantische **Kalender-Inhaltsfarben**: Nutzer können aus einer zentral
definierten, kontrastgeprüften Palette Farben für Stundenplan, Moodle, gemerkte Events und einzelne
öffentliche Kalender wählen. Das ändert weder die App-Akzentfarbe noch das Light-/Dark-Theme;
Kalendername, Text und Icon bleiben stets zusätzliche, nichtfarbliche Unterscheidungsmerkmale.

| Rolle            | Light     | Dark      |
| ---------------- | --------- | --------- |
| Primär / Beere   | `#C2185B` | `#EC6E9F` |
| Primär gedrückt  | `#97114A` | `#EC6E9F` |
| Primär-Container | `#FBE4EE` | `#511F37` |
| Himmel-Container | `#E0F2FE` | `#15384E` |
| Himmel-Tinte     | `#075985` | `#8ECDF2` |
| Hintergrund      | `#FAF7F8` | `#1B1418` |
| Oberfläche       | `#FDFBFC` | `#251D22` |
| Haupttext        | `#221A1E` | `#F3ECF0` |
| Begleittext      | `#6F6268` | `#A79CA2` |
| Kontur           | `#EADFE4` | `#3A3037` |
| Erfolg           | `#1D7A55` | `#7CC5A0` |
| Fehler           | `#B3261E` | `#E8837B` |

Farbliterale für das App-Theme liegen ausschließlich in
`apps/mobile/lib/core/theme/app_colors.dart`. Oberflächen greifen über
`context.colors` darauf zu. Zustände werden nie allein über Farbe vermittelt.

## Typografie

Die einzige Schriftfamilie ist **Albert Sans**. Sie wird lokal gebündelt und
zur Laufzeit nicht aus dem Netz geladen.

- Screen-Titel: 28/32, Gewicht 800
- Abschnittstitel: Gewicht 700 bis 800
- Fließtext: Gewicht 400
- Labels und Navigation: Gewicht 600
- Eyebrows: 12, Gewicht 700, optisch in Versalien, Laufweite 0,16 em

Die zugänglichen Texte bleiben in normaler Schreibweise; Versalien sind nur
eine visuelle Darstellung.

## Icons

Alle funktionalen Icons stammen aus **Tabler Icons**. Material-Icons werden in
Screens und Komponenten nicht direkt verwendet. Semantische Zuordnungen liegen
zentral in `apps/mobile/lib/core/theme/app_icons.dart`, damit ein Symbol in der
gesamten App dieselbe Bedeutung und Strichsprache behält.

## Form und Raum

- horizontaler Satzspiegel: 24 dp
- Kartenradius: 14 dp
- Karteninnenabstand: 14 bis 18 dp
- Abstand zwischen Karten: 10 bis 14 dp
- Bottom Sheets: 24 dp Radius
- Mindestgröße für Berührziele: 48 dp
- Karten und Eingaben erhalten eine feine Kontur, aber keinen dekorativen
  Schatten

Die Kontur hat zwei Aufgaben, die nicht dieselbe Farbe vertragen. Dekorative
Hairlines an Karten, Bannern und Trennlinien nutzen `Kontur`. Die Begrenzung
eines **Bedienelements** — nicht fokussiertes Eingabefeld, ausgeschalteter
Switch, nicht angehakte Checkbox — nutzt `Begleittext`, weil sie das Einzige
ist, was das Element sichtbar macht, und deshalb 3:1 gegen Oberfläche und
Hintergrund erreichen muss (WCAG 2.1 SC 1.4.11). `Kontur` erreicht 1,3:1 und
darf keine Bedienelementgrenze allein tragen. Abgesichert in
`test/core/theme/theme_contrast_test.dart`.

Der `ScreenHeader` trägt Eyebrow und Titel. Die untere Navigation liegt auf
einer abgegrenzten Oberfläche; der aktive Eintrag verwendet die Beerenfarbe.

## Seitenübergänge und Zurück-Geste

Auf Android, Linux und Windows setzt sich eine Seite auf: acht logische Pixel
Aufwärtsbewegung und eine Deckkraftrampe, die abgehende Seite blendet nur aus.

iOS und macOS behalten bewusst den Cupertino-Übergang. Die interaktive
Zurück-Wischgeste vom linken Rand steckt bei Flutter **im Seitenübergang
selbst**; ein eigener `PageTransitionsBuilder` entfernt sie mit. Die Geste ist
nur aktiv, wenn der umgebende Navigator wirklich eine Seite zurückgehen kann —
unter `StatefulShellRoute` also nie auf einer Tab-Wurzel — und nie, während ein
Übergang noch läuft.

Bei reduzierter Bewegung ist das eine dokumentierte Abweichung: Der Übergang
bleibt bestehen, seine Animationen werden aber stillgelegt. Eine gepushte Seite
erscheint ohne Bewegung und ohne Dauer. Nur die Wischgeste selbst folgt weiter
dem Finger, damit sichtbar bleibt, dass sie begonnen hat und dass ein frühes
Loslassen sie abbricht. Abgesichert in `test/app/app_navigation_test.dart` und
`test/core/theme/design_tokens_test.dart`.

## Theme-Einstellung

In den Einstellungen stehen ausschließlich **Hell** und **Dunkel** zur Wahl.
Alte gespeicherte Werte für den Systemmodus werden auf Hell migriert. Die
frühere Auswahl einer Akzentpalette ist entfernt.

## Zentrale Implementierung

| Datei                               | Inhalt                              |
| ----------------------------------- | ----------------------------------- |
| `core/theme/app_colors.dart`        | feste Light- und Dark-Palette       |
| `core/theme/app_typography.dart`    | Albert-Sans-Typografie              |
| `core/theme/app_icons.dart`         | semantische Tabler-Icon-Zuordnung   |
| `core/theme/app_dimensions.dart`    | Raster, Radien und Strichstärken    |
| `core/theme/app_metrics.dart`       | Abstände und Layoutmaße             |
| `core/theme/app_theme.dart`         | Material-Theme und Komponentenstile |
| `core/widgets/screen_scaffold.dart` | Screen-Gerüst und Kopf              |
| `app/takt_navigation_bar.dart`      | untere Navigation                   |

Neue Screens orientieren sich an den vorhandenen Komponenten und Tokens, auch
wenn für sie kein eigener Mockup-Screenshot vorliegt.
