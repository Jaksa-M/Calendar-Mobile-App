"""Thin Google Calendar client over REST (no heavy libraries).

Covers: the OAuth flow (auth URL, code exchange, token refresh), reading
busy times (FreeBusy), and inserting/deleting events."""
from __future__ import annotations

import urllib.parse
from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import CalendarConnection

AUTH_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
FREEBUSY_ENDPOINT = "https://www.googleapis.com/calendar/v3/freeBusy"
EVENTS_ENDPOINT = "https://www.googleapis.com/calendar/v3/calendars/primary/events"

SCOPES = (
    "https://www.googleapis.com/auth/calendar.readonly "
    "https://www.googleapis.com/auth/calendar.events"
)


def build_auth_url(state: str) -> str:
    params = {
        "client_id": settings.google_client_id,
        "redirect_uri": settings.google_redirect_uri,
        "response_type": "code",
        "scope": SCOPES,
        "access_type": "offline",
        "prompt": "consent",  # always return a refresh_token
        "include_granted_scopes": "true",
        "state": state,
    }
    return f"{AUTH_ENDPOINT}?{urllib.parse.urlencode(params)}"


async def exchange_code(code: str) -> dict:
    """Exchange the authorization code for tokens."""
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            TOKEN_ENDPOINT,
            data={
                "code": code,
                "client_id": settings.google_client_id,
                "client_secret": settings.google_client_secret,
                "redirect_uri": settings.google_redirect_uri,
                "grant_type": "authorization_code",
            },
        )
    resp.raise_for_status()
    return resp.json()


async def _refresh(refresh_token: str) -> dict:
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            TOKEN_ENDPOINT,
            data={
                "refresh_token": refresh_token,
                "client_id": settings.google_client_id,
                "client_secret": settings.google_client_secret,
                "grant_type": "refresh_token",
            },
        )
    resp.raise_for_status()
    return resp.json()


async def valid_access_token(db: AsyncSession, conn: CalendarConnection) -> str:
    """Return a valid access token, refreshing it if needed."""
    now = datetime.now(timezone.utc)
    if conn.token_expiry - timedelta(seconds=60) > now:
        return conn.access_token
    if not conn.refresh_token:
        return conn.access_token  # no refresh token - try the existing one
    data = await _refresh(conn.refresh_token)
    conn.access_token = data["access_token"]
    conn.token_expiry = now + timedelta(seconds=data.get("expires_in", 3600))
    await db.commit()
    return conn.access_token


async def busy_intervals(
    access_token: str, time_min: datetime, time_max: datetime
) -> list[tuple[datetime, datetime]]:
    """Return a list of (start, end) busy intervals from the primary calendar."""
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            FREEBUSY_ENDPOINT,
            headers={"Authorization": f"Bearer {access_token}"},
            json={
                "timeMin": _rfc3339(time_min),
                "timeMax": _rfc3339(time_max),
                "items": [{"id": "primary"}],
            },
        )
    resp.raise_for_status()
    cal = resp.json().get("calendars", {}).get("primary", {})
    out = []
    for b in cal.get("busy", []):
        out.append(
            (
                datetime.fromisoformat(b["start"].replace("Z", "+00:00")),
                datetime.fromisoformat(b["end"].replace("Z", "+00:00")),
            )
        )
    return out


async def insert_event(
    access_token: str, title: str, description: str | None,
    start: datetime, end: datetime,
) -> str:
    """Insert an event into the primary calendar; return its id."""
    async with httpx.AsyncClient(timeout=15) as client:
        resp = await client.post(
            EVENTS_ENDPOINT,
            headers={"Authorization": f"Bearer {access_token}"},
            json={
                "summary": title,
                "description": description or "",
                "start": {"dateTime": _rfc3339(start)},
                "end": {"dateTime": _rfc3339(end)},
            },
        )
    resp.raise_for_status()
    return resp.json()["id"]


async def delete_event(access_token: str, event_id: str) -> None:
    async with httpx.AsyncClient(timeout=15) as client:
        await client.delete(
            f"{EVENTS_ENDPOINT}/{event_id}",
            headers={"Authorization": f"Bearer {access_token}"},
        )


def _rfc3339(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
