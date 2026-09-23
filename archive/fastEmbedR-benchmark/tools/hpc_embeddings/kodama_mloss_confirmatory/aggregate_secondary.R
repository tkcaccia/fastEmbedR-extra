source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();root<-args$result_root%||%stop("--result-root required");out<-args$out_dir%||%file.path(root,"secondary_aggregate");dir.create(out,recursive=TRUE,showWarnings=FALSE)
patterns<-c(mtcycle="_mtcycle\\.csv$",landmark="_landmark\\.csv$",backend="_backend\\.csv$",graph_api="_graph_api\\.csv$",ablation="_ablation\\.csv$")
safe_median<-function(z){z<-as.numeric(z);z<-z[is.finite(z)];if(length(z))median(z)else NA_real_}
for(exp in names(patterns)){
 files<-list.files(file.path(root,exp),pattern=patterns[[exp]],recursive=TRUE,full.names=TRUE)
 if(!length(files))next
 raw<-do.call(rbind,lapply(files,read.csv,stringsAsFactors=FALSE));write.csv(raw,file.path(out,paste0(exp,"_all_rows.csv")),row.names=FALSE)
 id<-intersect(c("dataset","classifier","visualization","variant","M","Tcycle","selection","budget","backend","n_cores","search_mode","input_mode"),names(raw))
 num<-names(raw)[vapply(raw,is.numeric,logical(1))];num<-setdiff(num,c("seed"))
 if(length(id)&&length(num)){med<-aggregate(raw[num],raw[id],safe_median);write.csv(med,file.path(out,paste0(exp,"_dataset_seed_medians.csv")),row.names=FALSE)}
}

