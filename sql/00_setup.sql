-- ============================================================
-- MGTA 457 | Olist marketplace project
-- File:     00_setup.sql
-- Owner:    TODO name
-- Purpose:  Create the catalog, the two schemas and the volume
--           that holds the source files exactly as downloaded.
-- Run:      Once, before uploading the files (see README.md).
--           Safe to run again: it creates only what is missing.
-- AI use:   Drafted with Claude (Anthropic), 2026-11-17
--           (see docs/ai_usage.md).
--           Reviewed and understood by: TODO name
-- ============================================================

-- One catalog for the whole project, kept apart from the class
-- tutorial catalogs.
CREATE CATALOG IF NOT EXISTS olist
COMMENT 'MGTA 457 team project: Olist marketplace orders, the Olist marketing funnel and IBGE state population.';

-- raw: the files as delivered. Loaded by 01_load_raw.sql and never
-- edited afterwards.
CREATE SCHEMA IF NOT EXISTS olist.raw
COMMENT 'Bronze. The source files as delivered, every column as text. Never edited after loading.';

-- analytics: everything we build (Silver, Gold, metric views, checks).
CREATE SCHEMA IF NOT EXISTS olist.analytics
COMMENT 'Silver, Gold, metric views and checks built from olist.raw.';

-- The volume holds the downloaded files, one folder per source:
--   landing_zone/marketplace/  9 CSV files from the Olist e-commerce dataset
--   landing_zone/funnel/       2 CSV files from the Olist marketing funnel dataset
--   landing_zone/ibge/         2 JSON answers from the IBGE public API
CREATE VOLUME IF NOT EXISTS olist.raw.landing_zone
COMMENT 'The source files exactly as downloaded, one folder per source. See docs/sources.md for where each came from.';
