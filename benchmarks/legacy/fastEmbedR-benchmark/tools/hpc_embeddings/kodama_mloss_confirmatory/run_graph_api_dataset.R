source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();require_capability("folds");dataset<-args$dataset%||%stop("--dataset required");seed<-as_int(args$seed,4L);backend<-args$backend%||%"cuda";cores<-as_int(args$n_cores,4L)
out<-args$out_dir%||%stop("--out-dir required");dir.create(out,recursive=TRUE,showWarnings=FALSE)
lock<-read_release_lock(args$release_lock,args$image);d<-load_dataset(dataset,args$data_root);write_manifest(out,lock,dataset,backend,seed,list(protocol="graph-api-v1"))
gt<-run_timed(kodamaR::KODAMA.graph(d$x,k=100L,backend=backend,n.cores=cores,seed=seed));g<-gt$value
modes<-list(raw_only=list(data=d$x),raw_plus_graph=list(data=d$x,graph=g),graph_only=list(graph=g),bare_knn=list(graph=list(indices=g$indices,distances=g$distances)))
rows<-list();fits<-list()
for(cl in c("knn","pls_lda"))for(mode in names(modes)){
 a<-c(modes[[mode]],list(M=100L,Tcycle=100L,folds=5L,ncomp=min(50L,d$p),landmarks=10000000L,splitting=if(d$n<40000)100L else 300L,
  n.cores=cores,graph.neighbors=100L,knn.k=30L,classifier=cl,backend=backend,seed=seed,visual.init=FALSE,progress=TRUE))
 ft<-run_timed(do.call(kodamaR::KODAMA.matrix,a));fits[[paste(cl,mode)]]<-ft$value; ac<-fit_accuracy(ft$value)
 rows[[paste(cl,mode)]]<-data.frame(dataset=dataset,seed=seed,classifier=cl,input_mode=mode,backend=backend,runtime_sec=ft$elapsed,
  graph_precompute_sec=if(mode=="raw_only")0 else gt$elapsed,best_cv_accuracy=ac[["best"]],active_classes=active_classes(ft$value),
  ari=ari(d$labels,ft$value$best_labels),representation=if(cl=="pls_lda"&&mode%in%c("graph_only","bare_knn"))"spectral_graph_features"else"raw_features")
}
ref<-fits[["knn raw_plus_graph"]]
for(nm in names(rows)){f<-fits[[nm]];rows[[nm]]$label_ari_vs_raw_plus_graph<-ari(ref$best_labels,f$best_labels);rows[[nm]]$graph_rmse_vs_raw_plus_graph<-if(identical(dim(ref$knn$distances),dim(f$knn$distances)))sqrt(mean((ref$knn$distances-f$knn$distances)^2))else NA_real_}
write.csv(do.call(rbind,rows),file.path(out,paste0(dataset,"_seed",seed,"_graph_api.csv")),row.names=FALSE)
