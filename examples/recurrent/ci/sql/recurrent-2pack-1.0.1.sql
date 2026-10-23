DO $$
DECLARE
	missing_columns text;
BEGIN
	IF NOT EXISTS (SELECT 1 FROM ad_entitytype WHERE entitytype = 'CDSRCR' AND isactive = 'Y') THEN
		RAISE EXCEPTION 'Active entity type CDSRCR was not installed';
	END IF;
	IF NOT EXISTS (SELECT 1 FROM ad_table WHERE lower(tablename) = 'c_bpartner_product_chip' AND entitytype = 'CDSRCR') THEN
		RAISE EXCEPTION 'Dictionary table C_BPartner_Product_Chip was not installed';
	END IF;
	IF to_regclass('adempiere.c_bpartner_product_chip') IS NULL THEN
		RAISE EXCEPTION 'Physical table C_BPartner_Product_Chip was not installed';
	END IF;

	SELECT string_agg(expected.columnname, ', ' ORDER BY expected.columnname)
	INTO missing_columns
	FROM (VALUES
		('C_BPartner_Product_Chip_ID'),
		('C_BPartner_Product_Chip_UU'),
		('C_BPartner_ID'),
		('M_Product_ID'),
		('M_PriceList_ID'),
		('Qty'),
		('PriceList'),
		('PriceStd'),
		('Amt'),
		('BreakDiscount')
	) AS expected(columnname)
	WHERE NOT EXISTS (
		SELECT 1
		FROM ad_column c
		JOIN ad_table t ON t.ad_table_id = c.ad_table_id
		WHERE lower(t.tablename) = 'c_bpartner_product_chip'
		AND lower(c.columnname) = lower(expected.columnname)
	);
	IF missing_columns IS NOT NULL THEN
		RAISE EXCEPTION 'Missing dictionary columns: %', missing_columns;
	END IF;

	IF EXISTS (
		SELECT 1 FROM ad_column c
		JOIN ad_table t ON t.ad_table_id = c.ad_table_id
		WHERE lower(t.tablename) = 'c_bpartner_product_chip'
		AND lower(c.columnname) = 'isbillable'
	) THEN
		RAISE EXCEPTION 'IsBillable must not exist before incremental 2Pack 1.0.2';
	END IF;
END
$$;
