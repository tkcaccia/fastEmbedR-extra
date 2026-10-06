#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$root/../.." && pwd)
mode=${1:-all}
if [[ "$mode" != all && "$mode" != pdf ]]; then
  printf 'Usage: %s [all|pdf]\n' "$0" >&2
  exit 2
fi

cd "$root"
mkdir -p outputs
"${RSCRIPT:-Rscript}" \
  "$repo/analysis/render_jss_secondary_20260930.R" generated
"${LATEXMK:-latexmk}" -pdf -interaction=nonstopmode \
  -halt-on-error -outdir=outputs fastEmbedR_JSS.tex
"${LATEXMK:-latexmk}" -pdf -interaction=nonstopmode \
  -halt-on-error -outdir=outputs fastEmbedR_JSS_supplement.tex
if [[ "$mode" == pdf ]]; then
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
"${RSCRIPT:-Rscript}" "$repo/analysis/prepare_jss_docx_source.R" \
  fastEmbedR_JSS.tex "$tmp/main.tex"
"${PANDOC:-pandoc}" -f latex -t docx "$tmp/main.tex" \
  --resource-path="$root" --bibliography="$root/fastEmbedR_JSS.bib" \
  --citeproc -o "$tmp/main_raw.docx"
"${PYTHON:-python3}" "$repo/analysis/format_jss_docx.py" \
  "$tmp/main_raw.docx" outputs/fastEmbedR_JSS.docx

"${RSCRIPT:-Rscript}" "$repo/analysis/prepare_jss_docx_source.R" \
  fastEmbedR_JSS_supplement.tex "$tmp/supplement.tex"
"${PANDOC:-pandoc}" -f latex -t docx "$tmp/supplement.tex" \
  --resource-path="$root" --bibliography="$root/fastEmbedR_JSS.bib" \
  --citeproc -o "$tmp/supplement_raw.docx"
"${PYTHON:-python3}" "$repo/analysis/format_jss_docx.py" \
  "$tmp/supplement_raw.docx" "$tmp/supplement_formatted.docx"
"${PYTHON:-python3}" \
  "$repo/analysis/add_runtime_table_to_supp_docx.py" \
  "$tmp/supplement_formatted.docx" \
  generated/table_all_methods_runtime_supp.csv \
  20260930T203319Z outputs/fastEmbedR_JSS_supplement.docx
