"""google calendar integration: connections table + google_event_id

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-21

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE calendar_connections (
            id            BIGSERIAL PRIMARY KEY,
            user_id       BIGINT NOT NULL UNIQUE REFERENCES users (id) ON DELETE CASCADE,
            provider      VARCHAR(20) NOT NULL DEFAULT 'google',
            access_token  TEXT NOT NULL,
            refresh_token TEXT,
            token_expiry  TIMESTAMPTZ NOT NULL,
            scope         TEXT,
            created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
            updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
        );
        """
    )
    op.execute(
        "ALTER TABLE calendar_entries ADD COLUMN google_event_id VARCHAR(256);"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE calendar_entries DROP COLUMN google_event_id;")
    op.execute("DROP TABLE IF EXISTS calendar_connections;")
