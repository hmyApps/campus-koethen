# AGENTS.md Template für SSC-Portal Automation

Dieses Template kann in dein Projektverzeichnis kopiert und angepasst werden.

---

```markdown
# SSC-Portal Automation für Hochschule Anhalt

## 🎯 Automatisierungsziele

- [ ] Automatisches Login ins SSC-Portal
- [ ] Navigation zu Studienservice → Kontaktdaten
- [ ] Extraktion aller Kontaktdaten
- [ ] Export als JSON/CSV
- [ ] Periodische Backups der Studentendaten

## 📚 Kontext für Claude

**Portal**: HISinOne SSC Hochschule Anhalt (https://sscportal.ssc.hs-anhalt.de)

**Besonderheiten**:
- JSF-basiert mit PrimeFaces-ähnlichen Komponenten
- Tab-Navigation via Submit-Buttons (nicht Links)
- Alle Tabs haben eindeutige Button-IDs (`*_TabBtn`)
- Session-basiert, keine API

### Tab-Button IDs
```
- Meine Studiengänge:       studyserviceForm:stgStudent_TabBtn
- Kontaktdaten:             studyserviceForm:newContactData_TabBtn
- Zahlungen:                studyserviceForm:billsAndPayment_TabBtn
- Bescheide/Bescheinigungen: studyserviceForm:billsAndPayment_TabBtn
- Persönliche Einwilligungen: ...weitere
```

## 🤖 Agent-Workflows

### 1. Data Extraction Agent
**Purpose**: Extrahiert Kontaktdaten von der Studienservice-Seite

**Input**: 
- Portal-URL (nach Login)
- Gewünschte Adresstypen (oder alle)

**Output**:
- Strukturiertes JSON mit Kontaktdaten
- Verifizierungsstatus von E-Mails
- Typ-Labels (Heimat, Privat, Mobiltelefon, etc.)

**Tools**:
- Selenium/Playwright für Navigation
- BeautifulSoup/Cheerio zum Parsen
- Siehe: `ssc_parser.py` oder `ssc_parser.js`

**Prozess**:
```
1. Login (Credentials aus Umgebung)
2. Navigate zu Studienservice (POST mit Tab-Button-ID)
3. Click "Kontaktdaten" Button (ID: studyserviceForm:newContactData_TabBtn)
4. Wait für [role="tabpanel"] zu laden
5. Parse mit SSCPortalParser
6. Return JSON
```

### 2. Comparison Agent
**Purpose**: Vergleicht aktuelle mit gespeicherten Kontaktdaten

**Input**:
- Aktuelle Daten (von Data Extraction Agent)
- Gespeicherte Daten (von letztem Run)

**Output**:
- Change Report (neue/geänderte/gelöschte Felder)
- Diff mit Farben
- Alert wenn kritische Felder sich ändern

### 3. Backup Agent
**Purpose**: Speichert Kontaktdaten regelmäßig

**Input**:
- Extrahierte Daten
- Backup-Verzeichnis

**Output**:
- Datei: `kontaktdaten_YYYY-MM-DD.json`
- Versionshistorie

## 🔧 Selenium Setup (Python)

```python
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
import os

class SSCPortalAgent:
    def __init__(self):
        self.driver = webdriver.Chrome()
        self.wait = WebDriverWait(self.driver, 10)
        
    def login(self, username: str, password: str):
        """Login ins Portal"""
        self.driver.get("https://sscportal.ssc.hs-anhalt.de/qisserver")
        
        # Finde Login-Felder
        user_input = self.wait.until(
            EC.presence_of_element_located((By.ID, "username"))
        )
        pass_input = self.driver.find_element(By.ID, "password")
        
        user_input.send_keys(username)
        pass_input.send_keys(password)
        
        # Submit
        login_btn = self.driver.find_element(By.XPATH, "//button[contains(text(), 'Anmelden')]")
        login_btn.click()
        
        # Warte auf Seite zu laden
        self.wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "[role='main']")))
        
    def goto_studienservice(self):
        """Navigate zu Studienservice"""
        url = "https://sscportal.ssc.hs-anhalt.de/qisserver/pages/cm/stu/studyService/start.xhtml?_flowId=studyservice-flow"
        self.driver.get(url)
        
        self.wait.until(
            EC.presence_of_element_located((By.ID, "studyserviceForm:newContactData_TabBtn"))
        )
        
    def click_kontaktdaten_tab(self):
        """Klicke Kontaktdaten Tab"""
        btn = self.driver.find_element(By.ID, "studyserviceForm:newContactData_TabBtn")
        btn.click()
        
        # Warte auf Tab-Inhalt
        self.wait.until(
            EC.presence_of_element_located((By.CSS_SELECTOR, "[role='tabpanel']"))
        )
        
    def extract_kontaktdaten(self):
        """Extrahiere Kontaktdaten"""
        from ssc_parser import SSCPortalParser
        
        html = self.driver.page_source
        parser = SSCPortalParser(html)
        return parser.parse()
        
    def close(self):
        self.driver.quit()
