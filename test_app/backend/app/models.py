from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Enum,
    ForeignKey,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class AppointmentScope(str, enum.Enum):
    """A 'shared' appointment lives on the team calendar; a 'private' one is a
    personal block that only affects its single owner's availability."""

    shared = "shared"
    private = "private"


class RsvpStatus(str, enum.Enum):
    """A participant's response to a shared appointment they were invited to.
    'pending' = invited but hasn't answered yet."""

    pending = "pending"
    yes = "yes"
    no = "no"


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    username: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(100))
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


class Appointment(Base):
    """The canonical appointment. A shared appointment is shown on the team
    calendar; every participant additionally gets a CalendarEntry (their
    private-calendar copy)."""

    __tablename__ = "appointments"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    scope: Mapped[AppointmentScope] = mapped_column(
        Enum(AppointmentScope, name="appointment_scope")
    )
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    entries: Mapped[list[CalendarEntry]] = relationship(
        back_populates="appointment",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class CalendarEntry(Base):
    """One row == one appearance of an appointment in ONE user's private
    calendar. The database enforces (via an EXCLUDE constraint defined in the
    migration) that no two entries for the same user overlap in time. This is
    what makes the 'iff free for all participants' rule atomic and race-free."""

    __tablename__ = "calendar_entries"
    __table_args__ = (
        # An appointment appears at most once in a given user's calendar.
        UniqueConstraint("appointment_id", "user_id", name="uq_entry_appt_user"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    appointment_id: Mapped[int] = mapped_column(
        ForeignKey("appointments.id", ondelete="CASCADE")
    )
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # Denormalised from the appointment so the EXCLUDE constraint can act on a
    # single table. Kept in sync at write time.
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # This participant's RSVP to the appointment.
    response: Mapped[RsvpStatus] = mapped_column(
        Enum(RsvpStatus, name="rsvp_status"),
        default=RsvpStatus.pending,
        server_default=RsvpStatus.pending.value,
    )
    # If the appointment was mirrored into this user's Google calendar, the id
    # of the created Google event (so it can be removed on delete).
    google_event_id: Mapped[str | None] = mapped_column(String(256), nullable=True)

    # `time_range` (tstzrange) is a STORED generated column created in the
    # migration; the no-overlap EXCLUDE constraint is defined on it. It is not
    # mapped here because it is fully database-managed.

    appointment: Mapped[Appointment] = relationship(back_populates="entries")


class CalendarConnection(Base):
    """A user's link to an external calendar provider (currently Google). Stores
    the OAuth tokens used to read free/busy and write events on their behalf."""

    __tablename__ = "calendar_connections"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), unique=True
    )
    provider: Mapped[str] = mapped_column(String(20), default="google")
    access_token: Mapped[str] = mapped_column(Text)
    refresh_token: Mapped[str | None] = mapped_column(Text, nullable=True)
    token_expiry: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    scope: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Notification(Base):
    """An in-app notification for a user (invitation to a shared appointment or
    a participant's RSVP response). Delivered to the client by polling."""

    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    user_id: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    type: Mapped[str] = mapped_column(String(20))  # 'invited' | 'rsvp'
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)
    read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
