CREATE TABLE app_settings (
    key text PRIMARY KEY,
    category varchar(30) NOT NULL,
    label text NOT NULL,
    value text NOT NULL,
    value_type varchar(12) NOT NULL CHECK (value_type IN ('decimal','integer','text','time','boolean')),
    minimum numeric,
    maximum numeric,
    sort_order integer NOT NULL DEFAULT 0,
    updated_by bigint REFERENCES admin_users(id) ON DELETE RESTRICT,
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX app_settings_category_order ON app_settings(category,sort_order,key);

CREATE TABLE app_settings_audit (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    setting_key text NOT NULL,
    old_value text NOT NULL,
    new_value text NOT NULL,
    admin_user_id bigint NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO app_settings(key,category,label,value,value_type,minimum,maximum,sort_order) VALUES
('trading.user_percent','trading','Bagian user (%)','86','decimal',0,100,10),
('trading.holding_percent','trading','Bagian akun penampung (%)','12','decimal',0,100,20),
('trading.kangden_percent','trading','Bagian kangden69 (%)','2','decimal',0,100,30),
('trading.fee_exempt_username','trading','Username bebas fee','kangden69','text',NULL,NULL,40),
('referral.level_1_percent','referral','Referral level 1 (%)','1.5','decimal',0,100,10),
('referral.level_2_percent','referral','Referral level 2 (%)','0.9','decimal',0,100,20),
('referral.level_3_percent','referral','Referral level 3 (%)','0.6','decimal',0,100,30),
('subscription.price_trx','subscription','Harga per bulan (TRX)','22','decimal',0,NULL,10),
('subscription.upline_trx','subscription','Bagian upline (TRX)','3','decimal',0,NULL,20),
('subscription.management_trx','subscription','Bagian management (TRX)','19','decimal',0,NULL,30),
('subscription.trial_days','subscription','Trial user baru (hari)','2','integer',0,365,40),
('owner.nana_percent','owner','Kang Nana (%)','30','decimal',0,100,10),
('owner.deni_percent','owner','Kang Deni (%)','30','decimal',0,100,20),
('owner.arya_percent','owner','Pak Arya (%)','30','decimal',0,100,30),
('owner.operational_percent','owner','Operasional (%)','10','decimal',0,100,40),
('owner.cutoff_1','owner','Cutoff pertama','13:00','time',NULL,NULL,50),
('owner.cutoff_2','owner','Cutoff kedua','18:00','time',NULL,NULL,60),
('coin.TRX.minimum_bet','coins','TRX minimum bet','0.00000100','decimal',0,NULL,10),
('coin.TRX.minimum_withdrawal','coins','TRX minimum withdrawal','3','decimal',0,NULL,11),
('coin.TRX.minimum_claim','coins','TRX minimum claim bonus','30','decimal',0,NULL,12),
('coin.DOGE.minimum_bet','coins','DOGE minimum bet','0.00010000','decimal',0,NULL,20),
('coin.DOGE.minimum_withdrawal','coins','DOGE minimum withdrawal','5','decimal',0,NULL,21),
('coin.DOGE.minimum_claim','coins','DOGE minimum claim bonus','50','decimal',0,NULL,22),
('coin.FLOKI.minimum_bet','coins','FLOKI minimum bet','0.06000000','decimal',0,NULL,30),
('coin.FLOKI.minimum_withdrawal','coins','FLOKI minimum withdrawal','25000','decimal',0,NULL,31),
('coin.FLOKI.minimum_claim','coins','FLOKI minimum claim bonus','250000','decimal',0,NULL,32),
('coin.BTT.minimum_bet','coins','BTT minimum bet','0.10000000','decimal',0,NULL,40),
('coin.BTT.minimum_withdrawal','coins','BTT minimum withdrawal','2000000','decimal',0,NULL,41),
('coin.BTT.minimum_claim','coins','BTT minimum claim bonus','20000000','decimal',0,NULL,42)
ON CONFLICT (key) DO NOTHING;

CREATE TABLE app_setting_categories (
    key varchar(30) PRIMARY KEY,
    label text NOT NULL,
    description text NOT NULL,
    sort_order integer NOT NULL DEFAULT 0
);

INSERT INTO app_setting_categories(key,label,description,sort_order) VALUES
('trading','Trading & Fee','Pembagian hasil trading dan akun bebas fee.',10),
('referral','Referral','Persentase bonus referral dari bagian akun penampung.',20),
('subscription','Subscription','Harga langganan, trial, bagian upline, dan management.',30),
('owner','Owner & Jadwal','Pembagian saldo penampung dan jadwal cutoff.',40),
('coins','Coin & Minimum','Batas minimum bet, withdrawal, dan klaim bonus per coin.',50)
ON CONFLICT (key) DO NOTHING;
