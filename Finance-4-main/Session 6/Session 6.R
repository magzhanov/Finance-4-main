######################
#     FINANCE 4      #
#   TA SESSION #5    #
#  Timur Magzhanov   #
######################

##### PACKAGES #####
# install.packages("AER")        # if not installed
# install.packages("ggplot2")
# install.packages("broom")

##### LIBRARIES #####
library(AER)
library(ggplot2)
library(broom)
library(dplyr)

############################################################
#                        IV IN R                           #
#               (1) F>10 is not enough                     #
#               (2) LATE vs. ATE Distortion                #
############################################################


##### HELPER FUNCTIONS AND SETTINGS #####

# 1) partial_r2_and_f(): Return partial R^2 and F-statistic for a
#    first-stage regression in a simple 1-endogenous, 1-instrument setup.
partial_r2_and_f <- function(first_stage_model) {
  fs_sum <- summary(first_stage_model)
  f_stat <- fs_sum$fstatistic[1]
  r_sq <- fs_sum$r.squared
  return(list(partial_r2=r_sq, f_stat=f_stat))
}

# 2) Diagnostic function: prints coefficient comparisons, partial R^2,
#    first-stage F, plus a "reality check" on coefficient plausibility.
iv_diagnosis <- function(ols_model, iv_model, first_stage, true_value = NULL, label="SCENARIO") {
  cat("\n====================================================\n")
  cat("IV DIAGNOSIS:", label, "\n")
  cat("====================================================\n")
  
  #  OLS vs. IV Coefficients
  ols_coef <- coef(ols_model)[2]
  iv_coef  <- coef(iv_model)[2]
  ratio_iv_ols <- iv_coef / ols_coef
  
  cat("OLS vs. IV Coefficients:\n")
  cat("  OLS Estimate:", round(ols_coef, 3), "\n")
  cat("  IV  Estimate:", round(iv_coef, 3), "\n")
  cat("  IV/OLS Ratio:", round(ratio_iv_ols, 3), "\n\n")
  
  # First-stage stats
  fs_stats <- partial_r2_and_f(first_stage)
  cat("First-stage Partial R^2:", round(fs_stats$partial_r2, 4), "\n")
  cat("First-stage F-statistic  :", round(fs_stats$f_stat, 3), "\n\n")
  
  # Some warnings/interpretation
  if(abs(ratio_iv_ols) > 2) {
    cat("WARNING: IV is more than 2x OLS -> Potential inflation or local effect.\n")
  }
  if(fs_stats$f_stat < 10) {
    cat("WARNING: Weak instrument (F < 10). IV estimates may be unreliable.\n")
  }
  
  # Reality check if we have a "true_value"
  if(!is.null(true_value)) {
    # If the IV is more than double the true value => suspicious
    if(abs(iv_coef) > 2 * abs(true_value)) {
      cat("REALITY CHECK WARNING: IV >> 'True' effect.\n",
          "Possible LATE or serious model issues.\n")
    }
  }
}


##### F>10 IS NOT ENOUGH #####

# 1. Function to simulate data, run OLS & IV, return metrics

simulate_and_estimate <- function(
    n = 2000,
    true_beta = 2.0,   # True effect of X on Y
    corr_strength = 0.02  # correlation factor between Z and X
) {
  # "quality" or unobserved factor that influences X, Y
  quality <- rnorm(n, 0, 1)
  
  # Instrument Z (mean=0, sd=1)
  Z <- rnorm(n, 0, 1)
  
  # X depends partly on Z, partly on quality
  # 'corr_strength' is the coefficient in front of Z
  # If corr_strength is large, Z strongly affects X.
  # If corr_strength is small, Z is "weak".
  X <- corr_strength * Z + 0.5 * quality + rnorm(n, 0, 1)
  
  # Y depends on X and also on quality (creating upward OLS bias)
  Y <- true_beta * X + 0.5 * quality + rnorm(n, 0, 1)
  
  # OLS
  ols_fit <- lm(Y ~ X)
  ols_coef <- coef(ols_fit)[2]
  
  # IV regression
  iv_fit <- ivreg(Y ~ X | Z)
  iv_coef <- coef(iv_fit)[2]
  
  # First-stage
  fs_fit <- lm(X ~ Z)
  # partial R^2 (in simple 1IV-1X scenario, it's ~ R^2 of that regression)
  partial_r2 <- summary(fs_fit)$r.squared
  f_val <- summary(fs_fit)$fstatistic[1]
  
  # Return everything
  return(list(
    corr_strength = corr_strength,
    ols_coef = ols_coef,
    iv_coef = iv_coef,
    ratio_iv_ols = iv_coef / ols_coef,
    partial_r2 = partial_r2,
    f_stat = f_val
  ))
}


# 2. Loop over different instrument "strengths"
#    We'll test a range from near-0 up to 0.3, so we can see
#    how the ratio changes for truly "weak" to moderately "strong" instrument

set.seed(123)
grid_strength <- seq(0.005, 0.3, by=0.01) #set by=0.001 -> 300 steps (300 estimation results)
results_list <- lapply(grid_strength, function(g) {
  replicate_data <- simulate_and_estimate(n=2000, true_beta=2, corr_strength=g)
  return(replicate_data)
})

