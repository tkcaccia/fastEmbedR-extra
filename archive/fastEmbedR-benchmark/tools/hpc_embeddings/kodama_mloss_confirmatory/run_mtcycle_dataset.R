source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli(); require_capability("folds"); dataset<-args$dataset%||%stop("--dataset required"); seed<-as_int(args$seed,4L); backend<-args$backend%||%"cuda"; cores<-as_int(args$n_cores,4L)
out<-args$out_dir%||%stop("--out-dir required");dir.create(out,recursive=TRUE,showWarnings=FALSE)
lock<-read_release_lock(args$release_lock,args$image); d<-load_dataset(dataset,args$data_root);write_manifest(out,lock,dataset,backend,seed,list(protocol="mtcycle-v1"))
gt<-run_timed(kodamaR::KODAMA.graph(d$x,k=100L,backend=backend,n.cores=cores,seed=seed)); graph<-gt$value
fits<-list();rows<-list()
for(cl in c("knn","pls_lda")) for(M in c(20L,50L,100L)) for(Tcycle in c(20L,50L,100L)){
  key<-paste(cl,M,Tcycle,sep="_"); ft<-run_timed(do.call(kodamaR::KODAMA.matrix,list(data=d$x,graph=graph,M=M,Tcycle=Tcycle,folds=5L,ncomp=min(50L,d$p),
    landmarks=10000000L,splitting=if(d$n<40000)100L else 300L,n.cores=cores,graph.neighbors=100L,knn.k=30L,classifier=cl,backend=backend,seed=seed,visual.init=FALSE,progress=TRUE)))
  fit<-ft$value; fits[[key]]<-fit; a<-fit_accuracy(fit)
  vt<-run_timed(kodama_embedding(fit,"UMAP",backend,cores,seed)); qm<-layout_metrics(d$x,vt$value,d$labels,seed)
  rows[[key]]<-data.frame(dataset=dataset,seed=seed,classifier=cl,M=M,Tcycle=Tcycle,backend=backend,status="success",
    graph_runtime_sec=gt$elapsed,runtime_sec=ft$elapsed,best_cv_accuracy=a[["best"]],median_cv_accuracy=a[["median"]],
    visualization_runtime_sec=vt$elapsed,active_classes=active_classes(fit),ari=ari(d$labels,fit$best_labels),
    silhouette=qm$silhouette,preserve30=qm$preserve30,graph_rmse_vs_100=NA_real_)
}
graph_rmse<-function(a,b){ if(!identical(dim(a$knn$distances),dim(b$knn$distances)))return(NA_real_);sqrt(mean((a$knn$distances-b$knn$distances)^2)) }
for(key in names(fits)){z<-strsplit(key,"_")[[1]];ref<-fits[[paste(z[1],"100","100",sep="_")]]; rows[[key]]$graph_rmse_vs_100<-graph_rmse(fits[[key]],ref)}
write.csv(do.call(rbind,rows),file.path(out,paste0(dataset,"_seed",seed,"_mtcycle.csv")),row.names=FALSE)
