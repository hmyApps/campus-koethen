# Redaktionsleitfaden

Campus Köthen App · für Redaktion und Herausgeber:innen im Strapi-Admin

---

## 0. Grundregeln

Diese Punkte sind nicht verhandelbar — sie schützen das Projekt rechtlich.

| Regel                                                                                                        | Warum            |
| ------------------------------------------------------------------------------------------------------------ | ---------------- |
| **Eigene Texte** oder **eigene Zusammenfassungen mit Quellenlink**. Niemals fremde Volltexte übernehmen.     | Urheberrecht     |
| Nur **eigene oder nachweislich freigegebene Bilder**. Keine Pressefotos, keine Bilder von fremden Webseiten. | Urheberrecht     |
| **Keine erfundenen** Personen, Telefonnummern, E-Mail-Adressen oder offiziellen Aussagen.                    | Wahrheitspflicht |
| Personenbezogene Daten und Fotos nur **mit Einwilligung** der Person.                                        | DSGVO            |
| Die App ist **unabhängig und inoffiziell**. Nie im Namen der Hochschule sprechen.                            | Projektidentität |

> Campus Köthen ist eine unabhängige, inoffizielle Campus-App. Sie wird weder von
> der Hochschule Anhalt entwickelt oder betrieben noch von ihr offiziell
> unterstützt.

Formulierungen wie „offizielle App“, „HSA-App“ oder „die Hochschule teilt mit“
sind unzulässig. Hochschul- und Einrichtungsnamen dürfen **sachlich** genannt
werden („Quelle: Hochschule Anhalt“).

## 1. Rollen

| Rolle              | Darf                                                       |
| ------------------ | ---------------------------------------------------------- |
| **Redaktion**      | Entwürfe anlegen und bearbeiten, **nicht** veröffentlichen |
| **Herausgeber:in** | zusätzlich veröffentlichen und zurückziehen                |
| **Super-Admin**    | zusätzlich Rollen, Content-Types und Tokens verwalten      |

Zum Start genügt **ein manuell angelegter Super-Admin**. Es gibt kein Seed-Konto
und kein Standardpasswort im Repository.

**Kein Sammel-Account.** Jede Person bekommt einen eigenen Zugang, damit
nachvollziehbar bleibt, wer was veröffentlicht hat. Einladungen per E-Mail
funktionieren erst, wenn SMTP eingerichtet ist (offenes Release-Gate) — bis
dahin legt der Super-Admin Konten direkt an.

## 2. Zweisprachigkeit

Alle übersetzbaren Inhalte werden in **Deutsch und Englisch** gepflegt. Deutsch
ist die Standardsprache und der Fallback. Eigennamen wie der Name eines
Kanals bleiben bewusst in beiden Sprachfassungen identisch.

Oben rechts im Editor wird die Locale umgeschaltet. Wichtig:

- **Der `slug` ist bewusst nicht übersetzbar.** Er ist dieselbe stabile Kennung
  in beiden Sprachen. Genau daran erkennt die App einen Kanal oder Beitrag wieder.
- **Der Name eines Kanals ist ein Eigenname** und ebenfalls nicht
  übersetzbar. Nur seine Beschreibung erhält eine englische Fassung.
- Fehlt eine englische Fassung, liefert die API den deutschen Text und markiert
  ihn ehrlich als `translationFallback`. Der Beitrag verschwindet **nicht**.
- **Nie maschinell übersetzen lassen und als eigene Übersetzung ausgeben.**
  Lieber kein Englisch als ein falsches Englisch.

## 3. Kanal anlegen

`Content Manager → Channel → Create new entry`

| Feld                | Hinweis                                                       |
| ------------------- | ------------------------------------------------------------- |
| `name`              | Eigenname, in allen Sprachen identisch                        |
| `slug`              | **stabil**, klein, mit Bindestrichen, z. B. `campus-news`     |
| `description`       | übersetzbar; benennt, wer hier publiziert                     |
| `colorHex`          | `#RRGGBB`                                                     |
| `sortOrder`         | kleinere Zahl steht weiter oben                               |
| `isActive`          | sichtbar in der App                                           |
| `defaultSubscribed` | beim **ersten** Auftauchen automatisch abonniert              |
| `publicCalendar`    | optional, 1:1-Zuordnung zu einem öffentlichen Google-Kalender |

Ein neuer Kanal erscheint **ohne App-Update und ohne Code-Änderung**. Vor der
Veröffentlichung die englische Beschreibung ergänzen und beide Sprachfassungen
prüfen.

