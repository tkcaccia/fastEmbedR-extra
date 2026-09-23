source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();require_capability("folds");require_capability("ablation");require_capability("landmark.selection")
dataset<-args$dataset%||%stop("--dataset required");seed<-as_int(args$seed,4L);backend<-args$backend%||%"cuda";cores<-as_int(args$n_cores,4L)
out<-args$out_dir%||%stop("--out-dir required");dir.create(out,recursive=TRUE,showWarnings=FALSE)
lock<-read_release_lock(args$release_lock,args$image);d<-load_dataset(dataset,args$data_root);write_manifest(out,lock,dataset,backend,seed,list(protocol="ablation-v1"))
g<-kodamaR::KODAMA.graph(d$x,k=100L,backend=backend,n.cores=cores,seed=seed)
variants<-list(accepted=list(),random_proposal=list(prediction_guided=FALSE),fixed_proposal=list(adaptive_proposal_size=FALSE),
 previous_temperature=list(error_scaled_temperature=FALSE),no_degeneracy_guard=list(degeneracy_guard=FALSE),
 no_transition_coarsening=list(transition_coarsening=FALSE),no_pls_fragmentation=list(pls_fragmentation=FALSE))
rows<-list()
for(cl in c("knn","pls_lda"))for(v in names(variants)){
 ft<-run_timed(do.call(kodamaR::KODAMA.matrix,list(data=d$x,graph=g,M=100L,Tcycle=100L,folds=5L,ncomp=min(50L,d$p),landmarks=10000000L,
  landmark.selection="exact_quota",splitting=if(d$n<40000)100L else 300L,n.cores=cores,graph.neighbors=100L,knn.k=30L,classifier=cl,
  backend=backend,seed=seed,visual.init=TRUE,progress=TRUE,ablation=variants[[v]])))
 vt<-run_timed(kodama_embedding(ft$value,"UMAP",backend,cores,seed));q<-layout_metrics(d$x,vt$value,d$labels,seed);a<-fit_accuracy(ft$value)
 rows[[paste(cl,v)]]<-data.frame(dataset=dataset,seed=seed,classifier=cl,variant=v,best_cv_accuracy=a[["best"]],median_cv_accuracy=a[["median"]],
  silhouette=q$silhouette,ari=ari(d$labels,ft$value$best_labels),active_classes=active_classes(ft$value),collapsed=active_classes(ft$value)<=1L,
  runtime_sec=ft$elapsed+vt$elapsed)
}
write.csv(do.call(rbind,rows),file.path(out,paste0(dataset,"_seed",seed,"_ablation.csv")),row.names=FALSE)

