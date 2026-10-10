# SSC-Portal Kontaktdaten - Tab-Struktur (Rohe HTML-Analyse)

## 🎯 Wichtigste Erkenntnisse

**Die Tab-Buttons sind `<button type="submit">` Elemente mit `onclick` Handler**, nicht Links!

### Tab-Button-IDs gefunden:

```
1. "Meine Studiengänge"       → ID: studyserviceForm:stgStudent_TabBtn
2. "Kontaktdaten" [AKTIV]     → ID: studyserviceForm:newContactData_TabBtn
3. "Zahlungen"                → ID: studyserviceForm:billsAndPayment_TabBtn
4. "Bescheide / Bescheinigungen" → (weitere)
5. "Persönliche Einwilligungen" → (weitere)
```

## 📋 Tab-Button Struktur (aus JavaScript-Analyse)

```javascript
{
  tag: "BUTTON",
  type: "submit",              // ← Wichtig: Submit-Button!
  name: "studyserviceForm:content.5",  // ← JSF Value
  id: "studyserviceForm:newContactData_TabBtn",  // ← Eindeutige ID
  onclick: "HAS_ONCLICK",      // ← Routen-Handler im JavaScript
  form: "studyserviceForm",    // ← Gehört zu dieser Form
  role: "tab",                 // ← ARIA Tab-Rolle
  aria_selected: null,         // ← Kein aria-selected sichtbar
  aria_controls: null
}
```

## 🔍 Mechanismus erklärt

Entgegen der Annahme "fehlendes `_TabBtn`-Element" funktioniert das System so:

1. **Jeder Tab ist ein `<button type="submit">`** mit eindeutiger ID
2. **JSF kennt den aktivierten Tab über das `name` Attribut** (`studyserviceForm:content.5`)
3. **Der `onclick` Handler triggert JavaScript**, das:
   - Die Form ausfüllt (welcher Tab aktiv sein soll)
   - Den Form-Submit auslöst
   - Der Server sendet die neue Tab-Seite zurück
4. **Kein verstecktes `_TabBtn` nötig** — das ist ein älteres JSF-Pattern

## 🛠️ So aktivierst du einen Tab programmatisch

### Mit Selenium (Python):

```python
from selenium.webdriver.common.by import By

# Klick auf Kontaktdaten Tab
contact_data_btn = driver.find_element(By.ID, "studyserviceForm:newContactData_TabBtn")
contact_data_btn.click()

# Oder alle Tabs durchlaufen
tab_ids = [
    "studyserviceForm:stgStudent_TabBtn",
    "studyserviceForm:newContactData_TabBtn",
    "studyserviceForm:billsAndPayment_TabBtn",
    # ... weitere
]

for tab_id in tab_ids:
    btn = driver.find_element(By.ID, tab_id)
    btn.click()
    # Wait & Parse...
```

### Mit Browser-Konsole (JavaScript):

```javascript
// Kontaktdaten Tab aktivieren
const kontaktdatenBtn = document.getElementById('studyserviceForm:newContactData_TabBtn');
kontaktdatenBtn.click();

// Oder: Das onclick-Event direkt
if (kontaktdatenBtn.onclick) {
  kontaktdatenBtn.onclick(new Event('click'));
}
```

### Mit Curl/Browser-Form-Submit:

```
Die Tabs funktionieren nur via Browser-JavaScript.
Mit curl/scraping nicht möglich, da `onclick` Handler erforderlich.
Nutze stattdessen Selenium oder Playwright.
```

## 📊 Vollständige Tab-Liste aus der Seite

| Index | Label                       | Button ID                                 |
| ----- | --------------------------- | ----------------------------------------- |
| 0     | Meine Studiengänge          | `studyserviceForm:stgStudent_TabBtn`      |
| 1     | **Kontaktdaten** (aktiv)    | `studyserviceForm:newContactData_TabBtn`  |
| 2     | Zahlungen                   | `studyserviceForm:billsAndPayment_TabBtn` |
| 3     | Bescheide / Bescheinigungen | (ID folgt)                                |
| 4     | Persönliche Einwilligungen  | (ID folgt)                                |

## 🔄 JSF Form-Values beim Tab-Wechsel

Wenn du einen Tab klickst, wird folgendes übertragen:

```
POST /qisserver/pages/cm/stu/studyService/start.xhtml?_flowId=studyservice-flow

Form Data:
  studyserviceForm:content.5 = "newContactData"  ← Welcher Tab
  studyserviceForm = studyserviceForm            ← Form-ID
  [weitere JSF-Control-IDs...]
```

Das `content.5` ist die interne JSF-Value des Buttons (nicht 100% eindeutig, aber mit der ID kombiniert funktioniert es).

## ⚠️ Warum das Parser-Projekt davon nicht betroffen ist

Der SSC-Parser (`ssc_parser.js`, `ssc_parser.py`) parst die **bereits geladene HTML-Seite** im Browser oder aus einer lokalen HTML-Datei.

Die Tab-Struktur ist **irrelevant** für den Parser, weil:

- ✅ Der Parser nutzt den **Inhalt des aktiven Tabs** (das `[role="tabpanel"]`)
- ✅ Er braucht nicht zu wissen, wie man zwischen Tabs wechselt
- ✅ Du klickst manuell auf "Kontaktdaten" oder navigierst direkt zur URL

Der Parser funktioniert mit jedem Tab-System (klassisch JSF, PrimeFaces, React, Vue, ...), solange die Datenstruktur im tabpanel stimmt.

## 🎓 Fazit

**Das ist ein **typisches PrimeFaces `p:tabView`-Pattern** mit Submit-Buttons statt Links:**

- Jeder Tab-Click löst Form-Submit aus
- Server entscheidet, welcher Tab oben ist
- JavaScript-Handler im `onclick` koordiniert
- Gut für server-seitige Validierung & State-Management

**Für zukünftige Parser-Projekte:**

- Nicht auf Tab-Navigation verlassen (zu portalspezifisch)
- Direkt auf die URLs linken oder JavaScript/Selenium für automatisierte Navigatin nutzen
- Die Daten im tabpanel sind standardisiert genug zum Parsen

---

**Datum**: 2026-10-03
**System**: HISinOne Hochschule Anhalt  
**JSF Framework**: Mit PrimeFaces-ähnlichen Komponenten
