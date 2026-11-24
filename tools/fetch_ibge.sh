#!/bin/sh
# Download the two IBGE files this project uses, as JSON, into the folder given.
#
#   sh tools/fetch_ibge.sh <download folder>
#
# population_2018.json  IBGE table 6579 (population estimates), variable 9324
#                       (estimated resident population), year 2018, every state.
# states.json           IBGE's list of states: numeric code, two-letter
#                       abbreviation, name and region.
#
# AI use: drafted with Claude (Anthropic), 2026-11-17 (see docs/ai_usage.md).
set -eu
out="$1"
mkdir -p "$out"
curl -sS --fail --max-time 60 -o "$out/population_2018.json" \
  "https://servicodados.ibge.gov.br/api/v3/agregados/6579/periodos/2018/variaveis/9324?localidades=N3%5Ball%5D"
curl -sS --fail --max-time 60 -o "$out/states.json" \
  "https://servicodados.ibge.gov.br/api/v1/localidades/estados"
ls -l "$out"
