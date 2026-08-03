from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import google_calendar as gc
from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import CalendarConnection, User

router = APIRouter(prefix="/integrations/google", tags=["integrations"])


@router.get("/connect")
async def connect(user_id: int = Query(..., description="User id to connect")):
    """Return a redirect to the Google consent screen. Opens in the browser.
    (For the demo: `user_id` is passed directly; in production it would go through login.)"""
    if not settings.google_enabled:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Google integration is not configured (see backend/GOOGLE_SETUP.md).",
        )
    return RedirectResponse(gc.build_auth_url(state=str(user_id)))


@router.get("/callback", response_class=HTMLResponse)
async def callback(
    state: str,
    code: str | None = None,
    error: str | None = None,
    db: AsyncSession = Depends(get_db),
):
    if error:
        return HTMLResponse(f"<h3>Connection cancelled: {error}</h3>", status_code=400)
    if not code:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Missing code.")

    user_id = int(state)
    data = await gc.exchange_code(code)

    conn = await db.scalar(
        select(CalendarConnection).where(CalendarConnection.user_id == user_id)
    )
    expiry = datetime.now(timezone.utc) + timedelta(
        seconds=data.get("expires_in", 3600)
    )
    if conn is None:
        conn = CalendarConnection(user_id=user_id, provider="google")
        db.add(conn)
    conn.access_token = data["access_token"]
    # refresh_token is only sent on first consent - don't overwrite an existing one with empty
    if data.get("refresh_token"):
        conn.refresh_token = data["refresh_token"]
    conn.token_expiry = expiry
    conn.scope = data.get("scope")
    await db.commit()

    return HTMLResponse(
        "<html><body style='font-family:sans-serif;text-align:center;"
        "padding-top:60px'><h2>✅ Google Calendar connected</h2>"
        "<p>You can return to the app.</p></body></html>"
    )


@router.get("/status")
async def status_(
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    conn = await db.scalar(
        select(CalendarConnection).where(CalendarConnection.user_id == current.id)
    )
    return {"connected": conn is not None, "provider": "google"}


@router.delete("/disconnect", status_code=status.HTTP_204_NO_CONTENT)
async def disconnect(
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    conn = await db.scalar(
        select(CalendarConnection).where(CalendarConnection.user_id == current.id)
    )
    if conn is not None:
        await db.delete(conn)
        await db.commit()
