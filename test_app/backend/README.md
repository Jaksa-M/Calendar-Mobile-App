# Shared Calendar — Backend (FastAPI + PostgreSQL)

Backend for a multi-user calendar. There is one **shared (team) calendar** and a
**private calendar per user**. A shared appointment may reference one or more
users; it is booked **if and only if** the time slot is free in *every*
referenced user's private calendar.

## The key design idea

The "free for all participants" rule is enforced **atomically by the database**,
not by application code. Each user's private-calendar entries live in
`calendar_entries`, which carries a generated `time_range` (`tstzrange`) column
and this constraint:

```sql
EXCLUDE USING gist (user_id WITH =, time_range WITH &&)
```

> No single user may have two entries whose time ranges overlap.

Booking a shared appointment inserts one `calendar_entries` row per participant
inside a single transaction. If *any* participant is already busy, the constraint
aborts the whole transaction → the API returns `409`. This is **race-free**: even
under simultaneous requests, only one overlapping booking can ever commit (proven
by `tests/test_booking.py::test_concurrent_bookings_only_one_wins`).

## Setup (native Postgres via Homebrew)

```bash
# 1. Install (one-time)
brew install postgresql@16 python@3.12
brew services start postgresql@16

# 2. Create databases + role
cd backend
bash scripts/init_db.sh

# 3. Python env + deps
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 4. Config + migrate
cp .env.example .env
alembic upgrade head

# 5. Run
uvicorn app.main:app --reload
```

API docs: http://localhost:8000/docs

### Alternative: Postgres via Docker

```bash
docker compose up -d db
```

## Tests

```bash
source .venv/bin/activate
pytest            # uses the `calendar_test` database
```

## API summary

| Method | Path | Description |
|---|---|---|
| POST | `/auth/register` | Create account, returns JWT |
| POST | `/auth/login` | Log in (OAuth2 password form), returns JWT |
| GET  | `/users` | List users (to pick participants) |
| GET  | `/users/me` | Current user |
| POST | `/appointments` | Book a **shared** appointment (409 if any participant busy) |
| POST | `/appointments/private` | Add a personal block to your own calendar |
| GET  | `/appointments/shared` | The team calendar |
| GET  | `/appointments/me` | Your private calendar |
| DELETE | `/appointments/{id}` | Delete (creator only) |

## Schema

```
users ──< calendar_entries >── appointments
            (one row per participant per appointment;
             EXCLUDE constraint guarantees no per-user overlap)
```
