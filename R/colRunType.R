#' colRunType
#'
#' What is the type of this run?
#'
#' @param dir Path to the folder(s) where the run(s) is(are) performed
#'
#'
#' @author Anastasis Giannousakis
#' @export
colRunType<-function(mydir="."){

  cfgf <- paste0(mydir,"/config.Rdata")
  fulllst <- paste0(mydir,"/full.lst")
  
  if (file.exists(cfgf)) {
    load(cfgf)
    out <- cfg[["gms"]][["optimization"]]
    if (cfg[["gms"]][["CES_parameters"]]=="calibrate") out<-paste0("Calib_",out)
  } else if (file.exists(fulllst)) {
    out <- sub("         !! def = nash","",sub("^ .*.ion  ","",system(paste0("grep 'setGlobal optimization  ' ",fulllst),intern=TRUE)))
    chck <- sub("       !! def = load","",sub("^ .*.ers  ","",system(paste0("grep 'setglobal CES_parameters  ' ",fulllst),intern=TRUE)))
    if (chck=="calibrate") out <- paste0("Calib_",out)
  }
  return(out)

}
