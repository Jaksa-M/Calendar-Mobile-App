# Shared Calendar — Multi-user Calendar App

Dissertation project (assignment #21): a **multi-user calendar** with one shared
(team) calendar and a private calendar per user. An appointment can refer to one
or more users; it is also written into each referenced user's private calendar.
A shared appointment can be booked **if and only if** the slot is free in the
private calendars of *all* referenced users.

```
┌────────────┐     HTTP / JWT      ┌──────────────────┐
│  Flutter   │  ───────────────▶   │   FastAPI (api)  │ ──▶ PostgreSQL
│  (mobile)  │                     │   async / SQLA   │     EXCLUDE constraint
└────────────┘                     └──────────────────┘     = no double-booking
```

- **Frontend:** Flutter + Riverpod + Dio + `table_calendar` (this repo root).
- **Backend:** FastAPI + PostgreSQL — see [backend/](backend/) and its README.

## The core idea

The "free for all participants" rule is enforced **atomically by PostgreSQL**,
not application code. Each user's private-calendar entries carry a time range
and a single constraint guarantees no user can ever overlap themselves:

```sql
EXCLUDE USING gist (user_id WITH =, time_range WITH &&)
```

Booking a shared appointment inserts one entry per participant in one
transaction; if any participant is busy, the whole transaction aborts → `409`.
This is **race-free even under simultaneous requests** (proven by
`backend/tests/test_booking.py::test_concurrent_bookings_only_one_wins`).

## Run it

### 1. Backend

```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload      # http://localhost:8000/docs
```
(First-time setup is in [backend/README.md](backend/README.md). Postgres must be
running: `brew services start postgresql@16`.)

### 2. Flutter app

```bash
flutter run -d macos      # or an iOS/Android device/emulator
```

Notes on the backend URL ([lib/config.dart](lib/config.dart)):
- macOS desktop / iOS simulator → `localhost:8000` (default).
- Android emulator → `10.0.2.2:8000` (handled automatically).
- Physical device → `flutter run --dart-define=API_BASE_URL=http://YOUR-LAN-IP:8000`.

Demo accounts already seeded: `alice_demo` / `bob_demo`, password `secret1`.

## Project layout

```
test_app/
├── lib/                 Flutter app
│   ├── api/             Dio client + auth/appointment APIs
│   ├── models/          User, Appointment
│   ├── state/           Riverpod providers + auth controller
│   └── screens/         login, register, home (tabs), create appointment
└── backend/
    ├── app/             FastAPI app (models, routers, auth, config)
    ├── alembic/         migrations (incl. the EXCLUDE constraint)
    └── tests/           booking + concurrency tests
```
