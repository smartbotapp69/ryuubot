ALTER TABLE users
    ADD COLUMN last_login_at timestamptz,
    ADD COLUMN last_active_at timestamptz;

UPDATE users u
SET last_login_at = s.last_seen,
    last_active_at = s.last_seen
FROM (
    SELECT user_id, max(created_at) AS last_seen
    FROM user_sessions
    GROUP BY user_id
) s
WHERE s.user_id = u.id;

CREATE INDEX users_last_active_idx ON users(last_active_at DESC NULLS LAST);
