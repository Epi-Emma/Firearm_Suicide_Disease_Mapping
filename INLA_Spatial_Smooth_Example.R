
start_time <- Sys.time() # calculate how much time it takes to run the code

##########################################
## Spatial Disease Mapping Example Code ##
##########################################
# This file shows how to use the R-INLA package to estimate spatially smoothed
# area-level outcome rates using a BYM2 model.

# To use this code example, you will need to have your outcome data already 
# prepped and organized. Each row should represent a unit of your geography 
# (e.g. county). You will need a column representing the outcome count and 
# another column representing the population at risk count (i.e. your denominator).
# You will also need a shapefile (.shp) of whatever geography you would like 
# to use as your areal unit (unit for which rates will be calculated - same 
# geography as your outcome data).

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
dat <- readRDS(paste0(datadir, "[PUT FILE NAME HERE].rds"))
# if your data are not saved as .rds, change this command to read in your
# data in whatever format it is saved as. 

#Load in area shapefile (this is your geography - e.g. counties)
counties <- read_sf(paste0(datadir, "[PUT NAME OF SHAPEFILE HERE .shp]"))

## ---------------------------------------------------------------- ##

#Merge data to shape
data <- left_join(dat, counties, 
                  by = ("[County Column Name/ID in data]" = "[County Column Name/ID in shapefile]"))

#Create new IDs in order of data
data$new_id <- 1:nrow(data)

#Create the graph file to indicate who are and are not neighbors
mcnty_nb <- poly2nb(data, row.names = data$new_id, queen = F)
nb2INLA(paste0(datadir, "county_neighbors.graph"), county_nb) #save it


## ---------------------------------------------------------------- ##

#Now it's time to smooth the rates!
#Specify the formula
formula <- outcome ~ 1 + f(new_id, # "outcome" should be the column name of outcome counts
                           model="bym2", 
                           graph="[PUT PATH AND FILENAME OF GRAPH FILE HERE]", 
                           scale.model=T, constr=T, 
                           hyper=list(phi=list(prior="pc", param=c(0.5, 0.5), initial=-3), 
                                      prec=list(prior="pc.prec", param=c(1,0.01), initial=4)))

#Fit the model
fitmod <- inla(formula,
               data==data, 
               family="poisson", 
               offset=log(population), # "population" should be the column of denominator counts
               control.predictor = list(compute = TRUE), verbose = TRUE)
summary(fitmod) # look at the summary!

#Extract the posterior median from the model output
posterior_median <- fitmod$summary.fixed[4]

#Get the medians of the random effects for each area (which are centered around alpha)
random_effects <- exp(fitmod$summary.random$new_id[5])

#Calculate the smoothed rates by multiplying the posterior median by the random effects for each area
smoothed_rates <- as.double(exp(posterior_median)) * random_effects[, 1]

#Now merge it back to your shapefile to visualize!
#get the IDs from the model fit and bind them to the smoothed rate estimates you just calculated
new_id <- fitmod$summary.random$new_id$ID
addtopolygon <- cbind(new_id, smoothed_rates)


## ---------------------------------------------------------------- ##

#Calculate the width of of the 95% credible interval for each county estimate
#NOTE The linear predictor is in units of the outcome: counts
lower <- exp(fitmod$summary.linear.predictor["0.025quant"])
upper <- exp(fitmod$summary.linear.predictor["0.975quant"])

#combine the upper and lower bounds
posteriors <- cbind(lower, upper)
colnames(posteriors) <- c("lower", "upper")

#Combine data to merge back to shapefile
addtopolygon2 <- cbind(addtopolygon, posteriors)

#Merge the smoothed rates and posterior count estimates with the shapefile
county_output <- merge(data, addtopolygon, by="new_id")

#Calculate rate per 10,000 people by dividing the credible interval counts by county population
county_output$lower_rate10 <- (county_output$lower/county_output$population)*10000
county_output$upper_rate10 <- (county_output$upper/county_output$population)*10000

#Calculate the width of the 95% credible intervals of each county rate
county_output$ci_width_rate10 <- county_output$upper_rate10-county_output$lower_rate10


## ---------------------------------------------------------------- ##
#Save the shapefile for your GIS

#export your new estimates to a shapefile for mapping!
write_sf(county_output, paste0(datadir, "Smoothed_Rates.shp"))


end_time <- Sys.time()
end_time - start_time #this is the run time for the code