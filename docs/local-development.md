# Lokale Entwicklung

Campus Köthen App · `AGPL-3.0-only`

---

## 1. Werkzeuge

| Werkzeug         | Erwartet                | Prüfen                              |
| ---------------- | ----------------------- | ----------------------------------- |
| Node.js          | 24.21.0 LTS             | `pnpm node:check`                   |
| pnpm             | >= 10                   | `corepack enable && pnpm --version` |
| Docker + Compose | Docker 29.x, Compose v5 | `docker compose version`            |
| Flutter          | stable                  | `flutter doctor -v`                 |

Node 24 ist gewählt, weil es die aktuelle LTS-Linie ist und Strapi 5.56 offiziell
`node >=20.0.0 <=26.x.x` unterstützt. Die exakte Version steht in `.node-version` und `.nvmrc`;
CI und beide Dockerfiles verwenden denselben Patchstand. `package.json` begrenzt die unterstützte
Hauptversion zusätzlich auf 24.x. Ein abweichender lokaler Patchstand bricht die Installation
früh mit einer verständlichen Meldung ab.

## 2. Erststart

```bash
corepack enable
pnpm install --frozen-lockfile
```

### 2.1 Datenbanken

Der lokale Compose-Stack startet **zwei getrennte Datenbanken mit getrennten Rollen** in einer
PostgreSQL-16-Instanz — genau wie auf dem Server.

```bash
cp infrastructure/local/.env.example infrastructure/local/.env
pnpm compose:local:up
docker compose -f infrastructure/local/compose.yaml ps
```

PostgreSQL wird ausschließlich an `127.0.0.1` gebunden, nie an `0.0.0.0`.

### 2.2 Backend

```bash
cp apps/backend/.env.example apps/backend/.env
pnpm --filter @campus/backend prisma:generate
pnpm --filter @campus/backend prisma:migrate:dev
pnpm --filter @campus/backend start:dev
```

| URL                                  | Zweck                         |
| ------------------------------------ | ----------------------------- |
| <http://localhost:3000/health/live>  | Prozess lebt                  |
| <http://localhost:3000/health/ready> | Datenbank + Strapi erreichbar |
| <http://localhost:3000/docs>         | OpenAPI / Swagger UI          |

### 2.3 CMS

```bash
cp apps/cms/.env.example apps/cms/.env
pnpm --filter @campus/cms develop
```

Beim ersten Start unter <http://localhost:1337/admin> einen Super-Admin anlegen. Es gibt **keinen**
vorkonfigurierten Standard-Account und kein Standard-Passwort im Repository.

Danach ein Read-only-API-Token erzeugen und in `apps/backend/.env` als `STRAPI_API_TOKEN`
eintragen. Details: [content-editor-guide.md](content-editor-guide.md).

### 2.4 Seeds

```bash
pnpm --filter @campus/cms seed          # News-Kanäle + Demo-Kontaktbereiche, de + en
pnpm --filter @campus/backend seed:canteens
```

Beide Seeds sind **idempotent** — zweimaliges Ausführen erzeugt keine Duplikate.

### 2.5 Mensadaten

### Stundenplan

Der Stundenplan ist standardmäßig **deaktiviert**. Zum lokalen Ausprobieren in
`apps/backend/.env`:

```dotenv
WEBUNTIS_ENABLED=true
WEBUNTIS_SYNC_ON_BOOT=true
```

Danach den Worker starten. Er löst dann nacheinander Kontext-, Katalog- und Eintragslauf aus.
Der Katalog kostet einen Request, die Einträge **einen einzigen** Request für alle Gruppen.
Die öffentliche Campus-API liefert den synchronisierten Gruppenkatalog
anschließend paginiert (`page`, `pageSize` bis 50) und durchsucht ihn mit
`query` serverseitig. Die App lädt ihn nur im Gruppen-Picker beziehungsweise
Onboarding; Kaltstart und Stundenplan-Refresh verwenden `/timetable/status`
und die einzeln gespeicherte Gruppen-UUID.

Ohne aktiviertes Flag antworten die Endpunkte weiterhin mit `200`, melden aber
`featureEnabled: false` und `dataState: "unavailable"` — die App stellt das als verständlichen
Hinweis dar, nicht als Fehler.

