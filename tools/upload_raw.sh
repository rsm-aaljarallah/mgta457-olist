#!/bin/sh
# Upload the source files to the olist.raw.landing_zone volume, one folder per source.
#
#   sh tools/upload_raw.sh <folder with the Olist CSV files> <folder with the IBGE JSON files> [profile]
#
# The first folder must hold the 9 marketplace CSV files and the 2 funnel CSV
# files, with the names Kaggle gives them. Run sql/00_setup.sql first so the
# volume exists. The data files never go in this repository.
#
# AI use: drafted with Claude (Anthropic), 2026-11-17 (see docs/ai_usage.md).
set -eu
csv="$1"; ibge="$2"; profile="${3:-chord}"
vol="dbfs:/Volumes/olist/raw/landing_zone"

# fs cp does not create folders inside a volume, so make them first.
for d in marketplace funnel ibge; do
  databricks fs mkdir "$vol/$d" -p "$profile"
done

for f in olist_orders_dataset.csv olist_order_items_dataset.csv olist_order_payments_dataset.csv \
         olist_order_reviews_dataset.csv olist_customers_dataset.csv olist_sellers_dataset.csv \
         olist_products_dataset.csv olist_geolocation_dataset.csv product_category_name_translation.csv; do
  databricks fs cp "$csv/$f" "$vol/marketplace/$f" --overwrite -p "$profile"
done
for f in olist_marketing_qualified_leads_dataset.csv olist_closed_deals_dataset.csv; do
  databricks fs cp "$csv/$f" "$vol/funnel/$f" --overwrite -p "$profile"
done
for f in population_2018.json states.json; do
  databricks fs cp "$ibge/$f" "$vol/ibge/$f" --overwrite -p "$profile"
done
databricks fs ls "$vol/marketplace" -p "$profile"
databricks fs ls "$vol/funnel" -p "$profile"
databricks fs ls "$vol/ibge" -p "$profile"