```

**Beispiel-Nutzung**:
```python
agent = SSCPortalAgent()
agent.login(
    os.getenv("SSC_USERNAME"),
    os.getenv("SSC_PASSWORD")
)
agent.goto_studienservice()
agent.click_kontaktdaten_tab()
data = agent.extract_kontaktdaten()
agent.close()

print(data)
```

## 🌐 Browser-basierte Alternative (JavaScript)

Wenn du nur die Daten **von einer offenen Seite** extrahieren möchtest:

```javascript
// In Browser-Konsole auf der Kontaktdaten-Seite:
<script src="ssc_parser.js"></script>

SSCParser.summary()           // Übersicht
data = SSCParser.parse()      // Komplette Daten
SSCParser.downloadJSON()      // Datei
```

## 📅 Geplante Automatisierungen

### 1. Tägliches Backup
```yaml
Frequenz: Täglich 23:59 Uhr
Agent: Backup Agent
Action: extract + save to `backups/`
Benachrichtigung: Email bei Änderungen
```

### 2. Wöchentlicher Vergleich
```yaml
Frequenz: Montag 08:00 Uhr
Agent: Comparison Agent
Action: extract + compare mit vorheriger Woche
Report: Markdown file `weekly_changes.md`
```

### 3. Monatlicher Export
```yaml
Frequenz: 1. des Monats
Agent: Export Agent
Action: Alle Backups + Metadaten → CSV/Excel
Output: `archiv/kontaktdaten_2026_10.xlsx`
```

## 🔐 Sicherheit

- ✅ Credentials in Umgebungsvariablen
- ✅ Keine Logs mit persönlichen Daten
- ✅ Lokales Backup verschlüsseln wenn möglich
- ✅ Session-Cookies nur für API-Calls nutzen (kein Sharing)

## 📊 Fehlerbehandlung

```python
try:
    agent.login(...)
except TimeoutException:
    print("Login fehlgeschlagen oder Portal nicht erreichbar")
    # Benachrichtige Admin
    
try:
    agent.click_kontaktdaten_tab()
except ElementNotFound:
    print("Tab-Button nicht gefunden - Portal-Layout geändert?")
    # Parst Fehler und benachrichtige
```

## 🚀 Deployment

1. **Development**: Lokal mit Chrome/Chromium
2. **Production**: Mit Headless Chrome in Docker
   ```dockerfile
   FROM python:3.11
   RUN apt-get install chromium-browser
   COPY ssc_parser.py /app/
   COPY agent.py /app/
   CMD python /app/agent.py
   ```

## 📞 Debugging

### Seite lädt nicht
```python
# Screenshot machen
self.driver.save_screenshot("debug.png")

# HTML speichern
with open("debug.html", "w") as f:
    f.write(self.driver.page_source)
```

### Tab funktioniert nicht
```python
# Prüfe ob Button sichtbar
btn = self.driver.find_element(By.ID, "studyserviceForm:newContactData_TabBtn")
print("Button visible:", btn.is_displayed())

# Klick direkt via JavaScript
self.driver.execute_script("arguments[0].click();", btn)
```

### Parser funktioniert nicht
```python
# Prüfe ob tabpanel vorhanden
tabpanel = self.driver.find_element(By.CSS_SELECTOR, "[role='tabpanel']")
print("Tabpanel HTML:", tabpanel.get_attribute("outerHTML")[:500])

# Parse lokal für Debugging
from ssc_parser import SSCPortalParser
parser = SSCPortalParser(self.driver.page_source)
parser._extract_contact_blocks()  # Debugging
```

---

**Version**: 1.0  
**Letzte Aktualisierung**: 2026-10-03
**Getestet**: Hochschule Anhalt HISinOne
```
```

---

## Verwendung

Kopiere den Content oben in dein Projekt als `.github/AGENTS.md` oder `docs/AGENTS.md`.

Passe dann an:
- Deine spezifischen Credentials-Anforderungen
- Deine Scheduling-Anforderungen
- Deine Output-Formate

Dann kann jeder Agent in deinem Team die Richtlinien für Portal-Automatisierung befolgen.
