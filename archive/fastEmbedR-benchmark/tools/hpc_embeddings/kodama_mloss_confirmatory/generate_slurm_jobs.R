source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();required<-c("suite_dir","data_root","result_root","layout_root","input_root","image","release_lock","out_dir")
miss<-required[vapply(required,function(k)is.null(args[[k]]),logical(1))];if(length(miss))stop("Missing: ",paste(miss,collapse=", "))
dir.create(args$out_dir,recursive=TRUE,showWarnings=FALSE);reg<-load_registry(file.path(args$suite_dir,"datasets.csv"));seeds<-c(4L,17L,42L)
q<-function(x)shQuote(normalizePath(x,mustWork=FALSE)); manifest<-list()
write_job<-function(experiment,dataset,seed,backend,cores,script,extra=""){
 d<-file.path(args$out_dir,experiment);dir.create(d,recursive=TRUE,showWarnings=FALSE);name<-sprintf("%s_%s_%s_%dc_s%d",experiment,safe_name(dataset),backend,cores,seed);path<-file.path(d,paste0(name,".sh"))
 cuda<-backend=="cuda";header<-c("#!/usr/bin/env bash",sprintf("#SBATCH --job-name=%s",substr(name,1,80)),
  if(cuda)"#SBATCH --account=l40sfree" else "#SBATCH --account=eresearch",if(cuda)"#SBATCH --partition=l40s" else "#SBATCH --partition=ada",
  "#SBATCH --nodes=1","#SBATCH --ntasks=1",sprintf("#SBATCH --cpus-per-task=%d",cores),"#SBATCH --mem=64G","#SBATCH --time=48:00:00",
  if(cuda)"#SBATCH --gres=gpu:l40s:1" else NULL,sprintf("#SBATCH --output=%s",file.path(args$out_dir,"logs",paste0(name,"_%j.out"))),
  sprintf("#SBATCH --error=%s",file.path(args$out_dir,"logs",paste0(name,"_%j.err"))),"set -euo pipefail",sprintf("mkdir -p %s",q(file.path(args$out_dir,"logs"))))
 result<-file.path(args$result_root,experiment,dataset,backend,paste0("seed_",seed));layout<-file.path(args$layout_root,experiment,dataset,backend,paste0("seed_",seed))
 cmd<-paste(sprintf("IMAGE=%s SCRIPT=%s OUT_DIR=%s BACKEND=%s N_CORES=%d",q(args$image),q(file.path(args$suite_dir,script)),q(result),backend,cores),
  q(file.path(args$suite_dir,"run_worker.sh")),sprintf("--dataset=%s --seed=%d --backend=%s --n-cores=%d --data-root=%s --out-dir=%s --layout-dir=%s --release-lock=%s --image=%s %s",
  dataset,seed,backend,cores,q(args$data_root),q(result),q(layout),q(args$release_lock),q(args$image),extra))
 writeLines(c(header,cmd),path);Sys.chmod(path,"0755");manifest[[length(manifest)+1L]]<<-data.frame(experiment,dataset,seed,backend,cores,path)
}
for(dataset in reg$dataset)for(seed in seeds)write_job("confirmatory",dataset,seed,"cuda",1L,"run_confirmatory_dataset.R")
for(dataset in reg$dataset[reg$representative_mt])for(seed in seeds)write_job("mtcycle",dataset,seed,"cuda",1L,"run_mtcycle_dataset.R")
for(dataset in reg$dataset[reg$large_landmark])for(seed in seeds)write_job("landmark",dataset,seed,"cuda",1L,"run_landmark_dataset.R")
for(dataset in reg$dataset[reg$representative_ablation])for(seed in seeds)write_job("ablation",dataset,seed,"cuda",1L,"run_ablation_dataset.R")
for(dataset in unique(c("MetRef","MNIST","flow18")))for(seed in seeds)write_job("graph_api",dataset,seed,"cuda",1L,"run_graph_api_dataset.R")
for(dataset in unique(c("MetRef","MNIST","flow18")))for(seed in seeds){write_job("backend",dataset,seed,"cpu",1L,"run_backend_dataset.R");write_job("backend",dataset,seed,"cpu",4L,"run_backend_dataset.R");write_job("backend",dataset,seed,"cuda",1L,"run_backend_dataset.R")}
man<-do.call(rbind,manifest);write.csv(man,file.path(args$out_dir,"job_manifest.csv"),row.names=FALSE)
commands<-unlist(lapply(split(man$path,man$experiment),function(z)c(paste0("# ",basename(dirname(z[[1L]]))),paste("sbatch",shQuote(z)))))
writeLines(commands,file.path(args$out_dir,"submit_commands.sh"));cat("Generated ",nrow(man)," jobs. Nothing was submitted.\n",sep="")

