source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args<-parse_cli();dataset<-args$dataset%||%"MetRef";backend<-args$backend%||%"cpu";seed<-as_int(args$seed,4L);cores<-as_int(args$n_cores,1L)
out<-args$out_dir%||%stop("--out-dir required");dir.create(out,recursive=TRUE,showWarnings=FALSE)
lock<-read_release_lock(args$release_lock,args$image);d<-load_dataset(dataset,args$data_root);write_manifest(out,lock,dataset,backend,seed,list(protocol="wrapper-parity-v1"))
rows<-sample_rows(d$n,min(2000L,d$n),seed);x<-d$x[rows,,drop=FALSE]
input<-list(data=x,seed=seed,k=30L,M=20L,Tcycle=20L);saveRDS(input,file.path(out,"serialized_wrapper_input.rds"),compress=FALSE)
g<-kodamaR::KODAMA.graph(x,k=30L,backend=backend,n.cores=cores,seed=seed)
fit<-kodamaR::KODAMA.matrix(data=x,graph=g,M=20L,Tcycle=20L,ncomp=min(20L,ncol(x)),landmarks=10000000L,
 splitting=min(100L,nrow(x)-1L),n.cores=cores,graph.neighbors=30L,knn.k=30L,classifier="knn",backend=backend,seed=seed,progress=FALSE)
rout<-list(labels=fit$best_labels,accuracy=fit$acc,indices=fit$knn$indices,distances=fit$knn$distances,
 visual_init=fit$visual_init,backend=fit$backend%||%backend);saveRDS(rout,file.path(out,"r_wrapper_output.rds"),compress=FALSE)

python_driver<-args$python_driver%||%Sys.getenv("KODAMA_PYTHON_PARITY_DRIVER","")
cpp_driver<-args$cpp_driver%||%Sys.getenv("KODAMA_CPP_PARITY_DRIVER","")
status<-data.frame(interface=c("R","Python","C++"),status=c("success","not_run","not_run"),detail=c("R wrapper completed","driver not supplied","driver not supplied"))
if(nzchar(python_driver)){rc<-system2(python_driver,c(file.path(out,"serialized_wrapper_input.rds"),file.path(out,"python_output.npz")));status$status[2]<-if(rc==0)"success"else"failed";status$detail[2]<-paste("exit",rc)}
if(nzchar(cpp_driver)){rc<-system2(cpp_driver,c(file.path(out,"serialized_wrapper_input.rds"),file.path(out,"cpp_output.bin")));status$status[3]<-if(rc==0)"success"else"failed";status$detail[3]<-paste("exit",rc)}
write.csv(status,file.path(out,"wrapper_validation_status.csv"),row.names=FALSE)
if(any(status$status=="failed"))quit(status=2L)

