from fastapi import APIRouter, Depends, status
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import Notification, User
from app.schemas import NotificationOut

router = APIRouter(prefix="/notifications", tags=["notifications"])


async def create_notification(
    db: AsyncSession, user_id: int, type_: str, title: str, body: str
) -> None:
    """Create a notification for a user. Best-effort; commits itself."""
    db.add(Notification(user_id=user_id, type=type_, title=title, body=body))
    await db.commit()


@router.get("", response_model=list[NotificationOut])
async def list_notifications(
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """The current user's notifications, newest first."""
    rows = await db.scalars(
        select(Notification)
        .where(Notification.user_id == current.id)
        .order_by(Notification.id.desc())
        .limit(50)
    )
    return list(rows)


@router.post("/read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_all_read(
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    await db.execute(
        update(Notification)
        .where(Notification.user_id == current.id, Notification.read == False)  # noqa: E712
        .values(read=True)
    )
    await db.commit()
