######################
#     FINANCE 4      #
#   TA SESSION #3    #
#  Timur Magzhanov   #
######################

##### PACKAGES #####
# Install only if not already installed
install.packages(c("fixest", "bacondecomp", "dplyr", "ggplot2", "tidyr"))
install.packages("remotes")
install.packages("did2s")

##### LIBRARIES #####
library(fixest)       # For TWFE regression
library(bacondecomp)  # For Goodman-Bacon decomposition
library(dplyr)        # Data wrangling
library(ggplot2)      # Visualization
library(tidyr)        # Data reshaping
library(purrr)
library(broom)        # For tidy output of models
library(stringr)
library(knitr)
library(kableExtra)
library(did2s)        # All DiDs
library(did)

##### [lucky] Staggered DiD simulation #####

# Set seed for reproducibility
set.seed(42)

# ---- 1. Simulate a Staggered Diff-in-Diff Setup
num_firms <- 100  # Number of firms
num_periods <- 10  # Number of time periods

# Create firm-time panel
df <- expand.grid(firm = 1:num_firms, time = 1:num_periods)

# Assign staggered treatment times randomly
df <- df %>%
  group_by(firm) %>%
  mutate(treatment_time = sample(3:9, 1),  # Treatment occurs between periods 3-9
         treated = as.integer(time >= treatment_time),  # 1 if treated
         treatment_effect = rnorm(1, mean = 2, sd = 0.5)) %>%  # Heterogeneous treatment effects
  ungroup()

# Generate outcome variable (Y)
df <- df %>%
  mutate(epsilon = rnorm(n(), 0, 1),  # Random error
         Y = 5 + 0.5 * time + treated * treatment_effect + epsilon)  # Outcome equation

# ---- 2. Estimate Classic TWFE Diff-in-Diff Regression
twfe_model <- feols(Y ~ treated | firm + time, data = df)
twfe_summary <- summary(twfe_model)

# ---- 3. Goodman-Bacon Decomposition
bacon_results <- bacon(Y ~ treated, data = df, id_var = "firm", time_var = "time")
# Comments:
# "Earlier vs Later Treated" has a weight of 0.46792 and an estimated effect of 2.07732.
# "Later vs Earlier Treated" has a weight of 0.53208 and an estimated effect of 1.95664.
# This means that most of our TWFE estimate comes from later-treated firms serving as controls for earlier-treated firms.
# Since the estimates are close to each other, the bias might not be severe, but we still see some variation.

# ---- 4. Visualizations

## Treatment timing plot
ggplot(df, aes(x = time, y = firm, fill = as.factor(treated))) +
  geom_tile(color = "white") +
  scale_fill_manual(values = c("lightgray", "steelblue"), labels = c("Untreated", "Treated"), name = "Treatment status") +
  labs(title = "Staggered DiD treatment timing",
       x = "Time",
       y = "Firm ID") +
  theme_minimal()

## Goodman-Bacon decomposition plot
ggplot(bacon_results, aes(x = weight, y = estimate)) +
  geom_point(color = "red", alpha = 0.7, size = 3) +
  geom_hline(yintercept = mean(df$treatment_effect), linetype = "dashed", color = "blue") +
  labs(title = "Goodman-Bacon decomposition of TWFE DiD",
       x = "Weight of comparison",
       y = "Estimated treatment effect",
       caption = "Dashed line represents the true average treatment effect") +
  theme_minimal()
# Comments:
# Red dots represent comparisons (earlier vs later treated firms, or vice versa).
# The dashed blue line is the true ATE (from our simulation).
# Different 2x2 comparisons contribute differently to the final TWFE estimate.


##### [unlucky] Staggered DiD simulation #####

# Set seed for reproducibility
set.seed(42)

# ---- 1. Simulate an "unlucky" staggered Diff-in-Diff setup

num_firms <- 100  # Number of firms
num_periods <- 10  # Number of time periods

# Create firm-time panel
df_unlucky <- expand.grid(firm = 1:num_firms, time = 1:num_periods)

# Assign treatment times: most firms treated early, some much later
df_unlucky <- df_unlucky %>%
  group_by(firm) %>%
  mutate(
    treatment_time = sample(c(rep(3, 70), rep(8, 30)), 1),  # 70% treated early, 30% much later
    treated = as.integer(time >= treatment_time),  # Treatment indicator
    firm_effect = rnorm(1, mean = 0, sd = 2)  # Extreme firm-level heterogeneity
  ) %>%
  ungroup()

