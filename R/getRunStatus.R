#' getRunStatus
#'
#' Returns the current status of a run or a vector of runs
#'
#' @param mydir Path to the folder(s) where the run(s) is(are) performed
#' @param sort how to sort (nf=newest first)
#' @param user the user whose runs will be shown
#'
#' @author Anastasis Giannousakis
#' @examples
#' \dontrun{
#'
#' a <- getRunStatus(dir())
#' }
#'
#' @importFrom gdx readGDX
#' @importFrom utils head tail
#' @importFrom gms loadConfig
#' @importFrom piamutils niceround
#' @export
getRunStatus <- function(mydir = dir(), sort = "nf", user = NULL) {

  if (is.null(user)) user <- Sys.info()[["user"]]
  mydir <- normalizePath(mydir)

  onCluster <- file.exists("/p")
  out <- data.frame()

  a <- file.info(mydir)
  a <- a[a[, "isdir"] == TRUE, ]
  if (sort == "nf") mydir <- rownames(a[order(a[, "mtime"], decreasing = TRUE), ])

  for (i in mydir) {
    ii <- i
    i <- sub(paste0(dirname(i), "/"), "", i)

    out[i, "jobInSLURM"] <- if (onCluster) foundInSlurm(ii, user) else "NA"

    # Define files
    cfgf            <- grep("config.Rdata|config.yml", dir(ii), value = TRUE)
    fle             <- file.path(ii, "runstatistics.rda")
    gdx             <- file.path(ii, "fulldata.gdx")
    gdx_non_optimal <- file.path(ii, "non_optimal.gdx")
    fullgms         <- file.path(ii, "full.gms")
    fulllog         <- file.path(ii, "full.log")
    logtxt          <- file.path(ii, "log.txt")
    logmagtxt       <- file.path(ii, "log-mag.txt")
    abortgdx        <- file.path(ii, "abort.gdx")
    if (! file.exists(logmagtxt)) logmagtxt <- logtxt
    # select latest gdx file based on iteration, or if that fails based on timestamp
    gdxfiles <- c(gdx, gdx_non_optimal)[file.exists(c(gdx, gdx_non_optimal))]
    latest_gdx <- head(gdxfiles, 1)
    if (length(gdxfiles) > 1) {
      itergdx <- as.numeric(unlist(lapply(gdxfiles, readGDX, "o_iterationNumber", format = "simplest", react = "silent")))
      if (length(itergdx) == length(gdxfiles)) {
        latest_gdx <- gdxfiles[which.max(itergdx)]
      } else {
        fileInfo <- file.info(gdxfiles)
        latest_gdx <- rownames(fileInfo)[which.max(fileInfo$mtime)]
      }
    }

    # Initialize objects
    cfg <- NULL
    # Runtype and load cfg
    if (length(cfgf) == 0) {
      out[i, "RunType"] <- "NA"
    } else {
      ifelse(grepl("yml$", cfgf), cfg <- loadConfig(paste0(ii, "/", cfgf)), load(paste0(ii, "/", cfgf)))
      out[i, "RunType"] <- colRunType(ii)
    }

    runstatistics <- new.env()
    if (file.exists(fle)) {
      suppressWarnings(load(fle, envir = runstatistics))
    }

    # modelstat
    out[i, "modelstat"] <- "NA"
    if (length(latest_gdx) > 0) {
      o_modelstat <- try(c(readGDX(gdx = latest_gdx, c("o_modelstat", "p80_modelstat"), format = "first_found", react = "silent")), silent = TRUE)
      if (! is.null(o_modelstat) && ! inherits(o_modelstat, "try-error")) {
        out[i, "modelstat"] <- gsub("0", ".", paste0(o_modelstat, collapse = ""))
      }
    }
    if (out[i, "modelstat"] == "NA") {
      if (! is.null(runstatistics$stats) && any(grepl("config", names(runstatistics$stats)))) {
        if (runstatistics$stats[["config"]][["model_name"]] == "MAgPIE") {
          if (any(grepl("modelstat", names(runstatistics$stats)))) out[i, "modelstat"] <- paste0(as.character(runstatistics$stats[["modelstat"]]), collapse = "")
        } else {
          if (any(grepl("modelstat", names(runstatistics$stats)))) try(out[i, "modelstat"] <- runstatistics$stats[["modelstat"]], silent = TRUE)
        }
      }
    }
    explain_modelstat <- c("1" = "Optimal", "2" = "Locally Optimal", "3" = "Unbounded", "4" = "Infeasible",
                           "5" = "Locally Infes", "6" = "Intermed Infes", "7" = "Intermed Nonoptimal", "13" = "Error No Solution")
    if (out[i, "modelstat"] %in% names(explain_modelstat)) {
      out[i, "modelstat"] <- paste0(out[i, "modelstat"], ": ", explain_modelstat[out[i, "modelstat"]])
    }

    # runInAppResults
    if (onCluster) {
      out[i, "runInAppResults"] <- "no"
      if (any(grepl("id", names(runstatistics$stats)))) {
        if (any(grepl("config", names(runstatistics$stats))) && runstatistics$stats[["config"]][["model_name"]] == "MAgPIE") {
          ovdir <- "/p/projects/rd3mod/models/results/magpie/"
        } else {
          ovdir <- "/p/projects/rd3mod/models/results/remind/"
        }
        try(id <- paste0(ovdir, runstatistics$stats[["id"]], ".rds"))
        if (file.exists(id) && all((file.info(Sys.glob(paste0(ovdir, "overview.rds")))$mtime + 600) > file.info(id)$mtime)) {
          out[i, "runInAppResults"] <- "yes"
        }
      }
    }

    # MIF
    out[i, "Mif"] <- "NA"

    if (length(cfgf) != 0 && file.exists(paste0(ii, "/", cfgf))) {
      if (isTRUE(runstatistics$stats[["config"]][["model_name"]] == "MAgPIE")) {
        miffile <- paste0(ii, "/validation.mif")
        out[i, "Mif"] <- if (file.exists(miffile) && file.info(miffile)[["size"]] > 99999) "yes" else "no"
      } else {
        miffile    <- paste0(ii, "/REMIND_generic_", cfg[["title"]], ".mif")
        sumErrFile <- paste0(ii, "/REMIND_generic_", cfg[["title"]], "_summation_errors.csv")
        if (! file.exists(miffile)) {
          out[i, "Mif"] <- "no"
        } else if (file.exists(sumErrFile)) {
          out[i, "Mif"] <- "sumErr"
        } else {
          out[i, "Mif"] <- "yes"
        }
      }
    }

    # Iter
    cm_iteration_max <- cfg$gms$cm_iteration_max
    if (isTRUE(cfg$gms$cm_nash_autoconverge > 0) && grepl("nash", out[i, "RunType"])) {
      if (file.exists(fullgms)) {
        cm_iteration_max <- suppressWarnings(system(paste0("tac '", fullgms, "' | grep -m 1 'cm_iteration_max = [1-9].*.;[ ]*$'"), intern = TRUE))
        cm_iteration_max <- sub(";[ ]*", "", sub("^.*.= ", "", cm_iteration_max))
      }
    }
    out[i, "Iter"] <- "NA"
    out[i, "RunStatus"] <- "NA"
    if (file.exists(fulllog)) {
      suppressWarnings(try(loop <- sub("^.*.= ", "", system(paste0("grep 'LOOPS' '", fulllog, "' | tail -1"), intern = TRUE)), silent = TRUE))
      if (length(loop) > 0) out[i, "Iter"] <- loop
      if (length(cm_iteration_max) > 0) out[i, "Iter"] <- paste0(out[i, "Iter"], "/", cm_iteration_max)
      suppressWarnings(try(out[i, "RunStatus"] <- substr(sub("\\(s\\)", "", sub("\\*\\*\\* Status: ", "", system(paste0("grep '*** Status: ' '", fulllog, "'"), intern = TRUE))), start = 1, stop = 17), silent = TRUE))
      if (onCluster && out[i, "RunStatus"] == "NA") {
        if (out[i, "jobInSLURM"] == "no" || grepl("pending$", out[i, "jobInSLURM"])) {
          if (file.exists(logtxt)) {
            slurmerror <- NULL
            suppressWarnings(try(slurmerror <- system(paste0("grep 'slurmstepd.*error' ", logtxt), intern = TRUE), silent = TRUE))
            if (isTRUE(any(grepl("DUE TO TIME LIMIT", slurmerror)))) {
              out[i, "RunStatus"] <- "Timeout interrupt"
            } else if (isTRUE(any(grepl("memory|oom-kill", slurmerror)))) {
              out[i, "RunStatus"] <- "Memory interrupt"
            } else if (isTRUE(any(grepl("DUE TO PREEMPTION", slurmerror)))) {
              out[i, "RunStatus"] <- "Preempt interrupt"
            } else if (isTRUE(any(grepl("DUE TO JOB REQUEUE", slurmerror)))) {
              out[i, "RunStatus"] <- "Run requeued"
            } else if (isTRUE(any(grepl("CANCELLED", slurmerror)))) {
              out[i, "RunStatus"] <- "Run cancelled"
            }
          } else {
            out[i, "RunStatus"] <- if (out[i, "jobInSLURM"] == "no") "Run interrupted" else "Run restarted"
          }
        } else {
          out[i, "RunStatus"] <- "Run in progress"
          gridfiles <- Sys.glob(file.path(ii, "225*", "grid*", "gmsgrid.log"))
          if (length(gridfiles) > 0) {
            conoptdelay <- round(difftime(Sys.time(), max(file.info(gridfiles)$mtime), units = "hours") - 0.049, 1)
            gdxdelay <- 1
            if (length(latest_gdx) > 0 && file.exists(latest_gdx)) gdxdelay <- difftime(Sys.time(), file.info(latest_gdx)$mtime, units = "hours")
            if (conoptdelay > 0.1 && gdxdelay > 0.25) out[i, "RunStatus"] <- paste0("conoptspy >", niceround(conoptdelay, 1), "h")
          }
        }
      } else {
        if (out[i, "RunStatus"] == "NA") out[i, "RunStatus"] <- "Run interrupted"
      }
      if (out[i, "RunStatus"] == "Normal completion" && file.exists(logtxt) && out[i, "jobInSLURM"] != "no") {
        startrep <- suppressWarnings(system(paste0("tac '", logtxt, "' | grep -m 1 'Starting output generation for'"), intern = TRUE))
        endrep <- suppressWarnings(system(paste0("tac '", logtxt, "' | grep -m 1 'Finished output generation for'"), intern = TRUE))
        if (length(startrep) > length(endrep) && out[i, "jobInSLURM"] != "no") {
          out[i, "RunStatus"] <- "Running reporting"
        }
      }
      if (out[i, "RunStatus"] == "Execution error" && file.exists(abortgdx)) {
        # check if error was due to consecutive infes
        maxinfes <- try(as.numeric(readGDX(gdx = abortgdx, "cm_abortOnConsecFail", format = "simplest", react = "silent")), silent = TRUE)
        cf <- try(quitte::as.quitte(readGDX(gdx = abortgdx, "p80_trackConsecFail", react = "silent")), silent = TRUE)
        if (! inherits(maxinfes, "try-error") && isTRUE(maxinfes > 0) && ! inherits(cf, "try-error") && ! is.null(cf)) {
          cf <- unique(cf[cf$value == maxinfes, ]$region)
          if (length(cf) > 0) {
            cf <- if (length(cf) == 1) paste0(cf, " ") else paste0(length(cf), "R*")
            out[i, "RunStatus"] <- paste0("Abort ", cf, maxinfes, "*Infes")
          }
        }
      }
      if (file.exists(logmagtxt) && out[i, "jobInSLURM"] != "no" && (out[i, "RunStatus"] == "Normal completion" || grepl("log-mag.txt", logmagtxt))) {
        startmag <- suppressWarnings(system(paste0("tac '", logmagtxt, "' | grep -m 1 'Preparing MAgPIE'"), intern = TRUE))
        endmag <- suppressWarnings(system(paste0("tac '", logmagtxt, "' | grep -m 1 'MAgPIE output was stored'"), intern = TRUE))
        if (length(startmag) > length(endmag)) {
          fulllogmag <- gsub("-rem-", "-mag-", gsub("output", file.path("magpie", "output"), fulllog))
          if (! file.exists(fulllogmag)) fulllogmag <- gsub("-rem-", "-mag-", gsub("output", file.path("..", "magpie", "output"), fulllog))
          loopmag <- NULL
          if (file.exists(fulllogmag)) {
            suppressWarnings(try(loopmag <- sub("^.*.= ", "", system(paste0("grep 'LOOPS' '", fulllogmag, "' | tail -1"), intern = TRUE)), silent = TRUE))
          }
          if (length(suppressWarnings(system(paste0("tac '", logmagtxt, "' | grep -m 1 'Start getReport'"), intern = TRUE)) > 0)) loopmag <- "report"
          out[i, "RunStatus"] <- paste("Run MAgPIE", loopmag)
        }
        if (isTRUE(grepl("try to acquire model lock", try(system(paste("tail -1", logmagtxt), intern = TRUE), silent = TRUE)))) {
          out[i, "RunStatus"] <- "Wait MAgPIE lock"
        }

      }
    } else if (file.exists(logtxt) && isTRUE(grepl("try to acquire model lock", try(system(paste("tail -1", logtxt), intern = TRUE), silent = TRUE)))) {
      out[i, "RunStatus"] <- "Wait REMIND lock"
    } else {
      out[i, "RunStatus"] <- "full.log missing"
    }

    # Conv
    out[i, "Conv"] <- "NA"
    if (exists("cfg") && isTRUE(grepl("nash", out[i, "RunType"])) && length(latest_gdx) > 0) {
      iter_no  <- try(as.numeric(readGDX(gdx = latest_gdx, "o_iterationNumber", format = "simplest")), silent = TRUE)
      s80_bool <- try(as.numeric(readGDX(gdx = latest_gdx, "s80_bool", types = "parameters", format = "simplest")), silent = TRUE)
      if (! inherits(s80_bool, "try-error") && ! inherits(iter_no, "try-error")) {
        if (s80_bool == 1) {
          out[i, "Conv"] <- if (file.exists(gdx_non_optimal)) "converged (had INFES)" else "converged"
        } else if (s80_bool == 0 && as.numeric(cm_iteration_max) == iter_no) {
          out[i, "Conv"] <- "not_converged"
        } else {
          p80_repy <- try(readGDX(gdx = latest_gdx, "p80_repy"), silent = TRUE)
          if (! inherits(p80_repy, "try-error")) {
            out[i, "Conv"] <- paste(p80_repy[, , "modelstat"], collapse = "")
          }
        }
      }
    }
    # END Conv

    # Calib Iter
    if ((isTRUE(grepl("Calib", out[i, "RunType"])) || isTRUE(cfg$gms$CES_parameters == "calibrate")) && file.exists(logtxt)) {
      calibiter <- tail(suppressWarnings(system(paste0("grep 'CES calibration iteration' '", logtxt, "' |  grep -Eo  '[0-9]{1,2}'"), intern = TRUE)), n = 1)
      if (isTRUE(as.numeric(calibiter) > 0)) out[i, "Iter"] <- paste0(out[i, "Iter"], " ", "Clb: ", calibiter)
      if (isTRUE(out[i, "Conv"] %in% c("converged", "converged (had INFES)")) &&
          (length(system(paste0("find ", ii, " -name 'fulldata_*.gdx'"), intern = TRUE)) > 10 ||
           length(system(paste0("find ", ii, " -name 'input_*.gdx'"), intern = TRUE)) > 10)) {
        out[i, "Conv"] <- "Clb_converged"
      }
    }

    # Runtime
    out[i, "Runtime"] <- NA
    if (any(grepl("GAMSEnd", names(runstatistics$stats)))) {
      out[i, "Runtime"] <- as.numeric(round(difftime(runstatistics$stats[["timeGAMSEnd"]], runstatistics$stats[["timeGAMSStart"]], units = "secs"), 0))
    } else if (any(grepl("timePrepareStart", names(runstatistics$stats))) && ! out[i, "jobInSLURM"] %in% "no") {
      out[i, "Runtime"] <- as.numeric(round(difftime(Sys.time(), runstatistics$stats[["timePrepareStart"]], units = "secs"), 0))
    }

    # additional info on plausibility checks in REMIND runs
    if (length(cfgf) != 0 && file.exists(file.path(ii, cfgf)) &&
        !isTRUE(runstatistics$stats[["config"]][["model_name"]] == "MAgPIE")) {
      miffile <- paste0(ii, "/REMIND_generic_", cfg[["title"]], ".mif")
      sumErrFile <- paste0(ii, "/REMIND_generic_", cfg[["title"]], "_summation_errors.csv")
      if (!file.exists(miffile)) {
        next
      }

      # summation checks
      if (file.exists(sumErrFile)) {
        tmp <- read.csv2(sumErrFile, sep = ",")
        out[i, "summationErrors"] <- length(unique(tmp$variable))
      } else {
        out[i, "summationErrors"] <- 0
      }

      # range checks
      rangeErrFile <- paste0(ii, "/REMIND_generic_", cfg[["title"]], "_range_errors.txt")
      if (file.exists(rangeErrFile)) {
        tmp <- read.csv2(rangeErrFile)
        out[i, "rangeErrors"] <- nrow(tmp)
      } else {
        out[i, "rangeErrors"] <- 0
      }

      # fix on ref checks
      fixErrFile <- file.path(ii, "log_fixOnRef.csv")
      if (file.exists(fixErrFile)) {
        tmp <- read.csv2(fixErrFile, sep = ",")
        out[i, "fixErrors"] <- length(unique(tmp$variable))
      } else {
        out[i, "fixErrors"] <- 0
      }
      # project summations
      projectSumFile <- paste0(ii, "/projectSummations.rds")
      if (file.exists(projectSumFile)) {
        tmp <- readRDS(projectSumFile)
        out[i, "missingProjVars"] <- tmp[["ScenarioMIP"]][["missingVars"]]
        out[i, "projSummationErrors"] <- tmp[["ScenarioMIP"]][["checkSummations"]]
        out[i, "projSummationErrorsRegional"] <- tmp[["ScenarioMIP"]][["checkSummationsRegional"]]
      } else {
        out[i, "missingProjVars"] <- NA
        out[i, "projSummationErrors"] <- NA
        out[i, "projSummationErrorsRegional"] <- NA
      }
    }

  } # END DIR LOOP
  return(out)

}
