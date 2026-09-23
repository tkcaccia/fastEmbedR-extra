source(file.path(dirname(script_file()), "common.R"))
args <- parse_cli(); root <- args$root %||% "/scratch/firenze/NN"
code <- args$code_dir %||% file.path(root, "kodama_cpu4_ablation_hpc")
release <- args$release %||% "8d5339a"
run_root <- args$run_root %||% file.path(root, paste0("kodama_cpu4_ablation_", release))
image <- args$image %||% file.path(root, "singularity", "fastembedr_cuda.sif")
dir.create(file.path(run_root, "slurm"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(run_root, "logs"), recursive = TRUE, showWarnings = FALSE)
cells_path <- file.path(run_root, "cells.csv")
old <- commandArgs(); source(file.path(code, "build_cells.R"), local = new.env())
# build_cells.R uses commandArgs, so construct directly here when invoked by the normal setup script.
system2("Rscript", c(file.path(code, "build_cells.R"), paste0("--out=", cells_path)))
cells <- read.csv(cells_path, stringsAsFactors = FALSE)
graphs <- unique(cells[, c("dataset", "representation", "seed")]); graphs$graph_id <- seq_len(nrow(graphs))
atomic_write_csv(graphs, file.path(run_root, "graphs.csv"))
header <- function(name, array_n, time, mem) c("#!/usr/bin/env bash", paste0("#SBATCH --job-name=", name),
  "#SBATCH --account=eresearch", "#SBATCH --partition=ada", "#SBATCH --nodes=1", "#SBATCH --ntasks=1",
  "#SBATCH --cpus-per-task=4", paste0("#SBATCH --mem=", mem), paste0("#SBATCH --time=", time),
  paste0("#SBATCH --array=1-", array_n, "%40"), paste0("#SBATCH --output=", run_root, "/logs/%x_%A_%a.out"),
  paste0("#SBATCH --error=", run_root, "/logs/%x_%A_%a.err"), "set -euo pipefail")
graph_sh <- c(header("KOD_graph4", nrow(graphs), "12:00:00", "96G"),
  paste0("ROW=$(awk -F, -v id=$SLURM_ARRAY_TASK_ID 'NR>1 && $4==id {print $0}' ", shQuote(file.path(run_root,"graphs.csv")), ")"),
  "IFS=, read -r DATASET REPRESENTATION SEED GRAPH_ID <<< \"$ROW\"",
  paste0("OUT=", shQuote(file.path(run_root,"prepared_graphs")), "/$DATASET/$REPRESENTATION/seed_$SEED"),
  paste0("IMAGE=", shQuote(image), " SCRIPT=", shQuote(file.path(code,"prepare_graph.R")), " ", shQuote(file.path(code,"run_worker.sh")),
    " --dataset=$DATASET --representation=$REPRESENTATION --seed=$SEED --data-root=", shQuote(file.path(root,"Data")), " --out-dir=$OUT"))
cell_sh <- c(header("KOD_cell4", nrow(cells), "48:00:00", "128G"),
  paste0("IMAGE=", shQuote(image), " SCRIPT=", shQuote(file.path(code,"run_cell.R")), " ", shQuote(file.path(code,"run_worker.sh")),
    " --cells=", shQuote(cells_path), " --cell-id=$SLURM_ARRAY_TASK_ID --prepared-root=", shQuote(file.path(run_root,"prepared_graphs")),
    " --out-root=", shQuote(file.path(run_root,"cells"))))
preflight_sh <- c(header("KOD_pre4", 1L, "01:00:00", "32G")[-grep("--array", header("x",1,"1","1"), fixed=TRUE)],
  paste0("IMAGE=", shQuote(image), " SCRIPT=", shQuote(file.path(code,"preflight.R")), " ", shQuote(file.path(code,"run_worker.sh")),
    " --image=", shQuote(image), " --data-root=", shQuote(file.path(root,"Data")), " --out-dir=", shQuote(run_root)))
writeLines(preflight_sh, file.path(run_root,"slurm","preflight.sh")); writeLines(graph_sh,file.path(run_root,"slurm","graphs.sh")); writeLines(cell_sh,file.path(run_root,"slurm","cells.sh"))
submit <- c("#!/usr/bin/env bash", "set -euo pipefail", paste0("RUN_ROOT=", shQuote(run_root)),
  "PREFLIGHT=$(sbatch --parsable \"$RUN_ROOT/slurm/preflight.sh\")", "echo preflight=$PREFLIGHT",
  "GRAPHS=$(sbatch --parsable --dependency=afterok:$PREFLIGHT \"$RUN_ROOT/slurm/graphs.sh\")", "echo graphs=$GRAPHS",
  "CELLS=$(sbatch --parsable --dependency=afterok:$GRAPHS \"$RUN_ROOT/slurm/cells.sh\")", "echo cells=$CELLS")
writeLines(submit,file.path(run_root,"submit_all.sh")); Sys.chmod(list.files(file.path(run_root,"slurm"),full.names=TRUE),"0755");Sys.chmod(file.path(run_root,"submit_all.sh"),"0755")
cat("Generated only; submitted no jobs. Run root:",run_root,"\n")
