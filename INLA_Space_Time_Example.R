
start_time <- Sys.time() # calculate how much time it takes to run the code

#############################################
## Space Time Disease Mapping Example Code ##
#############################################
# This file shows how to use the R-INLA package to estimate space-time  
# smoothed area-level outcome rates over time. 


# To use this code example, you will need to have your outcome data already 
# prepped and organized into a space/time framework. Each row should represent
# a unique area/time period combination. You will need a column representing the 
# outcome count and another column representing the population at risk count 
# (i.e. your denominator).

# NOTE: unlike the spatial smoothing code, this dataset will be in long format
# meaning that each area will have multiple rows of data (one for each time period).
# Long data is not always easy to use when you are using spatial shapefiles (since 
# each row is a geography). For ease of illustration, we have not included code 
# below to convert data from wide to long format or vice versa, but know you may 
# need to manipulate your data this way to run the code. Use the neighbors graph
# file creation code from the spatial smoothing code here and make sure the 
# "new_id" column is the same. 


#Load in libraries
library("tidyverse")
library("dplyr")
library("sf") 
library("sp")
library("spdep")
library("INLA")

#Create directory path
datadir <- "[PUT YOUR DIRECTORY PATH HERE]"
# Use forward slashes "/"

#Load in data
longdata <- readRDS(paste0(datadir, "[PUT FILE NAME HERE].rds"))


## ---------------------------------------------------------------- ##

#Now it's time to smooth the rates!
#Specify the formula(s)

#First the formula specification for the random walk 1 “rw1” temporal model
#then the formula specification for the bym2 spatial model
formula <- outcome ~ 1 + f(time, #time should be the column name for your unit of time 
                           model="rw1", 
                           hyper = list(theta = list(prior="pc.prec", param=c(1,0.01)))) +
  f(new_id, 
    model="bym2", 
    graph="[PUT PATH AND FILENAME OF GRAPH FILE HERE]", 
    scale.model=T, constr=T, 
    hyper=list(phi=list(prior="pc", param=c(0.5, 0.5), initial=-3), 
               prec=list(prior="pc.prec", param=c(1,0.01), initial=4)))

#Fit the model
fitmod <- inla(formula,
               data=longdata, 
               family="poisson", 
               offset=log(population), # "population" should be the column of denominator counts
               control.predictor = list(compute = TRUE), verbose = TRUE)
summary(fitmod) # look at the summary!


#Extract the posterior median from the model output
posterior_median <- fitmod$summary.fixed[4]

#extract ids for merging 
new_ids <- fitmod$summary.random$new_id$ID[1:"[Number of areas]"]

#Get the medians of the random effects for space
spaceREs <- exp(fitmod$summary.random$new_id[1:"[Number of areas]",5])
spaceREs <- cbind(new_id, spaceREs)

#Get the medians of the random effects for year
timeREs <- exp(fitfslong$summary.random$year[1:"[number of time periods]",5])

#create a dataframe with REs for every space/time combo
REs <- data.frame(timeREs=timeREs,
                  year=data$year,
                  ID.area=data$new_id)
REs <- merge(REs, spaceREs, by.x = "ID.area", by.y = "new_id", all.x = TRUE)

#Calculate the space/time smoothed rates by multiplying the posterior median by the random effects for each area and time
smoothed_rates <- as.double(exp(posterior_median)) * REs[, 2] * REs[, 4]

#Now merge it back to your shapefile to visualize!
results <- cbind(REs, smoothed_rates)


## ---------------------------------------------------------------- ##

#Calculate the width of of the 95% credible interval for each county estimate
#NOTE The linear predictor is in units of the outcome: counts
lower <- exp(fitmod$summary.linear.predictor["0.025quant"])
upper <- exp(fitmod$summary.linear.predictor["0.975quant"])

#combine the upper and lower bounds
posteriors <- cbind(lower, upper)
colnames(posteriors) <- c("lower", "upper")

#Combine data to merge back to shapefile
addtopolygon_ci <- cbind(results, posteriors)

#Merge the smoothed rates and posterior count estimates with the shapefile
spacetime_output <- merge(longdata, addtopolygon_ci, by = c("new_id", "year")) 

#Calculate rate per 10,000 people by dividing the credible interval counts by county population
spacetime_output$lower_rate10 <- (spacetime_output$lower/spacetime_output$population)*10000
spacetime_output$upper_rate10 <- (spacetime_output$upper/spacetime_output$population)*10000

#Calculate the width of the 95% credible intervals of each county rate
spacetime_output$ci_width_rate10 <- spacetime_output$upper_rate10-spacetime_output$lower_rate10

#calculate rate of outcome per 10,000
spacetime_output$smooth_10 <- spacetime_output$smoothed_rates*10000

## ---------------------------------------------------------------- ##

saveRDS(spacetime_output, paste0(datadir, "[Name of output file .rds]"))

#you may need to convert "spacetime_output" from long to wide if you'd 
# like to merge back to a shapefile. 


end_time <- Sys.time()
end_time - start_time #this is the run time for the code