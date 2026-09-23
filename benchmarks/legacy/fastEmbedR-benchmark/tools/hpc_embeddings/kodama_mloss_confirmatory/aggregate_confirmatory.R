source(file.path(dirname(sub("^--file=", "", commandArgs(FALSE)[grepl("^--file=", commandArgs(FALSE))][1L])), "common.R"))
args <- parse_cli(); root <- args$result_root %||% stop("--result-root is required"); out <- args$out_dir %||% file.path(root,"aggregate")
dir.create(out,recursive=TRUE,showWarnings=FALSE)
files <- list.files(root,pattern="_confirmatory\\.csv$",recursive=TRUE,full.names=TRUE)
if (!length(files)) stop("No confirmatory CSV files found.")
raw <- do.call(rbind,lapply(files,read.csv,stringsAsFactors=FALSE)); raw <- raw[raw$status=="success",,drop=FALSE]
write.csv(raw,file.path(out,"confirmatory_all_rows.csv"),row.names=FALSE)
keys <- c("dataset","classifier","visualization","variant","backend")
metrics <- c("workflow_runtime_sec","trustworthiness","preserve30","silhouette","label_knn_accuracy","distance_spearman","ari","active_classes")
med <- aggregate(raw[metrics],raw[keys],function(z) median(z[is.finite(z)],na.rm=TRUE))
write.csv(med,file.path(out,"confirmatory_dataset_seed_medians.csv"),row.names=FALSE)

contrasts <- expand.grid(classifier=c("knn","pls_lda"),visualization=c("UMAP","opentsne"),stringsAsFactors=FALSE)
all_effects <- list(); tests <- list(); set.seed(20260806)
for (i in seq_len(nrow(contrasts))) {
  cl <- contrasts$classifier[i]; vis <- contrasts$visualization[i]
  k <- med[med$classifier==cl & med$visualization==vis & med$variant=="kodama",]
  b <- med[med$classifier=="none" & med$visualization==vis & med$variant=="classic",]
  m <- merge(k,b,by=c("dataset","visualization","backend"),suffixes=c("_kodama","_classic"))
  m$classifier <- cl; m$delta_silhouette <- m$silhouette_kodama-m$silhouette_classic
  m$delta_trustworthiness <- m$trustworthiness_kodama-m$trustworthiness_classic
  m$delta_preserve30 <- m$preserve30_kodama-m$preserve30_classic
  kr <- raw[raw$classifier==cl & raw$visualization==vis & raw$variant=="kodama",]
  br <- raw[raw$classifier=="none" & raw$visualization==vis & raw$variant=="classic",]
  sr <- merge(kr,br,by=c("dataset","seed","visualization","backend"),suffixes=c("_kodama","_classic"))
  sr$delta <- sr$silhouette_kodama-sr$silhouette_classic
  dataset_ci <- lapply(m$dataset,function(ds){z<-sr$delta[sr$dataset==ds & is.finite(sr$delta)];if(!length(z))return(c(NA,NA));
    bz<-replicate(5000L,median(sample(z,length(z),replace=TRUE)));unname(quantile(bz,c(.025,.975)))})
  m$dataset_ci_low <- vapply(dataset_ci,`[`,numeric(1),1L)
  m$dataset_ci_high <- vapply(dataset_ci,`[`,numeric(1),2L)
  all_effects[[i]] <- m
  d <- m$delta_silhouette[is.finite(m$delta_silhouette)]; nd <- length(d)
  boot <- if (nd) replicate(10000L,median(sample(d,nd,replace=TRUE))) else NA_real_
  wilcox_p <- if (nd && requireNamespace("coin",quietly=TRUE)) {
    as.numeric(coin::pvalue(coin::wilcoxsign_test(d ~ 1,distribution="exact")))
  } else NA_real_
  nonzero <- d[d!=0]
  sign_p <- if (length(nonzero)) binom.test(sum(nonzero>0),length(nonzero),p=.5)$p.value else NA_real_
  tests[[i]] <- data.frame(classifier=cl,visualization=vis,n_datasets=nd,n_improved=sum(d>0),
    median_delta=if(nd)median(d) else NA,ci_low=if(nd)quantile(boot,.025) else NA,
    ci_high=if(nd)quantile(boot,.975) else NA,wilcoxon_exact_p=wilcox_p,sign_test_p=sign_p)
}
effects <- do.call(rbind,all_effects); stats <- do.call(rbind,tests)
stats$wilcoxon_holm <- p.adjust(stats$wilcoxon_exact_p,"holm"); stats$sign_holm <- p.adjust(stats$sign_test_p,"holm")
write.csv(effects,file.path(out,"confirmatory_dataset_effects.csv"),row.names=FALSE)
write.csv(stats,file.path(out,"confirmatory_paired_inference.csv"),row.names=FALSE)

png(file.path(out,"confirmatory_silhouette_forest.png"),width=2200,height=1600,res=220)
op <- par(mfrow=c(2,2),mar=c(4,8,2,1)); on.exit({par(op);dev.off()},add=TRUE)
for(i in seq_len(nrow(contrasts))){
  z <- all_effects[[i]]; z <- z[order(z$delta_silhouette),]
  plot(z$delta_silhouette,seq_len(nrow(z)),pch=19,yaxt="n",xlab="KODAMA - classic silhouette",ylab="",
       main=paste(contrasts$classifier[i],contrasts$visualization[i])); axis(2,seq_len(nrow(z)),z$dataset,las=2,cex.axis=.7);abline(v=0,lty=2)
  segments(z$dataset_ci_low,seq_len(nrow(z)),z$dataset_ci_high,seq_len(nrow(z)))
}
