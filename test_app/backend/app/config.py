from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration, loaded from environment / .env file."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # postgresql+asyncpg://<user>:<password>@<host>:<port>/<db>
    database_url: str = "postgresql+asyncpg://calendar:calendar@localhost:5432/calendar"

    # JWT
    secret_key: str = "change-me-in-production"
    access_token_expire_minutes: int = 60 * 24  # 1 day
    jwt_algorithm: str = "HS256"

    # CORS — Flutter dev origins. "*" is fine for local dev.
    cors_origins: list[str] = ["*"]

    # --- Google Calendar integration (see backend/GOOGLE_SETUP.md) ---
    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = "http://localhost:8000/integrations/google/callback"

    @property
    def google_enabled(self) -> bool:
        return bool(self.google_client_id and self.google_client_secret)


settings = Settings()
