simulateW <- function(zinb, ncells = 100, nclust = 3, a = 1, colIni = 1){
  par(mfrow = c(2,2))
  # zinbW
  xlim = c(min(zinb@W[,1]) - 1, max(zinb@W[,1]) + 1) 
  ylim = c(min(zinb@W[,2]) - 1, max(zinb@W[,2]) + 1)
  plot(zinb@W, col = colIni, xlim = xlim, ylim = ylim,
       main = 'zinb fitted W\ncolor = brain area')
  
  # mclustW
  mclustW = Mclust(zinb@W, G = nclust)
  plot(mclustW$data, main = 'multivar gauss fit\nmclust K = 3', xlab = 'W1', ylab = 'W2', 
       xlim = xlim, ylim = ylim, col = mclustW$classification)
  
  # multivar gaussian
  clust = sample(mclustW$classification, ncells, replace = TRUE)
  # a = b = 1
  simW1 = lapply(clust, function(i){
    mvrnorm(n = 1, mu = mclustW$parameters$mean[, i], 
            Sigma = mclustW$parameters$variance$sigma[,, i])
  })
  simW1 = do.call(rbind, simW1)
  plot(simW1, col = clust,
       main = paste0('multivar gauss sim\nncells=', ncells, ', a=1'),
       xlab = 'W1', ylab = 'W2', xlim = xlim, ylim = ylim)
  
  b2 = computeB2(mclustW, a)
  b2 = matrix(c(b2[1], 1, 1, b2[2]), ncol = 2, nrow = 2)
  simW2 = lapply(clust, function(i){
    mvrnorm(n = 1, mu = mclustW$parameters$mean[, i] * a, 
            Sigma = mclustW$parameters$variance$sigma[,, i] * b2)
  })
  simW2 = do.call(rbind, simW2)
  plot(simW2, col = clust,
       main = paste0('multivar gauss sim\nncells=', ncells, ', a=' , a),
       xlab = 'W1', ylab = 'W2', xlim = xlim, ylim = ylim)
  par(mfrow = c(1, 1))
  
  return(list(simW = simW2, bio = clust))
}

computeB2 = function(mclustW, a = 1){
  N = nrow(mclustW$data)
  Vtot = apply(mclustW$data, 2, var)
  
  Vinter = (a * mclustW$parameters$mean - apply(mclustW$data, 2, mean))^2
  nk = as.vector(table(mclustW$classification))
  Vinter = as.vector(Vinter %*% nk)
  
  mk = sapply(mclustW$classification, function(i) mclustW$parameters$mean[,i])
  Vintra = apply((mclustW$data - t(mk))^2, 2, sum)
  
  ( 1 / Vintra ) * ( (N-1) * Vtot - Vinter )
}

simulateGamma <- function(zinb, ncells = 100, gammapiOffset = 0, colIni = 1,
                          colSim = 1){
  # gamma zinb
  gamma = data.frame(gammaMu = zinb@gamma_mu[1, ],
                     gammaPi = zinb@gamma_pi[1, ])
  # mclustW
  mclustGamma = Mclust(gamma, G = 1)
  
  # multivar gaussian
  simGamma = mvrnorm(n = ncells,
                     mu = mclustGamma$parameters$mean[,1] + c(0, gammapiOffset), 
                     Sigma = mclustGamma$parameters$variance$sigma[,, 1])
  
  par(mfrow = c(1,2))
  xlim = c(min(c(gamma[,1], simGamma[,1])) - .5,
           max(c(gamma[,1], simGamma[,1])) + .5) 
  ylim = c(min(c(gamma[,2], simGamma[,2])) - .5,
           max(c(gamma[,2], simGamma[,2])) + .5) 
  plot(gamma[,1], gamma[,2], col = colIni,
       xlim = xlim, ylim = ylim, xlab = 'gamma_mu', ylab = 'gamma_pi', 
       main = 'zinb fitted Gamma\ncolor = brain area')
  plot(simGamma, col = colSim,
       main = paste0('bivar gauss sim\nncells=', ncells, 
                     ', gammaPi offset = ', gammapiOffset),
       xlab = 'gamma_mu', ylab = 'gamma_pi', xlim = xlim, ylim = ylim)
  par(mfrow = c(1, 1))
  
  return(simGamma)
}

zinbSimWrapper <- function(core, colIni, ncells = 100, ngenes = 1000, nclust = 3, 
                           a = 1, gammapiOffset = 0, B = 1, ncores = NULL,
                           seed = NULL, fileName = 'zinbSim.rda'){
  
  if (!is.null(seed)) set.seed(seed)
  
  # sample ngenes 
  if (ngenes > nrow(core)) repl = T else repl = F
  core = core[sample(1:nrow(core), ngenes, repl = repl),]
  
  # fit zinb (if you already fitted zinb, it is cached)
  d = digest(core, "md5")
  tmp = paste0(tempdir(), '/', d)
  fileZinb = sprintf("%s_zinb.rda", tmp)
  if (!file.exists(fileZinb)){
    print('run ZINB')
    if (is.null(ncores)) ncores = max(1, detectCores() - 1)
    zinb <- zinbFit(core, ncores = ncores, K = 2, commondispersion = FALSE,
                    epsilon = ngenes)
    save(zinb, file = fileZinb)
  }else{
    load(fileZinb)
  }
  
  # sim W
  w = simulateW(zinb, ncells, nclust, a, colIni)
  simW = w$simW
  bio = w$bio
  
  # sim gamma
  simGamma = simulateGamma(zinb, ncells, gammapiOffset,
                           colIni = colIni, colSim = bio)
  
  # sim model
  simModel = zinbModel(W=simW, gamma_mu = matrix(simGamma[,1], nrow = 1),
                  gamma_pi = matrix(simGamma[,2], nrow = 1),
                  alpha_mu=zinb@alpha_mu, alpha_pi=zinb@alpha_pi,
                  beta_mu=zinb@beta_mu, beta_pi=zinb@beta_pi, zeta = zinb@zeta)
  
  # sim data
  if (B == 1){
    simData = zinbSim(simModel, seed = 1)
  } else{
    simData = lapply(seq_len(B), function(j){
      zinbSim(simModel, seed = j)
    })
  }
  
  save(bio, simModel, simData, file = fileName)
}