# Introduce a dynamic treatment effect (increasing over time)
df_unlucky <- df_unlucky %>%
  mutate(
    epsilon = rnorm(n(), 0, 1),  # Random noise
    dynamic_effect = ifelse(
      #treated == 1, (time - treatment_time) * rnorm(1, mean = 1.5, sd = 0.5), 0
      # turn on above if you want noisy theoretical treatment effect
      treated == 1, (time - treatment_time) * 1.5, 0
    ),  # Treatment effect grows over time
    Y = 5 + 0.5 * time + firm_effect + treated * dynamic_effect + epsilon  # Outcome equation
  )

# ---- 2. Estimate TWFE Diff-in-Diff Regression

twfe_unlucky_model <- feols(Y ~ treated | firm + time, data = df_unlucky)
twfe_unlucky_summary <- summary(twfe_unlucky_model)
twfe_unlucky_summary

# ---- 3. Goodman-Bacon Decomposition

bacon_unlucky_results <- bacon(Y ~ treated, data = df_unlucky, id_var = "firm", time_var = "time")

# Comments:
# Large gaps between "Earlier vs Later Treated" and "Later vs Earlier Treated" indicate severe bias.
# TWFE underestimates the true treatment effect due to dynamic effects and firm heterogeneity.

# ---- 4. Visualizations

## 4.1 Treatment Timing Plot (Highly Imbalanced)
ggplot(df_unlucky, aes(x = time, y = firm, fill = as.factor(treated))) +
  geom_tile(color = "white") +
  scale_fill_manual(values = c("lightgray", "steelblue"), labels = c("Untreated", "Treated"), name = "Treatment status") +
  labs(title = "Staggered DiD treatment timing",
       x = "Time",
       y = "Firm ID") +
  theme_minimal()

## 4.2 Goodman-Bacon Decomposition Plot
ggplot(bacon_unlucky_results, aes(x = weight, y = estimate)) +
  geom_point(color = "red", alpha = 0.7, size = 3) +
  geom_hline(yintercept = mean(df_unlucky$dynamic_effect[df_unlucky$treated == 1]), linetype = "dashed", color = "blue") +
  labs(
    title = "Goodman-Bacon decomposition of TWFE DiD",
    x = "Weight of comparison",
    y = "Estimated treatment effect",
    caption = "Dashed line represents the true dynamic treatment effect"
  ) +
  theme_minimal()

# Comments
# This "unlucky" scenario highlights why TWFE fails:
# Later-treated firms serve as "bad controls", worsening bias.
# The dynamic TE distorts TWFE estimates, making them unreliable.
# G-B decomposition shows large differences between "Earlier vs Later Treated" and "Later vs Earlier Treated"

##### [lucky] vs [unlucky] Comparison #####

# ---- 1. Define Theoretical Treatment Effects

event_time_seq <- seq(-5, 5, by = 1)

theoretical_data <- data.frame(
  event_time = rep(event_time_seq, 2),
  case = rep(c("Lucky", "Unlucky"), each = length(event_time_seq)),
  treatment_effect = c(
    # "Lucky" case: Constant treatment effect of 2 after treatment, 0 before
    rep(0, 5), rep(2, 6),
    
    # "Unlucky" case: Smooth dynamic treatment effect
    rep(0, 5), seq(1.5, 9, length.out = 6)  
  )
)

# Compute 90% confidence intervals properly for all cases
theoretical_data <- theoretical_data %>%
  mutate(
    lower_ci = case_when(
      case == "Lucky" & event_time >= 0 ~ 2 - 1.645 * 0.5,  # CI for "Lucky" after treatment
      TRUE ~ treatment_effect  # Ensuring ggplot doesn't break
    ),
    upper_ci = case_when(
      case == "Lucky" & event_time >= 0 ~ 2 + 1.645 * 0.5,  
      TRUE ~ treatment_effect  
    )
  )

# ---- 2. Plot Theoretical Event-Study
ggplot(theoretical_data, aes(x = event_time, y = treatment_effect, color = case, group = case)) +
  geom_line(size = 1.5, linetype = "dashed") +  # Dashed lines for theoretical effects
  geom_point(size = 3) +
  geom_ribbon(aes(ymin = lower_ci, ymax = upper_ci, fill = case), alpha = 0.2, show.legend = FALSE) +  # 90% CI applied correctly
  scale_color_manual(values = c("Lucky" = "steelblue", "Unlucky" = "red")) +
  scale_fill_manual(values = c("Lucky" = "steelblue", "Unlucky" = "red")) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "black") +
  labs(
    title = "Theoretical event-study",
    x = "Time to treatment",
    y = "Theoretical treatment effect",
    color = "Case"
  ) +
  theme(legend.position = "right")

