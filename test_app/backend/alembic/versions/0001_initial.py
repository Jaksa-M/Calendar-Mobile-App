"""initial schema: users, appointments, calendar_entries + no-overlap constraint

Revision ID: 0001
Revises:
Create Date: 2026-06-16

"""
from typing import Sequence, Union

from alembic import op

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # btree_gist lets a GiST index mix the scalar `user_id WITH =` operator with
    # the range `time_range WITH &&` operator in one EXCLUDE constraint.
    op.execute("CREATE EXTENSION IF NOT EXISTS btree_gist;")

    op.execute(
        """
        CREATE TABLE users (
            id            BIGSERIAL PRIMARY KEY,
            username      VARCHAR(50)  NOT NULL UNIQUE,
            display_name  VARCHAR(100) NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
        );
        """
    )
    op.execute("CREATE INDEX ix_users_username ON users (username);")

    op.execute("CREATE TYPE appointment_scope AS ENUM ('shared', 'private');")

    op.execute(
        """
        CREATE TABLE appointments (
            id          BIGSERIAL PRIMARY KEY,
            title       VARCHAR(200) NOT NULL,
            description TEXT,
            scope       appointment_scope NOT NULL,
            starts_at   TIMESTAMPTZ NOT NULL,
            ends_at     TIMESTAMPTZ NOT NULL,
            created_by  BIGINT NOT NULL REFERENCES users (id),
            created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
            CONSTRAINT ck_appt_time CHECK (ends_at > starts_at)
        );
        """
    )

    # `time_range` is a STORED generated column. The half-open interval '[)'
    # means back-to-back appointments (e.g. 10:00-11:00 and 11:00-12:00) do NOT
    # count as overlapping — exactly what calendar semantics want.
    op.execute(
        """
        CREATE TABLE calendar_entries (
            id             BIGSERIAL PRIMARY KEY,
            appointment_id BIGINT NOT NULL REFERENCES appointments (id) ON DELETE CASCADE,
            user_id        BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
            starts_at      TIMESTAMPTZ NOT NULL,
            ends_at        TIMESTAMPTZ NOT NULL,
            time_range     TSTZRANGE GENERATED ALWAYS AS
                               (tstzrange(starts_at, ends_at, '[)')) STORED,
            CONSTRAINT uq_entry_appt_user UNIQUE (appointment_id, user_id),
            CONSTRAINT ck_entry_time CHECK (ends_at > starts_at)
        );
        """
    )
    op.execute("CREATE INDEX ix_entries_user ON calendar_entries (user_id);")
    op.execute(
        "CREATE INDEX ix_entries_appointment ON calendar_entries (appointment_id);"
    )

    # THE core invariant: no single user may have two overlapping entries.
    # This is what makes 'book iff free for everyone' atomic and race-free.
    op.execute(
        """
        ALTER TABLE calendar_entries
        ADD CONSTRAINT no_overlap
        EXCLUDE USING gist (user_id WITH =, time_range WITH &&);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS calendar_entries;")
    op.execute("DROP TABLE IF EXISTS appointments;")
    op.execute("DROP TYPE IF EXISTS appointment_scope;")
    op.execute("DROP TABLE IF EXISTS users;")
