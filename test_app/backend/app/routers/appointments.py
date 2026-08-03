from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app import google_calendar as gc
from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import (
    Appointment,
    AppointmentScope,
    CalendarConnection,
    CalendarEntry,
    User,
)
from app.routers.notifications import create_notification
from app.scheduling import suggest_slots
from app.schemas import (
    AppointmentOut,
    ParticipantOut,
    PrivateBlockCreate,
    RsvpRequest,
    SharedAppointmentCreate,
    SuggestedSlot,
    SuggestRequest,
    SuggestResponse,
)

router = APIRouter(prefix="/appointments", tags=["appointments"])

# Postgres SQLSTATE for a violated EXCLUDE constraint.
_EXCLUSION_VIOLATION = "23P01"


def _to_out(appt: Appointment) -> AppointmentOut:
    entries = sorted(appt.entries, key=lambda e: e.user_id)
    return AppointmentOut(
        id=appt.id,
        title=appt.title,
        description=appt.description,
        scope=appt.scope,
        starts_at=appt.starts_at,
        ends_at=appt.ends_at,
        created_by=appt.created_by,
        participants=[
            ParticipantOut(user_id=e.user_id, response=e.response) for e in entries
        ],
        participant_ids=[e.user_id for e in entries],
    )


def _is_overlap_violation(err: IntegrityError) -> bool:
    sqlstate = getattr(err.orig, "sqlstate", None) or getattr(
        err.orig, "pgcode", None
    )
    if sqlstate == _EXCLUSION_VIOLATION:
        return True
    # Fallback: match the constraint name in the message.
    return "no_overlap" in str(err.orig).lower()


async def _conflicting_user_ids(
    db: AsyncSession, user_ids: list[int], starts_at, ends_at
) -> list[int]:
    """Which of `user_ids` already have an entry overlapping [starts_at, ends_at)."""
    rows = await db.scalars(
        select(CalendarEntry.user_id)
        .where(CalendarEntry.user_id.in_(user_ids))
        .where(
            and_(
                CalendarEntry.starts_at < ends_at,
                CalendarEntry.ends_at > starts_at,
            )
        )
        .distinct()
    )
    return list(rows)


async def _gather_busy(db: AsyncSession, user_ids, window_start, window_end):
    """Busy intervals of all participants = in-app appointments ∪ Google busy times."""
    intervals: list[tuple] = []

    rows = await db.execute(
        select(CalendarEntry.starts_at, CalendarEntry.ends_at)
        .where(CalendarEntry.user_id.in_(user_ids))
        .where(CalendarEntry.starts_at < window_end)
        .where(CalendarEntry.ends_at > window_start)
    )
    intervals.extend((s, e) for s, e in rows.all())

    if not settings.google_enabled:  # integration disabled → app appointments only
        return intervals

    conns = await db.scalars(
        select(CalendarConnection).where(CalendarConnection.user_id.in_(user_ids))
    )
    for conn in conns:
        try:  # best-effort: a Google failure must not break the suggestion
            token = await gc.valid_access_token(db, conn)
            intervals.extend(await gc.busy_intervals(token, window_start, window_end))
        except Exception:
            pass
    return intervals


async def _mirror_to_google(db: AsyncSession, appt: Appointment) -> None:
    """Write the confirmed shared appointment into connected participants' Google calendars."""
    if not settings.google_enabled:  # integration disabled → skip Google write-back
        return
    user_ids = [e.user_id for e in appt.entries]
    conns = await db.scalars(
        select(CalendarConnection).where(CalendarConnection.user_id.in_(user_ids))
    )
    by_user = {c.user_id: c for c in conns}
    changed = False
    for entry in appt.entries:
        conn = by_user.get(entry.user_id)
        if conn is None:
            continue
        try:
            token = await gc.valid_access_token(db, conn)
            entry.google_event_id = await gc.insert_event(
                token, appt.title, appt.description, appt.starts_at, appt.ends_at
            )
            changed = True
        except Exception:
            pass
    if changed:
        await db.commit()


@router.post(
    "",
    response_model=AppointmentOut,
    status_code=status.HTTP_201_CREATED,
    responses={409: {"description": "Slot not free for all participants"}},
)
async def create_shared_appointment(
    payload: SharedAppointmentCreate,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """Book a SHARED appointment for one or more users.

    Succeeds **iff** the slot is free in every referenced user's private
    calendar. The check is enforced atomically by the database's EXCLUDE
    constraint: we insert one CalendarEntry per participant inside a single
    transaction; if any participant is already busy, the constraint aborts the
    whole transaction and we return 409.
    """
    participant_ids = sorted(set(payload.participant_ids))

    # Validate that every referenced user exists.
    found = await db.scalars(select(User.id).where(User.id.in_(participant_ids)))
    found_ids = set(found)
    missing = [uid for uid in participant_ids if uid not in found_ids]
    if missing:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, f"Unknown user id(s): {missing}"
        )

    appt = Appointment(
        title=payload.title,
        description=payload.description,
        scope=AppointmentScope.shared,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        created_by=current.id,
    )
    appt.entries = [
        CalendarEntry(
            user_id=uid,
            starts_at=payload.starts_at,
            ends_at=payload.ends_at,
        )
        for uid in participant_ids
    ]
    db.add(appt)

    try:
        await db.commit()
    except IntegrityError as err:
        await db.rollback()
        if _is_overlap_violation(err):
            conflicting = await _conflicting_user_ids(
                db, participant_ids, payload.starts_at, payload.ends_at
            )
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                {
                    "detail": "Time slot is not free for all referenced users.",
                    "conflicting_user_ids": conflicting,
                },
            )
        raise

    await db.refresh(appt)
    # Mirror the confirmed appointment into connected participants' Google calendars.
    await _mirror_to_google(db, appt)
    # Notify invited participants (except the creator).
    for uid in participant_ids:
        if uid != current.id:
            await create_notification(
                db, uid, "invited", "New invitation",
                f'{current.display_name} invited you to "{appt.title}"')
    return _to_out(appt)