> `defaultSubscribed` wirkt pro Kanal **genau einmal** — beim ersten Mal, wenn
> die App den Slug sieht. Wer den Kanal danach abwählt, behält das. Ein
> nachträgliches Umschalten holt niemanden zurück.

### Kanal stilllegen

**`isActive` auf `false` setzen — niemals den `slug` ändern.** Der Slug ist die
gespeicherte Kennung auf jedem Gerät. Wird er geändert, verlieren alle
Abonnent:innen ihre Auswahl, und alte Beiträge hängen an einer Kennung, die es
nicht mehr gibt.

## 4. Tag anlegen

`Content Manager → Tag → Create new entry`

| Feld       | Hinweis                                                     |
| ---------- | ----------------------------------------------------------- |
| `name`     | übersetzbar, z. B. „News“ oder „Event“                      |
| `slug`     | **stabil**, klein, mit Bindestrichen, z. B. `news`, `event` |
| `isActive` | sichtbar in der App                                         |

Ein neuer Tag erscheint **ohne App-Update und ohne Code-Änderung**. Vor der
Veröffentlichung die englische Fassung ergänzen. Zum Start sind mindestens
`news` und `event` in Deutsch und Englisch angelegt.

**Tag stilllegen:** **`isActive` auf `false` setzen — niemals den `slug`
ändern**, aus denselben Gründen wie beim Kanal. Ein deaktivierter oder
gelöschter Tag löscht **keine** Beiträge — er verschwindet nur aus deren
Tag-Liste.

## 5. Beitrag schreiben und veröffentlichen

`Content Manager → Post → Create new entry`

| Feld                      | Hinweis                                                                              |
| ------------------------- | ------------------------------------------------------------------------------------ |
| `title`                   | übersetzbar                                                                          |
| `slug`                    | stabil, nicht übersetzbar; reservierte Slugs (`channels`, `tags`, `events`) verboten |
| `tag`                     | **Pflichtfeld**, genau ein Tag (z. B. `news` oder `event`)                           |
| `primaryChannel`          | **Pflichtfeld**, Hauptkanal; wird automatisch in `channels` synchronisiert           |
| `channels`                | mindestens `primaryChannel`, gern weitere Kanäle                                     |
| `content`                 | Rich Text                                                                            |
| `eventStart`, `eventEnd`  | **Pflicht** bei Tag `event` (`eventStart`), `eventEnd` muss nach `eventStart` liegen |
| `eventAllDay`             | Ganztägig-Schalter für Termine                                                       |
| `sourceName`, `sourceUrl` | Pflicht bei jeder Zusammenfassung fremder Inhalte; `sourceUrl` muss `https://` sein  |
| `heroImage`               | optional, nur eigene/freigegebene Bilder                                             |
| `validFrom`, `validUntil` | optionales Zeitfenster                                                               |

Ein Beitrag in **mehreren** Kanälen erscheint in der App trotzdem **nur einmal**.

**Unterstützte Inhaltsblöcke:** Absatz, Überschrift, Liste, Zitat, Link, Bild.
Andere Blocktypen werden von der API entfernt, damit die Detailseite nicht
zerbricht — sie erscheinen in der App also **gar nicht**. Links sind auf
`https:`, `mailto:` und `tel:` beschränkt.

**Ablauf für alle redaktionellen Content-Types:** Redaktion legt an → `Save`
(Entwurf) → Herausgeber:in prüft → `Publish`. **Entwürfe sind über die API nicht
sichtbar.** Jede Locale besitzt ihren eigenen Veröffentlichungsstatus; vor dem
Publish deshalb Deutsch und Englisch separat prüfen und veröffentlichen.

## 6. Kontaktbereiche und Personen

`Content Manager → Contact Area`

Ein Bereich ist **auch ganz ohne Kontaktperson gültig und in der App voll
nutzbar** — SSC oder Studentenwerk sind Anlaufstellen, keine Einzelpersonen.
Funktionale Kontakte sind Personen ausdrücklich vorzuziehen.

| Feld                                                                 | Hinweis                                                                                                    |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `name`, `shortDescription`, `description`, `address`, `openingHours` | übersetzbar                                                                                                |
| `slug`                                                               | stabil                                                                                                     |
| `iconKey`                                                            | Auswahl aus den von der App unterstützten Kategorien                                                       |
| `site`                                                               | Standort: Köthen, Bernburg oder Dessau. Die App zeigt den eigenen Standort zuerst; ohne Angabe gilt Köthen |
| `generalEmail`, `phone`, `website`, `appointmentBookingUrl`          | alle optional und validiert                                                                                |
| `persons`                                                            | optional, mehrfach                                                                                         |

