CREATE TABLE IF NOT EXISTS user_pasino_accounts (
    user_id bigint PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    provider_username varchar(100) NOT NULL,
    provider_email varchar(254),
    password_ciphertext text,
    access_token_ciphertext text,
    access_token_expires_at timestamptz,
    socket_token_ciphertext text,
    socket_token_expires_at timestamptz,
    encryption_version smallint NOT NULL DEFAULT 0,
    imported_from_legacy boolean NOT NULL DEFAULT false,
    last_authenticated_at timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(provider_username)
);
CREATE INDEX IF NOT EXISTS user_pasino_accounts_access_expiry ON user_pasino_accounts(access_token_expires_at);
