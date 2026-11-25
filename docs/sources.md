# Data sources

Three datasets from two publishers: 13 files, loaded into 13 tables in `olist.raw`. The files themselves never go in this repository. They sit in the Databricks volume `olist.raw.landing_zone`, one folder per source.

| # | Source | Publisher | Files | What it holds |
| --- | --- | --- | --- | --- |
| 1 | Brazilian E-Commerce Public Dataset by Olist | Olist, on Kaggle | 9 CSV | About 100,000 orders placed on Brazilian marketplaces through Olist, September 2016 to October 2018: items, payments, reviews, customers, sellers, products, zip-code locations, and English names for the product categories |
| 2 | Marketing Funnel by Olist | Olist, on Kaggle | 2 CSV | 8,000 sellers who asked to join Olist (June 2017 to May 2018), with the channel they came from, and the 842 who signed up |
| 3 | IBGE public data API | IBGE, Brazil's statistics office | 2 JSON | 2018 population estimate for each of the 27 states, and the list of states with their numeric code, two-letter abbreviation and region |

## Where to get them

| Source | Link | License |
| --- | --- | --- |
| 1 | https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce | CC BY-NC-SA 4.0, as the Kaggle dataset page lists it (checked 2026-11-24) |
| 2 | https://www.kaggle.com/datasets/olistbr/marketing-funnel-olist | CC BY-NC-SA 4.0, as the Kaggle dataset page lists it (checked 2026-11-24) |
| 3 | `sh tools/fetch_ibge.sh <folder>` calls the two IBGE API addresses written in that script | IBGE public data, free to reuse with credit to IBGE |

CC BY-NC-SA allows non-commercial use such as coursework, as long as we credit Olist and share anything derived from the data under the same terms.

## The files we loaded, and how we know they are the originals

Our first copies came from public mirrors:

- The 9 marketplace files are the copy at huggingface.co/datasets/bulutttt/olist-raw-data. Two other independent uploads, aviahYadler/Olist_Ecommerce_Dataset and MafiaAzulBr/olistcsv, are identical to it byte for byte.
- The 2 funnel files come from github.com/Catherinedataa/Olist-Sales-Funnel-Analysis. Only one copy was checked at first; the Kaggle check below settled it.
- **Checked against Kaggle on 2026-11-24.** Both datasets were downloaded from the Kaggle links above and the IBGE files were fetched again. All 13 SHA-256 hashes match the table below, so the tables in `olist.raw` hold the Kaggle files and nothing needs reloading.

| Folder | File | Rows | SHA-256 |
| --- | --- | ---: | --- |
| marketplace | olist_orders_dataset.csv | 99,441 | `8df58ef3d2d7e9944010f7beecd9b75367f5588ec6e3c91cec19ae3345ef9ecf` |
| marketplace | olist_order_items_dataset.csv | 112,650 | `0bc4d068c4fe38cbb01bd90e8746e3c613fe7b4baef75fab7b0e329701c3e279` |
| marketplace | olist_order_payments_dataset.csv | 103,886 | `4f713964f2815dbbaa40b9488268c55aac3627bfce5aa96cf58d1f3616de3cc0` |
| marketplace | olist_order_reviews_dataset.csv | 99,224 | `012b61c7593e34f51fa614efdf802b9c7056ce6aae5307ddb93236e7cfc797d7` |
| marketplace | olist_customers_dataset.csv | 99,441 | `983a422239e1712ded753b3bf9ecf47dc73f144d306029dcfa99e70a226883d2` |
| marketplace | olist_sellers_dataset.csv | 3,095 | `1f643d2b950373b85735e7794b20986f528d7a000432e7c6f9bcbb44d0846a0e` |
| marketplace | olist_products_dataset.csv | 32,951 | `3e6569628a17fbc75fd206ee357b59e20364b9afa90f5b6cd5b4d624c58aa9cc` |
| marketplace | olist_geolocation_dataset.csv | 1,000,163 | `b514f6fc991b9566aeba02aa5d67e2c3630f034b60a0e05aa0d082a3b66d88d6` |
| marketplace | product_category_name_translation.csv | 71 | `a81f0d1f27b27e7293f761bc79e3ce8f348ee39c4b3ed3e49bde38f478586278` |
| funnel | olist_marketing_qualified_leads_dataset.csv | 8,000 | `5537753b7549ce4068e52e2402c29f2773c5375fc0575520ae8f3f301f666573` |
| funnel | olist_closed_deals_dataset.csv | 842 | `1433f402d8fff00ca167579de641d9525f6e846368958c166f699ef1b0c31f3d` |
| ibge | population_2018.json | 27 states | `9087c2bed588c123b30edcb6e1f579f62d25ea9cbed92f8bd91afc84651d0576` |
| ibge | states.json | 27 states | `7ca1368dea3af83cba1af84ae8a7e88f1173c97586831d086cc8b3c1ba9c6596` |

The IBGE files were downloaded on 2026-11-17 and again on 2026-11-24, with the same hashes. IBGE can revise its estimates, so a later download may differ; the 2018 total we loaded is 208,494,900 people.

To compute a hash on a Mac: `shasum -a 256 <file>`.
