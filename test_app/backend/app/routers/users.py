from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_user
from app.models import User
from app.schemas import UserOut

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserOut])
async def list_users(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """All users — used by the client to pick participants for an appointment."""
    users = await db.scalars(select(User).order_by(User.display_name))
    return list(users)


@router.get("/me", response_model=UserOut)
async def me(current: User = Depends(get_current_user)):
    return current
