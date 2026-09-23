source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();require_capability("folds");require_capability("search.mode")
dataset<-args$dataset%||%stop("--dataset required");seed<-as_int(args$seed,4L);backend<-args$backend%||%"cpu";cores<-as_int(args$n_cores,1L)
out<-args$out_dir%||%stop("--out-dir required");dir.create(out,recursive=TRUE,showWarnings=FALSE)
lock<-read_release_lock(args$release_lock,args$image);d<-load_dataset(dataset,args$data_root);write_manifest(out,lock,dataset,backend,seed,list(protocol="backend-v1"))
rows<-list()
for(search_mode in c("exact","production")){
 gt<-run_timed(do.call(kodamaR::KODAMA.graph,list(data=d$x,k=100L,metric="euclidean",backend=backend,n.cores=cores,seed=seed,search.mode=search_mode)))
 for(cl in c("knn","pls_lda")){
  ft<-run_timed(do.call(kodamaR::KODAMA.matrix,list(data=d$x,graph=gt$value,M=100L,Tcycle=100L,folds=5L,ncomp=min(50L,d$p),landmarks=10000000L,
   splitting=if(d$n<40000)100L else 300L,n.cores=cores,graph.neighbors=100L,knn.k=30L,classifier=cl,backend=backend,seed=seed,visual.init=TRUE,progress=TRUE)))
  for(method in c("UMAP","opentsne")){vt<-run_timed(kodama_embedding(ft$value,method,backend,cores,seed));q<-layout_metrics(d$x,vt$value,d$labels,seed)
   key<-paste(search_mode,cl,method,sep="_");rows[[key]]<-data.frame(dataset=dataset,seed=seed,backend=backend,n_cores=cores,search_mode=search_mode,
    classifier=cl,visualization=method,status="success",graph_sec=gt$elapsed,cv_evolution_sec=ft$elapsed,
    visualization_sec=vt$elapsed,end_to_end_sec=gt$elapsed+ft$elapsed+vt$elapsed,trustworthiness=q$trustworthiness,
    preserve30=q$preserve30,silhouette=q$silhouette,ari=ari(d$labels,ft$value$best_labels),active_classes=active_classes(ft$value))}
 }
}
write.csv(do.call(rbind,rows),file.path(out,paste0(dataset,"_",backend,"_",cores,"c_seed",seed,"_backend.csv")),row.names=FALSE)
