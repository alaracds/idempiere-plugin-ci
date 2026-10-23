DO $$
DECLARE
	column_count integer;
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM information_schema.columns
		WHERE table_schema = 'adempiere'
		AND table_name = 'c_bpartner_product_chip'
		AND column_name = 'isbillable'
		AND column_default = '''Y''::bpchar'
		AND is_nullable = 'NO'
	) THEN
		RAISE EXCEPTION 'Physical IsBillable column is missing or has an unexpected default/nullability';
	END IF;

	SELECT count(*) INTO column_count
	FROM ad_column c
	JOIN ad_table t ON t.ad_table_id = c.ad_table_id
	WHERE lower(t.tablename) = 'c_bpartner_product_chip'
	AND lower(c.columnname) = 'isbillable';
	IF column_count <> 1 THEN
		RAISE EXCEPTION 'Expected exactly one IsBillable dictionary column, found %', column_count;
	END IF;

	IF NOT EXISTS (
		SELECT 1
		FROM ad_column c
		JOIN ad_table t ON t.ad_table_id = c.ad_table_id
		WHERE lower(t.tablename) = 'c_bpartner_product_chip'
		AND lower(c.columnname) = 'isbillable'
		AND c.defaultvalue = 'Y'
		AND c.ismandatory = 'Y'
		AND c.entitytype = 'CDSRCR'
	) THEN
		RAISE EXCEPTION 'IsBillable dictionary metadata is incomplete';
	END IF;

	IF NOT EXISTS (
		SELECT 1
		FROM ad_field f
		JOIN ad_column c ON c.ad_column_id = f.ad_column_id
		JOIN ad_tab tb ON tb.ad_tab_id = f.ad_tab_id
		JOIN ad_window w ON w.ad_window_id = tb.ad_window_id
		WHERE w.name = 'Partner Product Chip'
		AND lower(c.columnname) = 'isbillable'
		AND f.isactive = 'Y'
	) THEN
		RAISE EXCEPTION 'Active IsBillable field was not installed in Partner Product Chip';
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM ad_element_trl trl
		JOIN ad_element e ON e.ad_element_id = trl.ad_element_id
		WHERE lower(e.columnname) = 'isbillable'
		AND trl.ad_language IN ('es_CO', 'es_PA')
		AND trl.name = 'Facturable'
		GROUP BY e.ad_element_id
		HAVING count(DISTINCT trl.ad_language) = 2
	) THEN
		RAISE EXCEPTION 'Expected Facturable translations for es_CO and es_PA';
	END IF;
END
$$;
