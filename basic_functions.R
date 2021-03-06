# 07/03/2020

# basic code for 1st attempt of my inference framework
# exponential function <--> simple pure-birth process

library(tidyverse)

# 1. function to simulate a simple branching process

sim_branching <- function(lambda, tmax=10, y0=1){
  times = 0
  values = y0
  
  y = y0; t = 0
  
  while(t < tmax){
    rate = y * lambda
    delta.t = rexp(1, rate=rate)
    t = t + delta.t
    y = y + 1
    times = c(times, t)
    values = c(values, y)
  }
  
  return(list(times = times, values = values, tmax=tmax))
}

# try it out
ll = sim_branching(0.1, tmax = 100)
plot(ll$times, ll$values)

ll2 = sim_branching(1, tmax = 10)
plot(ll2$times, ll2$values)

# 2. a function to obtain discrete step-wise observations

get_discrete_obs <- function(branching_list, tau){
  
  times = branching_list$times
  values = branching_list$values
  tmax = branching_list$tmax

  obs = values[1]
  ts = seq(from=0, to=tmax, by=tau)
  
  for(t in ts){
    if(t!=0){
      ## find the event time t_i such that t_i <= t < t_{i+1}
      ind = max(which(times <= t))
      y_t = values[ind]
      obs = c(obs, y_t)
    }
  }
  
  return(list(times=ts, y=obs))
}

## try it out
observed = get_discrete_obs(ll, 5)
plot(observed$times, observed$y)


# 3. a function for iterative GLS procedure for Exponential function X
iGLS_exp <- function(observed, init.param, tol=1e-4){
  dat = data.frame(times = observed$times, y = observed$y)
  N = nrow(dat)
  
  gammaA = NULL
  lambdaA = NULL
  
  xformula = "exp(lambda * times)"
  
  # 0) initial estimate of lambda
  xvalues = exp(init.param * observed$times)
  ww = 1/xvalues
  #xformula = paste("exp(", as.character(init.param), " * times)", sep="") 
  init.fit = nls(as.formula(paste("y",xformula,sep=" ~ ")), data = dat,
                 start = list(lambda = init.param), weights = ww)
  lambda = coef(init.fit) %>% as.numeric()
  lambda.old = init.param
  
  iter = 0
  while(abs(lambda - lambda.old) > tol){
    iter = iter + 1
    # 1) estimate gamma
    xvalues = exp(lambda * observed$times)
    gamma = sum((observed$y - xvalues)^2/xvalues)/(N-1)
    gammaA = c(gammaA, gamma)
    # 2) estimate lambda
    lambda.old = lambda
    ww = 1/(gamma * xvalues)
    this.fit = nls(as.formula(paste("y",xformula,sep=" ~ ")), data = dat,
                   start = list(lambda = lambda.old), weights = ww)
    lambda = coef(this.fit) %>% as.numeric()
    lambdaA = c(lambdaA, lambda)
    # 3) print info
    cat("Iteration", iter, ", lambda =", lambda, "gamma =", gamma, "\n")
  }
  
  return(list(data = dat,
              lambda=lambda, gamma=gamma, 
              lambdaList=lambdaA, gammaList = gammaA))
}

## try it out
Est = iGLS_exp(observed, 0.05)
# estimated lambda = 0.08508203

## using pure NLS?
dat = data.frame(times = observed$times, y = observed$y)
NLS.fit = nls(y~exp(lambda * times), dat, 
              start = list(lambda = 0.2))
coef(NLS.fit)
# lambda 
# 0.08578579

# 4. a function for the entire pipeline
test_iGLS_exp <- function(lambda, tau, init.param, tmax=10, y0=1, tol=1e-4){
  # 1) simulate
  events = sim_branching(lambda, tmax, y0)
  cat("simulation done!\n")
  # 2) discretize
  obs = get_discrete_obs(events, tau)
  cat("Discrete data acquired with stepsize =",tau,"\n")
  plot(obs$times, obs$y)
  # 2.5) if simulated result is a flat line, then repeat
  while(all(obs$y == 1)){
    # 1) simulate
    events = sim_branching(lambda, tmax, y0)
    cat("simulation done!\n")
    # 2) discretize
    obs = get_discrete_obs(events, tau)
    cat("Discrete data acquired with stepsize =",tau,"\n")
    plot(obs$times, obs$y)
  }
  # 3) estimate
  res = iGLS_exp(obs, init.param, tol)
  # 4) compare with NLS
  NLS.fit = nls(y~exp(lambda * times), res$data, 
                start = list(lambda = init.param))
  NLS.est = coef(NLS.fit) %>% as.numeric()
  cat("NLS estimate for lambda: ", NLS.est,"\n")
  
  # 5) and true lambda value and NLS estimate
  res$lambdaTrue = lambda
  res$lambdaNLS = NLS.est
  
  return(res)
}

## try it out

test1 = test_iGLS_exp(lambda=0.5, tau=0.5, init.param= 0.2)
### works fine; similar to NLS

test2 = test_iGLS_exp(lambda=0.3, tau=0.2, init.param= 0.2)
### large randomness with Y process
### so should run this repeatedly!!
### (TBD)

test3 = test_iGLS_exp(lambda=1, tau=0.2, init.param= 0.5)


# 5. Conduct a series of experiments with
# lambda = 0.3, 0.5, 1
# tau = 0.2, 0.5, 1
# each repeat 20 times?

Lambdas = c(0.3, 0.5, 1)
Taus = c(0.2, 0.5, 1)

repeat_test <- function(LambdaList, TauList, R=20, ...){
  resTable = NULL
  for(lambda in LambdaList){
    for(tau in TauList){
      cat("Experiment with lambda =", lambda, "and tau =", tau,"...\n")
      for(r in 1:R){
        this.test = test_iGLS_exp(lambda=lambda, tau=tau, ...)
        est.error = this.test$lambda - this.test$lambdaTrue
        NLS.error = this.test$lambdaNLS - this.test$lambdaTrue
        resTable = rbind(resTable, c(lambda, tau, est.error))
        resTable = rbind(resTable, c(lambda, tau, NLS.error))
        cat(r,"\t")
      }
      cat("Experiment done and results recorded!\n")
    }
  }
  resTable = as.data.frame(resTable)
  names(resTable) = c("lambda","tau", "error")
  n = length(LambdaList) * length(TauList) * R
  resTable$method = rep(c("Approx","NLS"), n)
  
  return(resTable)
}

Res = repeat_test(Lambdas, Taus, init.param = 0.5)

## save this for later use
saveRDS(Res, "Exponential_simulation_res.rds")

## make boxplots to compare errors
ggplot(data=Res, aes(x=method,y=error)) +
  geom_hline(yintercept = 0, size=1, color="gray") +
  geom_boxplot() +
  #geom_violin() +
  theme_bw()+
  facet_grid(lambda~tau)