```bash
# Administrativer manueller Sync gegen die echte Quelle
pnpm --filter @campus/backend sync:canteens

# Offline-Variante gegen gespeicherte Fixtures
pnpm --filter @campus/backend sync:canteens -- --fixture
```

Es gibt bewusst **keinen öffentlichen, ungeschützten Sync-Endpunkt**.

### 2.6 Lageplan: Kartenassets und Raumsync

Die Kartenassets sind committet — für einen normalen Start ist **nichts** zu tun. Nach einer
Änderung an der kanonischen Karte:

```bash
# Katalog gegen das kanonische SVG prüfen
pnpm --filter @campus/map validate

# Flutter-Assets neu erzeugen (schreibt nur bei vollständigem Erfolg)
pnpm --filter @campus/map generate

# Prüfen, ob die committeten Assets noch zur Quelle passen — das CI-Gate
pnpm --filter @campus/map check
```

Räume ins CMS übernehmen (Strapi muss lauffähig konfiguriert sein, läuft aber nicht parallel):

```bash
# Zeigt create/update/unchanged/deactivate und schreibt nichts
pnpm --filter @campus/cms rooms:sync -- --dry-run

# Führt den Plan aus; beim ersten Lauf entstehen 60 Demo-Räume
pnpm --filter @campus/cms rooms:sync
```

Der Sync ist idempotent: ein zweiter Lauf meldet 60-mal „unchanged" und schreibt nichts.
Redaktionelle Felder und Kontaktrelationen werden dabei nie überschrieben. Details:
[campus-map.md](campus-map.md).

### 2.7 Flutter

```bash
cd apps/mobile
flutter pub get
flutter gen-l10n
flutter run \
  --dart-define=API_BASE_URL=http://localhost:3000 \
  --dart-define=ALLOW_LOCAL_API=true
```

Lokales HTTP ist nur mit diesem ausdrücklichen Opt-in erlaubt. Ohne
`API_BASE_URL` zeigt auch ein Debug-Build einen Konfigurationsfehler. Für einen
Android-Emulator oder ein per USB verbundenes Testgerät wird der Backend-Port
über ADB auf dessen Loopback-Adresse weitergereicht:

```bash
adb reverse tcp:3000 tcp:3000
flutter run \
  --dart-define=API_BASE_URL=http://localhost:3000 \
  --dart-define=ALLOW_LOCAL_API=true
```

## 3. Qualitätsgates

### 3.1 Isolierte Backend-Testdatenbank

Die Backend-Integrationstests führen `TRUNCATE` aus. Sie verwenden deshalb nie
`campus_app_local`, sondern ausschließlich eine pro Lauf erzeugte Datenbank mit
dem reservierten Namen `campus_app_test_<run-id>`. Der Testhelfer verlangt
zusätzlich `NODE_ENV=test` und die exakte Gleichheit von `DATABASE_URL` und
`TEST_DATABASE_URL`; eine versehentlich geladene DEV- oder PROD-Verbindung wird
vor dem ersten Verbindungsaufbau abgewiesen.

Der folgende Ablauf läuft in einer Bash-Subshell, legt die Datenbank im lokalen
PostgreSQL-Container an und entfernt sie durch den `EXIT`-Trap auch nach einem
fehlgeschlagenen Test. Er setzt ein gemäß `infrastructure/local/.env.example`
erzeugtes URL-sicheres `APP_DB_PASSWORD` voraus.

```bash
(
  set -a
  . infrastructure/local/.env
  set +a

  test_db="campus_app_test_$(date +%s)"
  cleanup_test_db() {
    docker compose --env-file infrastructure/local/.env \
      -f infrastructure/local/compose.yaml exec -T postgres \
      dropdb --username postgres --if-exists --force "$test_db"
  }
  trap cleanup_test_db EXIT INT TERM

  docker compose --env-file infrastructure/local/.env \
    -f infrastructure/local/compose.yaml exec -T postgres \
    createdb --username postgres --owner campus_app "$test_db"

  export NODE_ENV=test
  export DATABASE_URL="postgresql://campus_app:${APP_DB_PASSWORD}@127.0.0.1:${POSTGRES_PORT:-5433}/${test_db}?schema=public"
  export TEST_DATABASE_URL="$DATABASE_URL"

  pnpm --filter @campus/backend exec prisma migrate deploy
  pnpm --filter @campus/backend test
)
```

