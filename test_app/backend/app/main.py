from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.routers import appointments, auth, integrations, notifications, users

app = FastAPI(
    title="Shared Calendar API",
    description=(
        "Multi-user calendar: a shared (team) calendar plus per-user private "
        "calendars. A shared appointment can be booked iff the slot is free for "
        "every referenced user — enforced atomically by a Postgres EXCLUDE "
        "constraint."
    ),
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(appointments.router)
app.include_router(integrations.router)
app.include_router(notifications.router)


@app.get("/health", tags=["meta"])
async def health():
    return {"status": "ok"}
