SELECT concat_ws(':',
	(SELECT count(*) FROM ad_entitytype WHERE entitytype = 'CDSRCR'),
	(SELECT count(*) FROM ad_table WHERE lower(tablename) = 'c_bpartner_product_chip'),
	(SELECT count(*) FROM ad_column c JOIN ad_table t ON t.ad_table_id = c.ad_table_id WHERE lower(t.tablename) = 'c_bpartner_product_chip'),
	(SELECT count(*) FROM ad_field f JOIN ad_tab tb ON tb.ad_tab_id = f.ad_tab_id JOIN ad_window w ON w.ad_window_id = tb.ad_window_id WHERE w.name = 'Partner Product Chip'));
