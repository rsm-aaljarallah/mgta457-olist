-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     01_load_raw.sql
-- Owner:    TODO name
-- Purpose:  Load the 13 source files into olist.raw (Bronze),
--           exactly as delivered: every CSV column as text, the
--           IBGE answers as nested JSON. Nothing is fixed here.
--           Typing, renaming and cleaning happen in Silver.
-- Run:      After 00_setup.sql and tools/upload_raw.sh. Running
--           it again reloads the same files and gives the same
--           tables. Expected row counts are in 02_profile_bronze.sql.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-17
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- How the CSV files are read, and why:
--   inferSchema => false  every column stays text, so a zip code such as
--                         "01037" keeps its leading zero and nothing is
--                         guessed before we have profiled it.
--   multiLine => true     some review comments contain line breaks inside
--                         quotes; without this one review becomes two rows.
--   escape => '"'         the files write a quote inside a quoted field as
--                         two quotes (""), the standard CSV way. Spark's
--                         default escape character is a backslash.
-- Every table also records the file it came from and when it was loaded.
-- read_files adds one more column, _rescued_data, holding anything from a
-- row that did not fit the columns; 02_profile_bronze.sql checks it is empty.

-- ------------------------------------------------------------
-- Source 1: Olist e-commerce marketplace (9 files)
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.raw.orders
COMMENT 'olist_orders_dataset.csv as downloaded. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_orders_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.order_items
COMMENT 'olist_order_items_dataset.csv as downloaded. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_order_items_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.order_payments
COMMENT 'olist_order_payments_dataset.csv as downloaded. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_order_payments_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.order_reviews
COMMENT 'olist_order_reviews_dataset.csv as downloaded. Every column is text. Comments are in Portuguese and can contain line breaks.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_order_reviews_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.customers
COMMENT 'olist_customers_dataset.csv as downloaded. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_customers_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.sellers
COMMENT 'olist_sellers_dataset.csv as downloaded. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_sellers_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.products
COMMENT 'olist_products_dataset.csv as downloaded. Every column is text. Two column names are misspelled in the source (product_name_lenght, product_description_lenght); Silver renames them.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_products_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.geolocation
COMMENT 'olist_geolocation_dataset.csv as downloaded. Every column is text. Many rows per zip code prefix.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/olist_geolocation_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.category_translation
COMMENT 'product_category_name_translation.csv as downloaded: Portuguese category name and its English name.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/marketplace/product_category_name_translation.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

-- ------------------------------------------------------------
-- Source 2: Olist marketing funnel (2 files)
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.raw.leads
COMMENT 'olist_marketing_qualified_leads_dataset.csv as downloaded: sellers who asked to join, with the first contact date and the channel. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/funnel/olist_marketing_qualified_leads_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

CREATE OR REPLACE TABLE olist.raw.closed_deals
COMMENT 'olist_closed_deals_dataset.csv as downloaded: leads that signed up as sellers. Every column is text.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/funnel/olist_closed_deals_dataset.csv',
  format => 'csv', header => true, inferSchema => false, multiLine => true, escape => '"');

-- ------------------------------------------------------------
-- Source 3: IBGE, Brazil's statistics office (2 JSON answers)
-- The population answer is one nested record per variable, with the 27
-- states inside it; Silver unnests it into one row per state.
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE olist.raw.ibge_population_2018
COMMENT 'IBGE API answer for table 6579, variable 9324 (estimated population), 2018, all states, as nested JSON.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/ibge/population_2018.json',
  format => 'json', multiLine => true);

CREATE OR REPLACE TABLE olist.raw.ibge_states
COMMENT 'IBGE API list of states: numeric code, two-letter abbreviation, name and region, as JSON.'
AS SELECT *, _metadata.file_name AS _source_file, current_timestamp() AS _loaded_at
FROM read_files('/Volumes/olist/raw/landing_zone/ibge/states.json',
  format => 'json', multiLine => true);