# Convert list to a data frame
res_df <- do.call(rbind, lapply(results_list, as.data.frame))


# 3. Visualize the relationship:
#    (a) Ratio(IV/OLS) vs. partial R^2
#    (b) Ratio(IV/OLS) vs. F-stat
#    (c) We highlight lines for F=10

# (a) Ratio vs Partial R^2
p1 <- ggplot(res_df, aes(x=partial_r2, y=ratio_iv_ols)) +
  geom_point(color="blue") +
  geom_smooth(method="loess", color="red", se=FALSE) +
  labs(title="IV Inflation vs. Instrument Strength",
       subtitle="Ratio(IV/OLS) by Partial R^2 (n=2000, True Beta=2)",
       x="Partial R^2 of Instrument in First Stage",
       y="IV/OLS Ratio") +
  theme_minimal()

# (b) Ratio vs. F-stat
p2 <- ggplot(res_df, aes(x=f_stat, y=ratio_iv_ols)) +
  geom_point(color="blue") +
  labs(title="IV Inflation vs. F-Statistic",
       subtitle="Even if F>10, ratio can be larger than 1 (inflated IV)",
       x="First-Stage F",
       y="IV/OLS Ratio") +
  scale_x_continuous(limits = c(0, 35)) +  # Set x-axis from 0 to 30
  scale_y_continuous(limits = c(0, 1.5)) +  # Start y-axis from 0
  geom_hline(yintercept = 1, linetype="dashed", color="black") +  # Horizontal line at y=1
  geom_vline(xintercept = 10, linetype="dashed", color="black") + # Vertical line at x=10
  theme_minimal()


# We'll also look at how partial R^2 correlates with F
p3 <- ggplot(res_df, aes(x=partial_r2, y=f_stat)) +
  geom_point(color="darkgreen") +
  geom_smooth(method="loess", se=FALSE, color="red") +
  labs(title="F-stat vs. Partial R^2",
       subtitle="We see a monotonic but not 1-to-1 relationship",
       x="Partial R^2",
       y="First-Stage F") +
  theme_minimal()

# 4. Let's see how often F>10 but ratio>1

res_df <- res_df %>%
  mutate(flag_F_10 = (f_stat > 10),
         flag_ratio_1 = (abs(ratio_iv_ols) > 1))

# Proportion of cases with F>10 but ratio>1
cases_F_10 <- sum(res_df$flag_F_10)
cases_F_10_and_ratio_1 <- sum(res_df$flag_F_10 & res_df$flag_ratio_1)

cat("Among", nrow(res_df), "simulations:\n")
cat(" -", cases_F_10, "have F>10.\n")
cat(" -", cases_F_10_and_ratio_1,
    "have F>10 AND IV/OLS ratio>1.\n")
cat(" => Even with F>10, we can still see inflated IV.\n")


# Print results & plots
print(p1)
print(p2)
print(p3)


##### LATE vs. ATE Distortion (Simple) #####

# Imagine a situation: you have Harvard online course attendance (treatment)
# You have a selection for Harvard online course (assignment)
# Who applied for Harvard online course, were selected and attended = good boys/girls
# Good boys/girls have high treatment effect 
# However there are other boys/girls who somehow got to the course 
# These are low treatment effect students
# We want to estimate the effect of attending Harvard online course
# The question is: for whom? In general? Or only for good students?

# We'll create a population with TWO SUBGROUPS:
#  - Group 1 (70% of data) has 'true' effect of 1.0 (on average).
#  - Group 2 (30% of data) has 'true' effect of 4.0 => "high returns"
# ONLY Group 2 takes treatment as prescribed by Z_C.
# => OLS picks up a weighted average near ~1.9
# => IV focuses on the subpopulation that "complies" (mostly Group 2)
#    => might see a slope near 4.0, i.e. bigger than OLS.

set.seed(303)
nC <- 10000

# Group indicator
groupC <- rbinom(nC, size=1, prob=0.3)  # 30% in high-effect group

# True effect differs by group
beta_low <- 1.0
beta_high <- 4.0

# Let's define the "instrument" Z_C (treatment assignment):
#   Z_C strongly affects treatment only for Group 2, noisy for Group 1
#   Group 2 are pure compliers - they do as prescribed by Z
#   Group 1 are random takers - they have got treatment disregarding Z

Z_C <- rbinom(nC, 1, 0.5)

# Generate D:
#   For Group 2, D depends on Z_C. For Group 1, no effect from Z_C.
#   Everyone also has some baseline + noise.
D <- ifelse(groupC == 1, 1 * Z_C, sample(0:1, size=length(groupC), replace=TRUE))

# The true Y:
Y_C <- beta_low * D + # baseline effect
  ifelse(groupC==1, (beta_high - beta_low)*D, 0) + 
  rnorm(nC, 0, 1)

# => Actually, the effect for Group 2 is beta_high, for Group 1 is beta_low
#    The LATE is near 4.0 among group2 "compliers" but the overall ATE is < 4.