########################################################
library(scRNAseq)
library(zinb)
library(mclust)
library(digest)
library(RColorBrewer)
library(MASS)

##########
## ALLEN
##########
data("allen")
cols = brewer.pal(8, "Set1")
prefilter = allen[grep("^ERCC-", rownames(allen), invert = TRUE),
                   which(colData(allen)$Core.Type=="Core")]
filterGenes = apply(assay(prefilter) > 5, 1, sum) >= 5
postfilter = prefilter[filterGenes, ]
bioIni =  as.factor(colData(postfilter)$driver_1_s)
core = assay(postfilter)
colIni = cols[bioIni]

simAllen = T
if (simAllen){
  for (nc in c(100, 1000, 10000)){
    for (aa in c(1, 0.85)){
      for (offs in c(-3.5, 0, 3.5)){
        ff = sprintf('sims/datasets/simAllen_%s_a%s_offs%s.rda', nc, aa, offs)
        zinbSimWrapper(core = core, colIni = colIni, ncells = nc, nclust = 3, 
                       a = aa, gammapiOffset = offs, B = 10, seed = seed, 
                       fileName = ff)
        load(ff)
        keep = lapply(1:length(simData), function(i){
          counts = t(simData[[i]]$counts)
          keep = (rowSums(counts) != 0)
        })
        keep = Reduce('+', keep) == 10
        for (i in 1:length(simData)){
          simData[[i]]$counts = simData[[i]]$counts[,keep] 
        }
        save(bio, simModel, simData, keep, file = ff)
      }
    }
  }
}


##########
## ZEISEL
##########
#sims/datasets/
data <- read.table("sims/datasets/expression_mRNA_17-Aug-2014.txt", sep='\t',
                   stringsAsFactors = FALSE, comment.char = '%')
counts <- as.matrix(data[12:NROW(data),-(1:2)])
counts <- matrix(as.numeric(counts), ncol=ncol(counts), nrow=nrow(counts))
rownames(counts) <- data[12:NROW(data),1]
colnames(counts) <- data[8, -(1:2)]
level1 <- as.factor(as.matrix(data)[9,-(1:2)])
set.seed(21986)
filter = sample(1:ncol(counts), 2000, replace = F)
counts = counts[, filter]
level1 = droplevels(level1[filter])
filterGenes = apply(counts > 5, 1, sum) >= 5
counts <- counts[filterGenes, ]
col <- brewer.pal(8, "Set2")
colIni <- col[level1]


meanDiff = F
if (meanDiff){
  nc = 1000
  aa = 1
  offs = 3.5
  ff = sprintf('sims/figures/meanDiff/simZeisel_%s_a%s_offs%s.rda', nc, aa, offs)
  
  ## simulate
  zinbSimWrapper(core = counts, colIni = colIni, ncells = nc, nclust = 3, 
                 a = aa, gammapiOffset = offs, B = 1, fileName = ff)
  
  # remove genes with only zeros in at least one of the B simulated ds
  load(ff)
  counts = t(simData$counts)
  keep = rowSums(counts) > 0
  simData$counts = simData$counts[,keep] 
  save(bio, simModel, simData, keep, file = ff)

  # fit
  fittedSim = zinbFit(t(simData$counts), K = 2, commondispersion = FALSE,
                   epsilon = 150, ncores = 2)
  save(fittedSim, file = gsub('.rda', '_fitted.rda', ff))
}

corrSilh_Zeisel = F
if (simZeisel){
  for (nc in c(100, 1000, 10000)){
    for (aa in c(1, 0.85)){
      for (offs in c(-3.5, 0, 3.5)){
        #sims/datasets/bias_mse_ncells/
        ff = sprintf('simZeisel_%s_a%s_offs%s.rda', nc, aa, offs)
        zinbSimWrapper(core = counts, colIni = colIni, ncells = nc, nclust = 3, 
                       a = aa, gammapiOffset = offs, B = 10, seed = seed, 
                       fileName = ff)
        # remove genes with only zeros in at least one of the B simulated ds
        load(ff)
        keep = lapply(1:length(simData), function(i){
          counts = t(simData[[i]]$counts)
          keep = (rowSums(counts) != 0)
        })
        keep = Reduce('+', keep) == 10
        for (i in 1:length(simData)){
          simData[[i]]$counts = simData[[i]]$counts[,keep] 
        }
        save(bio, simModel, simData, keep, file = ff)
      }
    }
  }
}

time_Zeisel = F
if (simZeisel){
  aa = 1
  offs = 3.5
  for (nc in c(50, 100, 500, 1000, 5000, 10000)){
    ff = sprintf('sims/figures/cpuTime/simZeisel_%s_a%s_offs%s.rda', nc, aa, offs)
    zinbSimWrapper(core = counts, colIni = colIni, ncells = nc, nclust = 3, 
                   a = aa, gammapiOffset = offs, B = 10, seed = seed, 
                   fileName = ff)
  }
}
