# How to run the project & how it all works

A plain-language guide to the three pieces of this project and the commands to
start them.

## The big picture

The app is made of **three separate programs** that talk to each other:

```
   ┌─────────────────┐        ┌─────────────────┐        ┌──────────────┐
   │  Flutter app    │  HTTP  │  FastAPI server │  SQL   │  PostgreSQL  │
   │  (the phone UI) │ ─────▶ │  (the "brain")  │ ─────▶ │  (the data)  │
   │  Dart           │ ◀───── │  Python         │ ◀───── │  database    │
   └─────────────────┘  JSON  └─────────────────┘        └──────────────┘
        FRONTEND                   BACKEND                    DATABASE
```

1. **Frontend — the Flutter app (Dart).** This is what runs on the phone/emulator.
   It only draws the screens and sends requests like "log me in" or "book this
   appointment". It does **not** store data itself.

2. **Backend — the FastAPI server (Python).** This is the brain. It receives
   requests from the app, checks the rules (e.g. *"is everyone free at this
   time?"*), talks to the database, and sends answers back as JSON. It runs on
   your Mac at `http://localhost:8000`.

3. **Database — PostgreSQL.** This is where all the data actually lives (users,
   appointments). It keeps the data even when everything else is turned off.

The app never talks to the database directly — it always goes through the
backend. That's normal and good: the rules live in one place.

## What you have installed (you do NOT need to download anything else)

Everything is already installed on your Mac via **Homebrew**:

| Piece        | What it is                    | How it's installed            |
|--------------|-------------------------------|-------------------------------|
| PostgreSQL   | The database server           | `brew install postgresql@16`  |
| Python 3.12  | Runs the backend              | `brew install python@3.12`    |
| Flutter      | Builds & runs the app         | (already had it)              |
| Android Studio | Provides the Android emulator | (already had it)            |

> **Do you need a separate "SQL server"?** No. **PostgreSQL _is_ the SQL server.**
> It's already installed and runs quietly in the background as a service. You
> don't open it or look at it directly — the backend does that for you.

## Running it — every time, from scratch

You need **3 things running**, in this order. Use a separate terminal tab for
the two long-running ones.

### Step 1 — Make sure the database is running (once per Mac restart)

PostgreSQL runs as a background service, so usually it's already on. To be sure:

```bash
brew services start postgresql@16
```

This stays running even after you close the terminal (and restarts when you log
in). You rarely need to touch it again.

### Step 2 — Start the backend (Terminal tab 1)

```bash
cd ~/FlutterProjects/test_app/backend
source .venv/bin/activate          # turns on the Python environment
uvicorn app.main:app --reload      # starts the server
```

If by any chance program is running on port 8000, first do this:
```bash
lsof -ti tcp:8000 | xargs kill      # stop whatever is listening on 8000
```

Leave this running. You'll see logs here. The API is now at
`http://localhost:8000` — you can open `http://localhost:8000/docs` in a browser
to see and try every endpoint.

### Step 3 — Start the app (Terminal tab 2)

```bash
# Launch the Android emulator (skip if it's already open in Android Studio):
flutter emulators --launch Pixel_4_XL      # or open it from Android Studio

# Wait ~30–60s for it to fully boot, then:
cd ~/FlutterProjects/test_app
flutter run                                 # picks the running emulator
```

If `flutter run` says "no devices", the emulator just hasn't finished booting —
wait a bit and run it again. To target a specific device:

```bash
flutter devices                 # lists ids, e.g. emulator-5554
flutter run -d emulator-5554
```

While `flutter run` is attached you can press:
- **`r`** = hot reload (apply code changes instantly)
- **`R`** = hot restart
- **`q`** = quit the app

## Stopping everything

- App: press **`q`** in the `flutter run` terminal.
- Backend: press **`Ctrl+C`** in the uvicorn terminal.
- Database (optional, normally leave it on): `brew services stop postgresql@16`

## Logging in

Demo accounts already exist:
- **alice_demo** / `secret1`
- **bob_demo** / `secret1`

Or tap "Create an account" in the app to make your own.

## Connecting the app to the backend

The app needs the right address for the backend ([lib/config.dart](lib/config.dart)):
- **Android emulator** → `http://10.0.2.2:8000` (automatic — `10.0.2.2` is the
  emulator's special name for "the Mac I'm running on"; plain `localhost` would
  mean the emulator itself).
- **Real Android phone** (same Wi-Fi) → run with your Mac's IP:
  `flutter run --dart-define=API_BASE_URL=http://YOUR-MAC-IP:8000`

## Where the data lives & how to peek at it

The data is in a PostgreSQL database named `calendar`. If you ever want to look
at it directly:

```bash
psql calendar                      # opens the database shell
\dt                                # list tables
SELECT * FROM users;               # see users
SELECT * FROM appointments;        # see appointments
\q                                 # quit
```

(`psql` is on the PATH after `eval "$(/opt/homebrew/bin/brew shellenv)"` if it
isn't found.)

## One-time setup (only if you move to a new computer)

You won't need this on this Mac, but for reference / your dissertation, the full
first-time setup is in [backend/README.md](backend/README.md): install Postgres
+ Python, create the database, create the Python environment, and run the
database migrations (`alembic upgrade head`) which build the tables.
