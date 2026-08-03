"""add RSVP response to calendar_entries

Revision ID: 0002
Revises: 0001
Create Date: 2026-06-26

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE TYPE rsvp_status AS ENUM ('pending', 'yes', 'no');")
    op.execute(
        """
        ALTER TABLE calendar_entries
        ADD COLUMN response rsvp_status NOT NULL DEFAULT 'pending';
        """
    )


def downgrade() -> None:
    op.execute("ALTER TABLE calendar_entries DROP COLUMN response;")
    op.execute("DROP TYPE rsvp_status;")