##### Stacked regression (Gormley & Matsa, 2011) #####

# The stacked regression (G&M 2011, Baker et al. 2022) breaks data into
# event-specific cohorts and estimates a separate DiD in each cohort. 
# Then “stacks” those cohorts together into one dataset 
# and runs a single regression (with cohort fixed effects).

# Compared to “usual” TWFE on the entire panel, stacked DiD avoids 
# having previously treated units serve as controls for later-treated units
# which can bias a standard TWFE estimate when treatment is staggered 
# especially if dynamic or heterogeneous treatment effects are present.

# ---- 1. Create cohorts for each unique treatment time and stack them
unique_tt <- sort(unique(df_unlucky$treatment_time))

stacked_data <- do.call(rbind, lapply(unique_tt, function(tt) {
  # Identify newly treated firms at time = tt
  treated_firms <- df_unlucky %>%
    filter(treatment_time == tt) %>%
    pull(firm) %>%
    unique()
  
  # Define an event window (e.g., 3 periods before and 3 periods after the event)
  min_t <- max(1, tt - 3)
  max_t <- min(num_periods, tt + 3)
  
  # Keep observations within this event window, either newly treated at tt or not-yet-treated
  sub_data <- df_unlucky %>%
    filter(time >= min_t & time <= max_t) %>%
    filter((firm %in% treated_firms) | (treatment_time > tt))
  
  # Define treatment (TREAT) and post (POST) indicators, plus their interaction
  sub_data <- sub_data %>%
    mutate(
      TREAT = ifelse(firm %in% treated_firms, 1, 0),
      POST = ifelse(time >= tt, 1, 0),
      TREAT_POST = TREAT * POST,
      cohort = tt
    )
  
  return(sub_data)
}))

# There are 2 cohorts in the stacked_data (3 and 8):
# 70% of firms were treated at time = 3 and 30% - at time = 8.


# ---- 2. Estimate the stacked DiD model
# Here we include fixed effects for firm, time, and cohort.
# Clustering by 'firm' is shown; you can add more clustering if desired.
stacked_model <- feols(Y ~ TREAT_POST + TREAT + POST | firm + time + cohort, 
                       data = stacked_data, 
                       cluster = c("firm"))
summary(stacked_model)
stacked_model_summary <- summary(stacked_model)
# TREAT_i is time-invariant for each firm hence is dropped out with firm FE


# ---- 3. Compute average "true" treatment effect from the simulation
# "dynamic_effect" is the actual effect assigned in df_unlucky post-treatment.
# We'll take its average among truly treated observations in their post period.
df_unlucky_post <- df_unlucky %>%
  filter(treated == 1 & time >= treatment_time)

avg_true_effect <- mean(df_unlucky_post$dynamic_effect, na.rm = TRUE)

# Extract stacked DiD estimate for TREAT_POST
tidy_stacked <- broom::tidy(stacked_model)
stacked_estimate <- tidy_stacked$estimate[tidy_stacked$term == "TREAT_POST"]

# Present results in a neat table
comparison_table <- data.frame(
  Metric = c("Stacked DiD Estimate (TREAT_POST)", "Average True Treatment Effect"),
  Value  = c(round(stacked_estimate, 4), round(avg_true_effect, 4))
)
comparison_table %>%
  kable("simple") %>%
  kable_styling(full_width = FALSE)

# The stacked DiD with a 3-period window is capturing essentially 
# a local average effect - only up to 3 periods after each firm’s treatment. 
# If the full effect continues to grow beyond that, the stacked DiD estimate 
# will understate the overall “true effect”.

##### Sun & Abraham (2021) - did2s - [unlucky] #####

set.seed(42)
num_firms   <- 100
num_periods <- 10

# Create firm-time panel
df_unlucky <- expand.grid(
  firm = 1:num_firms,
  time = 1:num_periods
)

# Assign treatment times: 70% at t=3, 30% at t=8
df_unlucky <- df_unlucky %>%
  group_by(firm) %>%
  mutate(
    treatment_time = sample(c(rep(3, 70), rep(8, 30)), 1),
    treated        = as.integer(time >= treatment_time),
    firm_effect    = rnorm(1, mean = 0, sd = 2)
  ) %>%
  ungroup()

