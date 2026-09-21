CREATE TABLE admin_user_actions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_username varchar(100) NOT NULL,
    user_id bigint NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    action varchar(24) NOT NULL CHECK (action IN ('EXTEND_SUBSCRIPTION','RESET_PASSWORD','SUSPEND','ACTIVATE')),
    detail jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX admin_user_actions_user_time ON admin_user_actions(user_id,created_at DESC);
