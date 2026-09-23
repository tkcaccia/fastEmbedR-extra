source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();require_capability("folds");require_capability("landmark.selection")
dataset<-args$dataset%||%stop("--dataset required");seed<-as_int(args$seed,4L);backend<-args$backend%||%"cuda";cores<-as_int(args$n_cores,4L)
out<-args$out_dir%||%stop("--out-dir required");layout_dir<-args$layout_dir%||%file.path(out,"layouts");dir.create(out,recursive=TRUE,showWarnings=FALSE);dir.create(layout_dir,recursive=TRUE,showWarnings=FALSE)
lock<-read_release_lock(args$release_lock,args$image);d<-load_dataset(dataset,args$data_root);write_manifest(out,lock,dataset,backend,seed,list(protocol="landmark-v1"))
gt<-run_timed(kodamaR::KODAMA.graph(d$x,k=100L,backend=backend,n.cores=cores,seed=seed));graph<-gt$value
budgets<-unique(c(1000L,5000L,10000L,50000L,100000L,d$n)); budgets<-budgets[budgets>=2L]
rows<-list();fits<-list()
for(cl in c("knn","pls_lda")) for(selection in c("exact_quota","uniform")) for(budget in budgets){
  variant<-if(budget>=d$n)"historical_75pct" else as.character(budget); key<-paste(cl,selection,variant,sep="_")
  ft<-run_timed(do.call(kodamaR::KODAMA.matrix,list(data=d$x,graph=graph,M=100L,Tcycle=100L,folds=5L,ncomp=min(50L,d$p),landmarks=budget,
    landmark.selection=selection,splitting=if(d$n<40000)100L else 300L,n.cores=cores,graph.neighbors=100L,knn.k=30L,classifier=cl,
    backend=backend,seed=seed,visual.init=TRUE,progress=TRUE)))
  fit<-ft$value; fits[[key]]<-fit
  vt<-run_timed(kodama_embedding(fit,"UMAP",backend,cores,seed));q<-layout_metrics(d$x,vt$value,d$labels,seed)
  idx<-as.integer(fit$landmark_indices%||%fit$landmarks_indices%||%integer())
  coverage<-if(length(idx)&&!is.null(d$labels))length(unique(d$labels[idx]))/nlevels(d$labels) else NA_real_
  projection_distance<-as.numeric(fit$projection_distance%||%fit$nonlandmark_projection_distance%||%NA_real_)
  saveRDS(vt$value,file.path(layout_dir,paste0(safe_name(key),"_layout.rds")),compress=FALSE)
  a<-fit_accuracy(fit);rows[[key]]<-data.frame(dataset=dataset,seed=seed,classifier=cl,selection=selection,budget=budget,
    effective_landmarks=if(length(idx))length(idx)else NA_integer_,historical_rule=budget>=d$n,backend=backend,status="success",graph_runtime_sec=gt$elapsed,
    core_runtime_sec=ft$elapsed,visualization_runtime_sec=vt$elapsed,best_cv_accuracy=a[["best"]],median_cv_accuracy=a[["median"]],
    active_classes=active_classes(fit),ari=ari(d$labels,fit$best_labels),silhouette=q$silhouette,preserve30=q$preserve30,
    truth_class_coverage=coverage,median_nonlandmark_projection_distance=if(any(is.finite(projection_distance)))median(projection_distance,na.rm=TRUE)else NA_real_)
}
write.csv(do.call(rbind,rows),file.path(out,paste0(dataset,"_seed",seed,"_landmark.csv")),row.names=FALSE)