# Introduce a dynamic effect that grows post-treatment
df_unlucky <- df_unlucky %>%
  mutate(
    epsilon = rnorm(n(), 0, 1),
    dynamic_effect = ifelse(
      treated == 1, (time - treatment_time) * 1.5, 0
    ),
    Y = 5 + 0.5*time + firm_effect + treated*dynamic_effect + epsilon
  )

# Rename "time" to "period" to avoid conflicts with base R "time()" function
df_unlucky <- df_unlucky %>%
  rename(period = time)

# Confirm 'period' is numeric (or integer). If it isn't, convert:
df_unlucky$period <- as.integer(df_unlucky$period)

# If a firm is treated, G = treatment_time:
df_unlucky <- df_unlucky %>%
  mutate(G = ifelse(treated == 1, treatment_time, 0))

# Sun & Abraham (2021) style DiD:
#  - first_stage   : specify fixed effects with the " | " syntax 
#  - second_stage  : use sunab(G, time) to get event-study style estimates
#  - treatment     : name of the 0/1 indicator in your data
#  - cluster_var   : choose your clustering variable

df_unlucky <- df_unlucky %>%
  mutate(
    period = as.integer(period),
    firm   = as.integer(firm),
    G      = ifelse(treated == 1, treatment_time, 0),
    rel_year = period - treatment_time   # relative event time
  )

# Make sure rel_year is integer (it should be by construction)
df_unlucky$rel_year <- as.integer(df_unlucky$rel_year)

sa_model <- did2s(
  data        = df_unlucky,
  yname       = "Y",
  first_stage = ~ 1 | firm + period,       # firm & period FEs
  second_stage = ~ i(rel_year),     # Sun & Abraham transformation
  treatment   = "treated",
  cluster_var = "firm"
)

summary(sa_model)

# plot rel_year coefficients and standard errors 
fixest::coefplot(sa_model, keep = "rel_year::(.*)")

##### Sun & Abraham (2021) - did2s - [package data] #####

# Load the built-in "df_het" dataset from did2s
#    This dataset has:
#       - dep_var: outcome variable
#       - unit   : unit ID
#       - year   : time variable
#       - g      : first treatment period for each unit

data("df_het")  # Provided by did2s package

# Quick peek at structure
str(df_het)

# event_study() can simultaneously produce estimates using:
#   - TWFE
#   - did2s (Gardner, 2021)
#   - did   (Callaway & Sant’Anna, 2020)
#   - impute (Borusyak, Jaravel, Spiess, 2021)
#   - sunab  (Sun & Abraham, 2020)
#   - staggered (Roth & Sant’Anna, 2021)
# Setting estimator="all" runs all


out <- event_study(
  data      = df_het,
  yname     = "dep_var",
  idname    = "unit",
  gname     = "g",
  tname     = "year",
  estimator = "all"    # all methods
)

# Plot all event-study estimates on ONE chart
# By default, plot_event_study(out) puts them on separate facets
# To overlay them on the same plot, set `separate = FALSE`.

event_plot <- plot_event_study(out, separate = FALSE)
ggsave("event_study_comparison.png", event_plot, width = 10, height = 7, dpi = 300, bg = "white")

##### Callaway & Sant’Anna (2021) - did - [unlucky] #####

#  att_gt() is the main function, returning ATT(g,t) for each group g in period t
#  We'll use the default "dr" (doubly robust) method. 
#  Note: Because we don't have never-treated units, the "not-yet-treated" units at each t 
#  act as the comparison group in practice.

did_unlucky <- att_gt(
  yname  = "Y",
  tname  = "period",
  idname = "firm",
  gname  = "treatment_time",
  data   = df_unlucky,
  control_group = "notyettreated", 
  est_method = "dr"
)

# Now aggregate to a "dynamic" event-study style object 
es_unlucky <- aggte(
  did_unlucky,
  type = "dynamic"
)
summary(es_unlucky)

# Plot using ggdid() from the "did" package
ggdid(es_unlucky)

##### Callaway & Sant’Anna (2021) - did - [package data] #####

data("df_het", package = "did2s")
# Quick reminder:
#   df_het has columns: dep_var, unit, year, g
#   - 'dep_var' = outcome
#   - 'unit'    = unit ID
#   - 'year'    = time variable
#   - 'g'       = first treatment period (or 0 if never treated, if any)

did_het <- att_gt(
  yname  = "dep_var",
  tname  = "year",
  idname = "unit",
  gname  = "g",
  data   = df_het,
  est_method = "dr"  # "dr" = doubly robust
)

# Aggregate into an event-study object
es_het <- aggte(
  did_het,
  type = "dynamic"
)
summary(es_het)

# Plot event-study estimates
ggdid(es_het)
