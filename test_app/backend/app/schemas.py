from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.models import AppointmentScope, RsvpStatus


# --- Auth / users ---
class UserCreate(BaseModel):
    username: str = Field(min_length=3, max_length=50)
    display_name: str = Field(min_length=1, max_length=100)
    password: str = Field(min_length=6, max_length=128)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    username: str
    display_name: str


class LoginRequest(BaseModel):
    username: str
    password: str


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


# --- Appointments ---
class _TimeWindow(BaseModel):
    starts_at: datetime
    ends_at: datetime

    @field_validator("ends_at")
    @classmethod
    def _end_after_start(cls, v: datetime, info):
        start = info.data.get("starts_at")
        if start is not None and v <= start:
            raise ValueError("ends_at must be after starts_at")
        return v


class SharedAppointmentCreate(_TimeWindow):
    title: str = Field(min_length=1, max_length=200)
    description: str | None = None
    # The users this appointment refers to (must be non-empty).
    participant_ids: list[int] = Field(min_length=1)


class PrivateBlockCreate(_TimeWindow):
    """A personal block in the caller's own private calendar."""

    title: str = Field(min_length=1, max_length=200)
    description: str | None = None


class ParticipantOut(BaseModel):
    user_id: int
    response: RsvpStatus


class AppointmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str | None
    scope: AppointmentScope
    starts_at: datetime
    ends_at: datetime
    created_by: int
    # Each invited user plus their RSVP.
    participants: list[ParticipantOut]
    # Kept for convenience / backwards compatibility.
    participant_ids: list[int]


class RsvpRequest(BaseModel):
    response: RsvpStatus


class SuggestRequest(BaseModel):
    """Request for suggesting the earliest free slot for all participants."""

    participant_ids: list[int] = Field(min_length=1)
    duration_minutes: int = Field(gt=0, le=24 * 60)
    window_start: datetime
    window_end: datetime
    work_start_hour: int = Field(default=9, ge=0, le=23)
    work_end_hour: int = Field(default=17, ge=1, le=24)


class SuggestedSlot(BaseModel):
    starts_at: datetime
    ends_at: datetime


class SuggestResponse(BaseModel):
    slots: list[SuggestedSlot]


class NotificationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    type: str
    title: str
    body: str
    read: bool
    created_at: datetime


class ConflictDetail(BaseModel):
    """Returned with a 409 when a booking is rejected."""

    detail: str = "Time slot is not free for all referenced users."
    conflicting_user_ids: list[int] = []