@router.post(
    "/private",
    response_model=AppointmentOut,
    status_code=status.HTTP_201_CREATED,
    responses={409: {"description": "Overlaps an existing entry"}},
)
async def create_private_block(
    payload: PrivateBlockCreate,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """Create a personal block in the caller's own private calendar. This makes
    the caller 'busy' for that window and will block shared bookings."""
    # Capture before any commit/rollback: a rollback expires ORM objects, so
    # reading `current.id` afterwards would trigger a lazy reload (and crash in
    # async context). A plain int is safe to use later.
    user_id = current.id

    appt = Appointment(
        title=payload.title,
        description=payload.description,
        scope=AppointmentScope.private,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        created_by=user_id,
    )
    appt.entries = [
        CalendarEntry(
            user_id=user_id,
            starts_at=payload.starts_at,
            ends_at=payload.ends_at,
        )
    ]
    db.add(appt)

    try:
        await db.commit()
    except IntegrityError as err:
        await db.rollback()
        if _is_overlap_violation(err):
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                {
                    "detail": "This block overlaps an existing entry in your calendar.",
                    "conflicting_user_ids": [user_id],
                },
            )
        raise

    await db.refresh(appt)
    return _to_out(appt)


@router.post("/suggest", response_model=SuggestResponse)
async def suggest(
    payload: SuggestRequest,
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """Suggest the earliest free slots for all participants, taking into account
    both in-app appointments and busy times from connected Google calendars."""
    participant_ids = sorted(set(payload.participant_ids))
    busy = await _gather_busy(
        db, participant_ids, payload.window_start, payload.window_end
    )
    slots = suggest_slots(
        busy,
        duration=timedelta(minutes=payload.duration_minutes),
        window_start=payload.window_start,
        window_end=payload.window_end,
        work_start_hour=payload.work_start_hour,
        work_end_hour=payload.work_end_hour,
    )
    return SuggestResponse(
        slots=[SuggestedSlot(starts_at=s, ends_at=e) for s, e in slots]
    )


@router.get("/shared", response_model=list[AppointmentOut])
async def shared_calendar(
    db: AsyncSession = Depends(get_db),
    _: User = Depends(get_current_user),
):
    """The team calendar: all shared appointments."""
    appts = await db.scalars(
        select(Appointment)
        .where(Appointment.scope == AppointmentScope.shared)
        .order_by(Appointment.starts_at)
    )
    return [_to_out(a) for a in appts]


@router.get("/me", response_model=list[AppointmentOut])
async def my_calendar(
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """The caller's private calendar: every appointment (shared or private) in
    which they are a participant."""
    appts = await db.scalars(
        select(Appointment)
        .join(CalendarEntry, CalendarEntry.appointment_id == Appointment.id)
        .where(CalendarEntry.user_id == current.id)
        .order_by(Appointment.starts_at)
    )
    return [_to_out(a) for a in appts.unique()]


@router.post("/{appointment_id}/response", response_model=AppointmentOut)
async def respond_to_appointment(
    appointment_id: int,
    payload: RsvpRequest,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    """Set the caller's RSVP (yes / no / pending) for an appointment they were
    invited to. Only a participant of the appointment may respond."""
    entry = await db.scalar(
        select(CalendarEntry).where(
            CalendarEntry.appointment_id == appointment_id,
            CalendarEntry.user_id == current.id,
        )
    )
    if entry is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "You are not a participant of this appointment.",
        )
    entry.response = payload.response
    await db.commit()

    appt = await db.get(Appointment, appointment_id)
    await db.refresh(appt)

    # Notify the appointment creator about the response (unless they are responding themselves).
    if appt.created_by != current.id:
        verb = {"yes": "is going", "no": "is not going"}.get(
            payload.response.value, "updated their response"
        )
        await create_notification(
            db, appt.created_by, "rsvp", "RSVP update",
            f'{current.display_name} {verb} to "{appt.title}"')

    return _to_out(appt)


@router.delete("/{appointment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_appointment(
    appointment_id: int,
    db: AsyncSession = Depends(get_db),
    current: User = Depends(get_current_user),
):
    appt = await db.get(Appointment, appointment_id)
    if appt is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Appointment not found")
    if appt.created_by != current.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Only the creator can delete this appointment"
        )

    # Best-effort: remove mirrored events from participants' Google calendars.
    mirrored = [(e.user_id, e.google_event_id) for e in appt.entries
                if e.google_event_id]
    if mirrored:
        conns = await db.scalars(
            select(CalendarConnection).where(
                CalendarConnection.user_id.in_([uid for uid, _ in mirrored])
            )
        )
        by_user = {c.user_id: c for c in conns}
        for uid, event_id in mirrored:
            conn = by_user.get(uid)
            if conn is None:
                continue
            try:
                token = await gc.valid_access_token(db, conn)
                await gc.delete_event(token, event_id)
            except Exception:
                pass

    await db.delete(appt)  # CalendarEntry rows cascade.
    await db.commit()