**Leere Felder bleiben leer.** Die App blendet sie aus; sie erfindet nichts und
zeigt keine leeren Zeilen. Lieber kein Telefon als eine geratene Nummer.

Eine Person kann **mehreren Bereichen** zugeordnet sein und wird trotzdem nur
einmal gepflegt. `isActive: false` blendet sie überall aus, ohne Daten zu
löschen.

Auch Kontaktbereiche, Kontaktpersonen und Autor:innen durchlaufen den
Entwurfs- und Veröffentlichungsablauf. Ein bloßes `Save` ändert noch nichts in
der App.

## 7. Räume (Lageplan)

Räume sind **technische Referenzdaten** und werden nicht von Hand angelegt. Der Lageplan enthält
freigegebene, vereinfachte und nicht maßstabsgetreue Gebäudepläne. Die Plangrundlage wird pro
Gebäude in der App ausgewiesen; die SVG-Umsetzungen stammen aus dem Projekt. Die Karten sind keine
Flucht-, Rettungs- oder amtlichen Gebäudepläne.

**Was du bearbeiten kannst:**

| Feld                              | Bedeutung                                                                   |
| --------------------------------- | --------------------------------------------------------------------------- |
| `displayNameDe` / `displayNameEn` | optionaler sprechender Name statt der reinen Nummer, z. B. „Großer Hörsaal" |
| `descriptionDe` / `descriptionEn` | optionale kurze Beschreibung                                                |
| `isVisible`                       | Raum aus der App ausblenden, ohne den Katalog anzufassen                    |
| `contactPersons` / `contactAreas` | Räume mit Ansprechpartnern und Bereichen verknüpfen                         |

**Was du nicht ändern kannst — und warum:** `roomKey`, `roomNumber`, Gebäude, Etage, `roomType`,
`mapVersion`, `sortOrder` und `catalogActive` gehören zum Kartenkatalog. Sie müssen exakt zur
gezeichneten Geometrie passen, sonst würde die App den falschen Raum markieren. Der Server lehnt
Änderungen daran ab und ignoriert sie beim Speichern — das ist kein Fehler, sondern Absicht.
Räume anlegen oder löschen ist aus demselben Grund gesperrt.

Verschwindet ein Raum aus dem Katalog, wird er **deaktiviert, nicht gelöscht**: deine Texte und
Verknüpfungen bleiben erhalten und leben wieder auf, falls der Raum zurückkehrt.

Braucht ihr einen neuen Raum, eine Etage oder ein Gebäude, wendet euch an die Entwicklung — das ist
eine Änderung an der Karte, kein CMS-Vorgang.

## 8. Häufige Fehler

| Fehler                                 | Folge                                      |
| -------------------------------------- | ------------------------------------------ |
| `slug` nachträglich geändert           | Abos und Verlinkungen brechen              |
| Kanal gelöscht statt `isActive: false` | Beiträge verlieren ihre Zuordnung          |
| Fremder Volltext kopiert               | Urheberrechtsverstoß                       |
| Bild ohne Rechte hochgeladen           | Urheberrechtsverstoß                       |
| Nur Deutsch gepflegt                   | Englisch fällt sichtbar auf Deutsch zurück |
| Beitrag ohne Kanal                     | erscheint in keiner Liste                  |
| Zusammenfassung ohne `sourceUrl`       | Quelle nicht nachvollziehbar               |
| Entwurf „veröffentlicht“ geglaubt      | nichts sichtbar — `Publish` fehlt          |

## 9. Mensadaten

Mensapläne kommen **automatisch** von `meine-mensa.de` und werden alle zwei
Stunden synchronisiert. Sie sind **nicht** redaktionell und im Admin nicht
bearbeitbar.

- Gerichtsnamen bleiben im deutschen Original und werden **nie** übersetzt.
- Es werden **keine Mensabilder** verwendet.
- Fällt die Quelle aus, bleibt der letzte gültige Stand erhalten und wird in der
  App als veraltet gekennzeichnet. Es verschwindet nichts.

Inhaltliche Fehler im Speiseplan müssen an der Quelle korrigiert werden.
