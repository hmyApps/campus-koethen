# Bibliothek

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

Der Bereich „Bibliothek“ (Mehr → Campus) ist eine **reine Linkliste**. Die App öffnet öffentliche
Einstiegsseiten der Hochschulbibliothek im Systembrowser und liest dabei **keine** Daten aus ihnen,
sendet nichts dorthin und kennt kein Bibliothekskonto. Er fällt daher nicht unter die direkten
Dienste in AGENTS.md §2.

| Eintrag                           | Adresse                                                       |
| --------------------------------- | ------------------------------------------------------------- |
| Online-Katalog (OPAC)             | `https://opac.lbs-anhalt.gbv.de/DB=1/LNG=DU/`                 |
| Discovery-Suche                   | `https://discovery.hs-anhalt.de/search`                       |
| Elektronische Zeitschriften (EZB) | `https://ezb.uni-regensburg.de/index.phtml?bibid=HSB&lang=de` |
| Bibliothek auf hs-anhalt.de       | `https://www.hs-anhalt.de/hochschulbibliothek`                |

Die Liste steht typisiert in `features/library/domain/library_resource.dart`; alle Adressen müssen
`https` sein (der `SafeLinkLauncher` lässt nichts anderes durch).

## Erweiterungen

Der OPAC ist ein Katalog des Verbunds GBV (`lbs-anhalt.gbv.de`). Suche im Bestand, Leihfristen oder
Verlängerungen **in der App** wären Zugriffe auf einen Drittanbieter und brauchen vorher: eine
dokumentierte Schnittstelle des Betreibers, eine Klärung der Nutzungsbedingungen und eine
ausdrückliche Ergänzung der Ausnahmen in AGENTS.md §2. Bis dahin bleibt es bei Links.
