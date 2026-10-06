"""Build a local, read-only index of every saved campaign PNG."""

import argparse
import html
import json
import os
from pathlib import Path
from urllib.parse import quote


DATASETS = {
    "COIL20", "USPS", "FashionMNIST", "FlowRepository_FR-FCM-ZYRM_files",
    "flow18", "MNIST", "imagenet", "MetRef", "mass41", "TabulaMuris",
    "Macosko2015_retina",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("campaign", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    campaign = args.campaign.resolve(strict=True)
    results = campaign / "results"
    if not results.is_dir():
        parser.error("campaign has no results directory")
    plots = sorted(results.rglob("*.png"))
    if not plots:
        parser.error("campaign has no PNG plots")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    prefix = Path(os.path.relpath(campaign, args.output.parent))
    records = []
    for plot in plots:
        relative = plot.relative_to(campaign)
        parts = relative.parts
        source = "/".join(quote(part) for part in (prefix / relative).parts)
        records.append({
            "title": " / ".join(parts[1:-1]),
            "category": parts[1],
            "dataset": next((part for part in parts if part in DATASETS), "other"),
            "source": source,
        })
    data = json.dumps(records, ensure_ascii=True).replace("</", "<\\/")
    title = html.escape(campaign.name)
    audit = campaign / "final_audit.txt"
    status = "missing"
    if audit.is_file():
        for line in audit.read_text(encoding="utf-8").splitlines():
            if line.startswith("status="):
                status = line.partition("=")[2]
                break
    status = html.escape(status)
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fastEmbedR plots: {title}</title>
<style>
body {{ margin:0; font:14px system-ui,sans-serif; color:#172027;
  background:#f7f8f8; }}
header {{ padding:18px max(18px,4vw); border-bottom:1px solid #ced5d7;
  background:white; }}
h1 {{ margin:0 0 12px; font-size:20px; font-weight:650; }}
.controls {{ display:flex; flex-wrap:wrap; gap:10px; align-items:center; }}
input,select,button {{ font:inherit; padding:7px 10px; border:1px solid #aebabe;
  border-radius:4px; background:white; color:inherit; }}
input {{ min-width:220px; flex:1; }}
button {{ cursor:pointer; }}
main {{ padding:18px max(18px,4vw); }}
.bar {{ display:flex; gap:14px; align-items:center; margin-bottom:12px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,
  minmax(min(100%,300px),1fr)); gap:12px; }}
figure {{ margin:0; border:1px solid #d5dcde; background:white; }}
figure a {{ display:block; }}
img {{ display:block; width:100%; aspect-ratio:6/5; object-fit:contain; }}
figcaption {{ padding:9px; font-size:12px; overflow-wrap:anywhere; }}
</style></head><body>
<header><h1>fastEmbedR campaign {title}: saved plots</h1>
<p>Final audit: {status}. Plots include diagnostic analyses.</p>
<div class="controls"><select id="category" aria-label="Plot category"></select>
<select id="dataset" aria-label="Dataset"></select>
<input id="query" type="search" placeholder="Search method, backend, seed">
</div></header><main><div class="bar"><span id="count"></span>
<button id="previous" type="button">Previous</button>
<span id="page"></span><button id="next" type="button">Next</button></div>
<div id="grid" class="grid"></div></main>
<script>
const plots={data};
const category=document.getElementById('category');
const dataset=document.getElementById('dataset');
const query=document.getElementById('query');
const grid=document.getElementById('grid');
let page=0;
function options(select,values,label) {{
  for (const value of ['',...values]) {{
    const item=document.createElement('option');
    item.value=value; item.textContent=value || label; select.append(item);
  }}
}}
options(category,[...new Set(plots.map(p=>p.category))].sort(),'All analyses');
options(dataset,[...new Set(plots.map(p=>p.dataset))].sort(),'All datasets');
category.value='workflow_comparators';
function render() {{
  const term=query.value.trim().toLowerCase();
  const rows=plots.filter(p=>(!category.value || p.category===category.value)
    && (!dataset.value || p.dataset===dataset.value)
    && (!term || p.title.toLowerCase().includes(term)));
  const pages=Math.max(1,Math.ceil(rows.length/24));
  page=Math.min(page,pages-1);
  grid.replaceChildren();
  for (const record of rows.slice(page*24,(page+1)*24)) {{
    const figure=document.createElement('figure');
    const link=document.createElement('a');
    link.href=record.source; link.target='_blank';
    const image=document.createElement('img');
    image.src=record.source; image.loading='lazy'; image.alt=record.title;
    const caption=document.createElement('figcaption');
    caption.textContent=record.title;
    link.append(image); figure.append(link,caption); grid.append(figure);
  }}
  document.getElementById('count').textContent=`${{rows.length}} plots`;
  document.getElementById('page').textContent=`${{page+1}} / ${{pages}}`;
  document.getElementById('previous').disabled=page===0;
  document.getElementById('next').disabled=page>=pages-1;
}}
for (const control of [category,dataset,query])
  control.addEventListener('input',()=>{{page=0;render();}});
document.getElementById('previous').onclick=()=>{{page--;render();}};
document.getElementById('next').onclick=()=>{{page++;render();}};
render();
</script></body></html>"""
    args.output.write_text(page, encoding="utf-8")
    print(f"Indexed {len(records)} plots in {args.output}")


if __name__ == "__main__":
    main()
