ALTER TABLE app_settings_audit ALTER COLUMN admin_user_id DROP NOT NULL;

INSERT INTO app_setting_categories(key,label,description,sort_order) VALUES
('accounts','Akun Bisnis','Username akun Pasino untuk penampung, langganan, fee, owner, dan operasional.',45)
ON CONFLICT (key) DO UPDATE SET label=excluded.label,description=excluded.description,sort_order=excluded.sort_order;

INSERT INTO app_settings(key,category,label,value,value_type,minimum,maximum,sort_order) VALUES
('account.fee_collector_username','accounts','Akun penampung fee','smartbotapp','text',NULL,NULL,10),
('account.subscription_collector_username','accounts','Akun penampung langganan','langgananbot','text',NULL,NULL,20),
('account.kangden_username','accounts','Akun penerima fee kangden','kangden69','text',NULL,NULL,30),
('account.owner_nana_username','accounts','Akun Kang Nana','nana','text',NULL,NULL,40),
('account.owner_deni_username','accounts','Akun Kang Deni','deni','text',NULL,NULL,50),
('account.owner_arya_username','accounts','Akun Pak Arya','arya','text',NULL,NULL,60),
('account.operational_username','accounts','Akun operasional','operasional','text',NULL,NULL,70)
ON CONFLICT (key) DO NOTHING;