# OLS
ols_C <- lm(Y_C ~ D)
# IV
iv_C <- ivreg(Y_C ~ D | Z_C)
# First stage
fs_C <- lm(D ~ Z_C)

cat("\n\n LATE Distortion -> IV > OLS? ---\n")
summary(ols_C)
summary(iv_C)
iv_diagnosis(ols_C, iv_C, fs_C, true_value= 1.9, label="LATE vs. ATE Distortion")

# Visualization: 
# We'll color points by Group. Note how only Group=1 has big slope, but the
# instrument primarily nudges Group=1 to adopt more X.
dfC <- data.frame(
  D=D,
  Y_C=Y_C,
  groupC=factor(groupC, labels=c("LowEffectGroup","HighEffectGroup")),
  Z_C=Z_C
)

pC <- ggplot(dfC, aes(x=D, y=Y_C, color=groupC)) +
  geom_point(alpha=0.5) +
  geom_smooth(method="lm", se=FALSE) +
  labs(title="Scenario C: LATE vs. ATE Distortion",
       subtitle="Blue=LowEffectGroup, Red=HighEffectGroup",
       x="X", y="Y") +
  theme_minimal()
print(pC)

# => The slope among the blue group is large (~4), while the red group is ~1.
# => OLS sees mixture, IV identifies the "complier" group (mostly blue),
#    so we might see a bigger slope from IV.


##### LATE vs. ATE Distortion (Detailed) #####

set.seed(404)
nL <- 2000  # Sample size

# -------------------- 1. ASSIGN GROUPS -------------------- #
# We create four groups:
# - Never-Takers: 30%
# - Compliers: 40% (Only take treatment when instrument suggests so)
# - Always-Takers: 20% (Always take treatment)
# - Defiers: 10% (Act opposite to the instrument, rare)

groupL <- sample(c("Never-Taker", "Complier", "Always-Taker", "Defier"), 
                 size = nL, replace = TRUE, prob = c(0.3, 0.4, 0.2, 0.1))

# -------------------- 2. GENERATE INSTRUMENT -------------------- #
# A valid IV must:
# - Affect treatment probability
# - Be unrelated to the outcome, except through treatment

Z_L <- rnorm(nL, 0, 1)  # Instrument (e.g., policy change, external shock)

# -------------------- 3. TREATMENT ASSIGNMENT -------------------- #
# How does treatment (X) depend on the instrument (Z) for different groups?

X_L <- rep(0, nL)  # Default: No treatment

# Compliers take X if Z > 0
X_L[groupL == "Complier"] <- ifelse(Z_L[groupL == "Complier"] > 0, 1, 0)

# Always-Takers always take treatment
X_L[groupL == "Always-Taker"] <- 1  

# Defiers do the opposite of Z
X_L[groupL == "Defier"] <- ifelse(Z_L[groupL == "Defier"] > 0, 0, 1)

# -------------------- 4. OUTCOME GENERATION -------------------- #
# Different groups may have different treatment effects

# True effect of treatment:
true_effect_complier <- 3.0
true_effect_always_taker <- 2.0
true_effect_never_taker <- 1.0
true_effect_defier <- -1.0  # Defiers may have a negative effect

# Potential outcomes (Y without treatment)
Y_0 <- rnorm(nL, 5, 1)  # Baseline outcome if untreated

# Apply treatment effects:
Y_L <- Y_0 +
  (X_L * true_effect_complier * (groupL == "Complier")) +
  (X_L * true_effect_always_taker * (groupL == "Always-Taker")) +
  (X_L * true_effect_never_taker * (groupL == "Never-Taker")) +
  (X_L * true_effect_defier * (groupL == "Defier")) +
  rnorm(nL, 0, 1)  # Additional noise

# -------------------- 5. RUN ESTIMATIONS -------------------- #
# OLS (biased because it mixes all groups)
ols_L <- lm(Y_L ~ X_L)

# IV Regression: Should isolate effect for compliers (LATE)
iv_L <- ivreg(Y_L ~ X_L | Z_L)

# First-Stage Regression
fs_L <- lm(X_L ~ Z_L)

# -------------------- 6. OUTPUT RESULTS -------------------- #
cat("\n\n--- LATE DISTORTION: IV IDENTIFIES ONLY COMPLIERS ---\n")
summary(ols_L)
summary(iv_L)

# -------------------- 7. VISUALIZATION -------------------- #
dfL <- data.frame(
  X_L = X_L,
  Y_L = Y_L,
  groupL = factor(groupL),
  Z_L = Z_L
)

# (B) Show the relationship between Treatment and Outcome, colored by group
pL2 <- ggplot(dfL, aes(x=X_L, y=Y_L, color=groupL)) +
  geom_point(alpha=0.5) +
  geom_smooth(method="lm", se=FALSE) +
  labs(title="Outcome vs. Treatment by Group",
       subtitle="IV captures only the Compliers' treatment effect",
       x="Treatment (X)",
       y="Outcome (Y)") +
  theme_minimal()
print(pL2)

# KEY TAKEAWAYS 
# 1) OLS mixes all groups, the effect ~1.9
# 2) IV isolates LATE, the effect for Compliers (should be ~3.0)
