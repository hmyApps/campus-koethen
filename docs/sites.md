# Campus-Standorte

Campus Köthen App · `AGPL-3.0-only` · Copyright © 2026 Leviora Studio and Jona Loreen Sommer

Die Hochschule Anhalt hat drei Standorte, die diese App abdeckt: **Köthen**, **Bernburg** und
**Dessau**. Ein Standort entscheidet, was **zuerst** erscheint. Er blendet nichts aus: Wer in Köthen
studiert, isst vielleicht in Dessau.

## 1. Die Wahl

- Im Einrichtungsassistenten gibt es den Schritt „Dein Standort“ (Schritt 3 von 9, direkt nach der
  Begrüßung und vor allem, was er vorbelegt). Es ist eine Einfachauswahl, **nichts ist vorgewählt**,
  und der Schritt lässt sich überspringen.
- In den Einstellungen unter „Standort“ lässt sich die Wahl jederzeit ändern.
- Gespeichert wird sie lokal (`site.preferred.v1`: `koethen`, `bernburg` oder `dessau`). Ohne Wahl
  verhält sich die App wie für Köthen.

## 2. Was sie bewirkt

| Bereich  | Wirkung                                                                                                                                                                                                                           |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mensa    | Die Mensen des eigenen Standorts stehen zuerst und sind in der Auswahl unter einer Standortüberschrift gruppiert (nur, wenn mehr als ein Standort angeboten wird). Ohne eigene Wahl zeigt die App die erste Mensa des Standorts   |
| Lageplan | Beim Öffnen gilt der gewählte Standort. Das Gebäudemenü gruppiert nach Standort; Standorte ohne Pläne sind wählbar und sagen es. Ein verlinkter Raum, ein Gebäude oder ein Stockwerk gewinnt immer und bringt seinen Standort mit |
| Kontakte | Die Bereiche sind nach Standort gegliedert, der eigene zuerst; Überschriften nur, wenn mehr als ein Standort Bereiche hat                                                                                                         |

Eine **von Hand gewählte Mensa** und das **Standardgebäude** der Einstellungen schlagen den Standort.

## 3. Herkunft der Standortangabe

| Quelle          | Feld                                                                 | Fehlt es?                                 |
| --------------- | -------------------------------------------------------------------- | ----------------------------------------- |
| Kartenkatalog   | `siteKey` je Gebäude (`packages/campus-map`, validiert)              | Köthen. Alle bisherigen Pläne sind Köthen |
| Mensen          | `site` in `/v1/canteens` aus `canteens.config.ts` (`siteKey`)        | unbekannt: die App ordnet sie hinten ein  |
| Kontaktbereiche | `site` in `/v1/contacts/areas*` aus dem CMS-Feld `site` (Aufzählung) | Köthen                                    |

Die App kennt keine Standortlisten außerhalb dieser Felder. Ein weiterer Standort ist eine Änderung
am Enum `CampusSite` (App), `CAMPUS_SITES` (Backend) und `SITE_KEYS` (Kartenpaket) zugleich.

## 4. Stand der Daten

- **Mensen:** Dessau (`location_id` 13) und Bernburg (`8`) sind angebunden und liefern echte Pläne.
- **Lagepläne:** nur Köthen. Für Bernburg und Dessau gibt es noch keine freigegebenen Pläne; reale
  Gebäudepläne brauchen nach `docs/campus-map.md` geklärte Herkunft und Veröffentlichungsrechte.
- **Kontakte:** Das CMS-Feld ist neu. Bereits gepflegte Bereiche gelten als Köthen, bis sie neu
  gespeichert werden; Bereiche für Bernburg und Dessau legt die Redaktion an.
