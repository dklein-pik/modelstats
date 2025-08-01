#' promptAndRun
#'
#' prompts runs, will be called by rs2
#'
#' @param mydir a dir or vector of dirs
#' @param user the user whose runs will be shown. For -t, the pattern used for matching
#' @param daysback integer defining the number of days -c will look back in time to find runs
#'
#' @author Anastasis Giannousakis, Oliver Richters
#' @import crayon
#' @importFrom gtools mixedsort mixedorder
#' @export
#' @examples
#' \dontrun{
#'   promptAndRun()
#' }
#'

# Temporary note: this function is called by rs2 
# with the following arguments coming from the command line
# "$2" == number -> promptAndRun('$1', ''  , '$2') # only daysback
# "$2" == string -> promptAndRun('$1', '$2', '$3') # parameter and daysback

promptAndRun <- function(mydir = ".", user = NULL, daysback = 3) {
  mydir <- strsplit(mydir, ',')[[1]]
  colors <- ! any(grepl("^-.*b.*", mydir))
  
### AMTs ### rs2 -t
  if (isTRUE(mydir == "-t")) {
    amtPath <- "/p/projects/remind/modeltests/remind/output/"
    cat("Results from", amtPath, "\n")
    amtPattern <- if (is.null(user) || user == "") readRDS("/p/projects/remind/modeltests/remind/runcode.rds") else user
    amtDirs <- dir(path = amtPath, pattern = amtPattern, full.names = TRUE)
    loopRuns(amtDirs, user = NULL, colors = colors, sortbytime = FALSE)
    return(invisible())
  }
  
  if (is.null(user) || user == "") user <- Sys.info()[["user"]]
  if (daysback == "") daysback <- 3
  if (isFALSE(colors) && grepl("^-[a-zA-Z]+", mydir)) mydir <- gsub("b", "", mydir)
  
  if (isTRUE(mydir == ".")) {
### CURRENT FOLDER: list single run ### rs2 .
    loopRuns(".", user = user, colors = colors)
  } else if (length(mydir) == 0 || isTRUE(mydir == "")) {
    # detect if in run folder or in main folder
    if (sum(file.exists(c("full.gms", "log.txt", "config.Rdata", "prepare_and_run.R", "prepareAndRun.R"))) >= 4 ||
        sum(file.exists(c("full.gms", "submit.R", "config.yml", "magpie_y1995.gdx"))) == 4) {
### IN RUN FOLDER: list single run ### rs2
      loopRuns(".", user = user, colors = colors)
    } else {
### IN MAIN FOLDER: prompt list of all runs in "output" ### rs2
      folder <- if (sum(file.exists(c("output", "output.R", "start.R", "main.gms"))) == 4) "./output" else "."
      dirs <- c(folder, list.dirs(folder, recursive = FALSE))
      chosendirs <- gms::chooseFromList(dirs, type = "folders")
      loopRuns(if (length(chosendirs) == 0) "exit" else chosendirs, user = user, sortbytime = FALSE)
    }
  } else if (isTRUE(mydir %in% c("-d", "-f"))) {
### IN CURRENT OR IN MAIN FOLER: list alphabetically (-d) or by time (-f)
    folder <- if (sum(file.exists(c("output", "output.R", "start.R", "main.gms"))) == 4) "output" else "."
    # load all directories with a config file plus all that look like coupled runs to include them if they are pending
    loopRuns(list.dirs(folder, recursive = FALSE), user = user, colors = colors, sortbytime = mydir %in% "-f")
  } else if (isTRUE(mydir %in% c("-p", "-s"))) {
### COUPLED RUNS
    folders <- if (sum(file.exists(c("output", "output.R", "start.R", "main.gms"))) == 4) "output" else "."
    if (isTRUE(mydir %in% "-p") && dir.exists(file.path("magpie", "output"))) folders <- c(folders, file.path("magpie", "output"))
    dirs <- NULL
    for (folder in folders) {
      fdirs <- mixedsort(grep("-(rem|mag)-[0-9]+$", basename(list.dirs(folder, recursive = FALSE)), value = TRUE), scientific = FALSE, numeric.type = "decimal")
      if (isTRUE(mydir %in% "-p")) {
        dirs <- c(dirs, file.path(folder, fdirs))
      } else { # -s shows only last run
        lastdirs <- NULL
        for (r in unique(gsub("-(rem|mag)-[0-9]+$", "", fdirs))) {
          lastdirs <- c(lastdirs, fdirs[min(which(gsub("-(rem|mag)-[0-9]+$", "", fdirs) == r))])
        }
        dirs <- c(dirs, file.path(folder, lastdirs))
      }
      fdirs <- grep("-(rem|mag)-[0-9]+$", basename(list.dirs(folder, recursive = FALSE)), value = TRUE, invert = TRUE)
      fdirs <- fdirs[mixedorder(gsub("-", "", fdirs), scientific = FALSE, numeric.type = "decimal")]
      if (isTRUE(mydir %in% "-p")) {
        dirs <- c(dirs, file.path(folder, fdirs))
      } else {
        lastdirs <- NULL
        for (r in unique(gsub("_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}\\.[0-9]{2}\\.[0-9]{2}$", "", fdirs))) {
          lastdirs <- c(lastdirs, fdirs[max(which(gsub("_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}\\.[0-9]{2}\\.[0-9]{2}$", "", fdirs) == r))])
        }
        dirs <- c(dirs, file.path(folder, lastdirs))
      }
    }
    # order and make sure rem-1 is not interpreted as negative number
    dirs <- dirs[mixedorder(gsub("-", "", dirs), scientific = FALSE, numeric.type = "decimal")]
    loopRuns(dirs, user = user, colors = colors, sortbytime = FALSE)
  } else if (all(mydir %in% c("-cr", "-a", "-c"))) {
### CURRENT OR ACTIVE RUNS
    myruns   <- system(paste0("squeue -u ", user, " -h -o '%Z'"), intern = TRUE)
    runnames <- system(paste0("squeue -u ", user, " -h -o '%j'"), intern = TRUE)

    if (all(mydir %in% c("-cr", "-c"))) {
      sacctcode <- paste0("sacct -u ", user, " -s cd,f,cancelled,timeout,oom -S ", as.Date(format(Sys.Date(), "%Y-%m-%d")) - as.numeric(daysback), " -E now -P -n")
      myruns   <- c(myruns,   system(paste(sacctcode, "--format WorkDir"), intern = TRUE))
      runnames <- c(runnames, system(paste(sacctcode, "--format JobName"), intern = TRUE))
    }

    if (any(grepl("mag-run", runnames))) {
      deleteruns <- which(runnames %in% c("default", "batch"))
    } else {
      deleteruns <- which(runnames %in% c("batch"))
    }
    if (length(deleteruns) > 0) {
      myruns <- myruns[-deleteruns]
      runnames <- runnames[-deleteruns]
    }

    if (length(myruns) == 0) {
      return(paste0("No runs found for this user. You can change the reporting period (here: 5 days) by running 'rs2 -c ", user, " 5"))
    }
    # add REMIND-MAgPIE coupled runs where run directory is not the output directory
    # these lines also drops all other slurm jobs such as remind preprocessing etc.
    coupled <- rem <- NULL
    for (i in 1:length(runnames)) {
      if (! any(grepl(runnames[[i]], myruns[[i]]), grepl("mag-run", runnames[[i]]))) {
        coupled <- c(coupled, paste0(myruns[[i]], "/output/", runnames[[i]])) # for coupled runs in parallel mode
        rem <- c(rem, i)
      }
    }
    if (!is.null(rem)) {
      myruns <- myruns[-rem] # remove coupled parent-job and all other slurm jobs
      myruns <- c(myruns, coupled) # add coupled paths
    }
    myruns <- myruns[file.exists(myruns)] # keep only existing paths
    myruns <- sort(unique(myruns[!is.na(myruns)]))

    if (length(myruns) == 0) {
      return("No runs found for this user. To change the reporting period (days) you need to specify also a user, e.g. rs2 -c USER 1")
    } else {
      message("")
      message("Found ", length(myruns), if (mydir == "-a") " active", " runs.",
              if (length(myruns)/as.numeric(daysback) > 20) " Excuse me? You need a cluster only for yourself it seems.")
    }
    print(myruns[1:min(100, length(myruns))])
    loopRuns(myruns, user = user, colors = colors, sortbytime = FALSE)
  } else {
### PATHs or REGEX 
    mydir <- ifelse(! dir.exists(mydir) & dir.exists(file.path("output", mydir)), file.path("output", mydir), mydir)
    user <- mydir
    if (! all(dir.exists(mydir))) {
      folder <- if (sum(file.exists(c("output", "output.R", "start.R", "main.gms"))) == 4) "./output" else "."
      mydir <- c(mydir[dir.exists(mydir)],
                 grep(paste0(mydir[! dir.exists(mydir)], collapse = "|"), list.dirs(folder, recursive = FALSE), value = TRUE))
    }
    # if mydir yields no results it may be a user name -> try with username
    if (length(mydir) == 0) {
      message(paste0("Did not find any runs for ", user, ". Looking for runs of user ", user))
      promptAndRun(mydir = "-c", user = user, daysback = daysback)
    }
    loopRuns(mydir, user = user, colors = colors, sortbytime = FALSE)
  }
}
