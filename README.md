# Calendar Mobile App

A calendar for a group of people. Everyone has a private calendar, and there is one shared calendar for the team. A shared appointment can be booked only if every invited person is free at that time.

The app is written in Flutter. The backend is FastAPI on top of PostgreSQL.

## Features

- registration and login (JWT)
- a private calendar and the shared team calendar
- creating a shared appointment with any number of participants, or a private block just for yourself
- suggestions for the earliest slot when everyone is free
- accepting or declining an invitation
- optional Google Calendar connection: Google busy times count when checking availability, and confirmed appointments are written back to Google
- in-app notifications and local reminders before an appointment

## How double booking is prevented

Checking in application code whether everyone is free is not enough, because two requests can pass the check at the same moment and both get saved. So the rule lives in the database instead.

Every participant of an appointment gets a row in `calendar_entries` with a time range, and the table has this constraint:

```sql
EXCLUDE USING gist (user_id WITH =, time_range WITH &&)
```

One user can never have two overlapping entries. Booking inserts all the rows in a single transaction, so if one participant is busy the whole booking fails and the API returns `409`.

## Layout

All code is in `test_app/`:

```
lib/         Flutter app (api, models, screens, state)
backend/
  app/       FastAPI application (routers, models, scheduling, Google client)
  alembic/   database migrations
```

## Running

**Backend**

You need PostgreSQL 16 and Python 3.12.

```
cd test_app/backend
bash scripts/init_db.sh
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
alembic upgrade head
uvicorn app.main:app --reload
```

The API runs at `http://localhost:8000`, with interactive docs at `/docs`. If you would rather not install Postgres, `docker compose up -d db` starts it in a container.

The Google integration is optional. The steps for setting it up, in Serbian, are in `backend/GOOGLE_SETUP.md`.

**App**

```
cd test_app
flutter pub get
flutter run
```

On the Android emulator the app finds the backend at `10.0.2.2:8000` by itself. On a real phone, pass your computer's address:

```
flutter run --dart-define=API_BASE_URL=http://YOUR-IP:8000
```

## Stack

Flutter, Riverpod, Dio, table_calendar, flutter_local_notifications. FastAPI, SQLAlchemy (async), Alembic, PostgreSQL.
