DO $$
BEGIN
	IF EXISTS (SELECT 1 FROM ad_entitytype WHERE entitytype = 'CDSRCR') THEN
		RAISE EXCEPTION 'Entity type CDSRCR already exists';
	END IF;
	IF EXISTS (SELECT 1 FROM ad_table WHERE lower(tablename) = 'c_bpartner_product_chip') THEN
		RAISE EXCEPTION 'Dictionary table C_BPartner_Product_Chip already exists';
	END IF;
	IF to_regclass('adempiere.c_bpartner_product_chip') IS NOT NULL THEN
		RAISE EXCEPTION 'Physical table C_BPartner_Product_Chip already exists';
	END IF;
END
$$;
