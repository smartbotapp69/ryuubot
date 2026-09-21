ALTER TABLE business_rule_versions
    DROP COLUMN IF EXISTS change_reason;

ALTER TABLE admin_business_rule_audit
    DROP COLUMN IF EXISTS reason;

ALTER TABLE admin_business_rule_audit
    DROP CONSTRAINT IF EXISTS admin_business_rule_audit_action_check;

UPDATE admin_business_rule_audit
    SET action = 'SAVE'
    WHERE action <> 'SAVE';

ALTER TABLE admin_business_rule_audit
    ADD CONSTRAINT admin_business_rule_audit_action_check CHECK (action = 'SAVE');