In CI übernimmt der kurzlebige PostgreSQL-Service dieselbe Isolation; auch dort
sind beide Variablen explizit auf `campus_app_test` gesetzt. Keine Testanleitung
verwendet die normale lokale Entwicklungsdatenbank.

```bash
pnpm install --frozen-lockfile
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm --filter @campus/cms build

cd apps/mobile
flutter gen-l10n
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## 4. Container lokal bauen

```bash
docker build -f apps/cms/Dockerfile -t campus-app-cms:local .
docker build -f apps/backend/Dockerfile -t campus-app-backend:local .
```

Die veröffentlichten Images sind ausschließlich `linux/amd64`. Auf Apple Silicon läuft ein
`--platform linux/amd64`-Build per Emulation und ist deutlich langsamer; der verbindliche
amd64-Nachweis entsteht in `.github/workflows/images.yml`.

## 5. Vollständiger lokaler Stack

```bash
docker compose -f infrastructure/local/compose.yaml --profile full up -d --build
docker compose -f infrastructure/local/compose.yaml ps
./scripts/smoke-test.sh
```

## 6. DEV-Datenbanken zurücksetzen

Der Umbau von `news-article`/`news-channel`/`news-tag` auf `post`/`channel`/`tag`
(`LEVIORA-112`) hat die alten
Strapi-Content-Types **ersatzlos entfernt**. Es gibt bewusst **keine** Migration bestehender
Inhalte und **keinen** Produktionsmigrationspfad — der beschlossene Weg ist ein vollständiger
DEV-Reset. Eine DEV-Instanz, die noch alte Tabellen enthält, läuft sonst in einen undefinierten
Zustand.

Der Reset verwirft **alle** lokalen Inhalte, Uploads und Sync-Zustände. Er gilt ausschließlich für
lokale und DEV-Umgebungen; gegen eine Umgebung mit echten Nutzerdaten wird er nie ausgeführt.

```bash
# 1. Stack stoppen und die Datenvolumes mitentfernen (-v ist der eigentliche Reset).
docker compose -f infrastructure/local/compose.yaml --profile full down -v

# 2. Neu hochfahren: die initdb-Skripte legen beide Datenbanken und Rollen neu an.
docker compose -f infrastructure/local/compose.yaml up -d

# 3. Operatives Schema der Campus API neu aufbauen.
pnpm --filter @campus/backend exec prisma migrate deploy

# 4. Strapi starten; der Bootstrap-Hook legt die Start-Tags `news` und `event`
#    idempotent an. SEED_DEMO_CONTENT=true ergänzt zweisprachige Demo-Inhalte.
pnpm cms:dev
```

Danach einmal `./scripts/smoke-test.sh` gegen den vollständigen Stack laufen lassen: Es prüft unter
anderem, dass `/v1/posts/channels`, `/v1/posts/tags` und `/v1/posts/events` antworten und dass die
beiden Start-Tags vorhanden sind.

## 7. Bekannte Toolchain-Einschränkungen

`flutter gen-l10n`, `dart format`, `flutter analyze` und `flutter test` benötigen **keine** mobile
Plattform-Toolchain und laufen auf jedem Entwicklungsrechner.

Für einen echten Gerätestart gilt zusätzlich:

| Ziel             | Bedarf                                                                                                       |
| ---------------- | ------------------------------------------------------------------------------------------------------------ |
| iOS-Simulator    | vollständiges Xcode aus dem App Store, danach `sudo xcodebuild -runFirstLaunch` und `brew install cocoapods` |
| Android-Emulator | Android SDK **inklusive `cmdline-tools`** sowie `flutter doctor --android-licenses`                          |

Fehlt eine dieser Toolchains, bleiben Analyse und Tests trotzdem vollständig ausführbar; der
Gerätestart ist dann ein dokumentierter Blocker und wird **nicht** als erfolgreich gemeldet.
