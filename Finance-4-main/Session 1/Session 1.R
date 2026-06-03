######################
#     FINANCE 4      #
#   TA SESSION #1    #
#  Timur Magzhanov   #
######################

##### PACKAGES #####
install.packages("dplyr")
install.packages("datasets")
install.packages("knitr")
install.packages("kableExtra")
install.packages("tidyr")
install.packages("tinytex")
install.packages("fixest")
install.packages("stargazer")
install.packages("ggplot2")
install.packages("ggthemes")
install.packages("showtext")
install.packages("curl")
install.packages("margins")
install.packages("AER")

##### LIBRARIES #####
library("dplyr") 
library("datasets")
library(knitr)          # For generating and displaying tables
library(kableExtra)     # For beautiful tables
library(tinytex)        # For PDF compilation from LaTeX
library(fixest)         # For high dim fixed effects
library(stargazer)
library(ggplot2)        # for plots
library(ggthemes)       # awesome themes for ggplot2
library(showtext)       # text styles on plots
library(curl)           # for text styles auxiliary
library(margins)        # marginal effects computation
library(AER)            # for Tobit
library(tidyverse)      # was not before
library(broom)          # added

##### DESCRIPTIVE STATISTICS #####
# Load example dataset
data("mtcars")        

# General descriptive statistics for all numeric columns
general_stats <- mtcars %>%
  summarise(across(
    everything(),
    list(
      Mean = ~mean(.),
      SD = ~sd(.),
      Median = ~median(.),
      Min = ~min(.),
      Max = ~max(.)
    )
  )) %>%
  pivot_longer(
    everything(),
    names_to = c("Variable", ".value"),
    names_sep = "_"
  )

# Compute group-level descriptive statistics by number of cylinders
group_stats <- mtcars %>%
  group_by(cyl) %>%
  summarise(across(
    everything(),
    list(
      Mean = ~mean(.),
      SD = ~sd(.),
      Median = ~median(.),
      Min = ~min(.),
      Max = ~max(.)
    )
  )) %>%
  pivot_longer(
    cols = -c(cyl),
    names_to = c("Variable", ".value"),
    names_sep = "_"
  ) %>%
  arrange(cyl, Variable)

# Display general stats in the console
cat("\n\nGeneral Descriptive Statistics:\n")
general_table_console <- kable(general_stats, format = "markdown", caption = "General Descriptive Statistics for mtcars")
print(general_table_console)

# Display group stats in the console
cat("\n\nGroup Statistics by Cylinders:\n")
group_table_console <- kable(group_stats, format = "markdown", caption = "Group Statistics by Cylinders")
print(group_table_console)

# Export general stats to LaTeX
general_table_latex <- kable(general_stats, format = "latex", booktabs = TRUE) %>%
  kable_styling(latex_options = c("striped", "hold_position"), full_width = FALSE) %>%
  add_header_above(c(" " = 1, "General Descriptive Statistics" = 5))

# Export group stats to LaTeX
group_table_latex <- kable(group_stats, format = "latex", booktabs = TRUE) %>%
  kable_styling(latex_options = c("striped", "hold_position"), full_width = FALSE) %>%
  add_header_above(c(" " = 2, "Group Statistics by Cylinders" = 5))

# Save separate LaTeX files 
#writeLines(general_table_latex, "general_table.tex")
#writeLines(group_table_latex, "group_table.tex")


##### LATEX -> PDF #####

# Create a LaTeX code as a string (example)
latex_code <- "
\\documentclass{article}
\\usepackage{booktabs}
\\usepackage{longtable}
\\begin{document}

\\section*{Example Table}
Here is an example table created in R and exported to LaTeX:

\\begin{longtable}{lrrr}
\\toprule
Variable & Mean & SD & Median \\\\
\\midrule
mpg       & 20.09 & 6.03 & 19.20 \\\\
disp      & 230.72 & 123.94 & 196.30 \\\\
hp        & 146.69 & 68.56 & 123.00 \\\\
\\bottomrule
\\end{longtable}

\\end{document}
"

# Save LaTeX code to a .tex file
writeLines(latex_code, "example.tex")

# Compile the LaTeX file into a PDF
tinytex::pdflatex("example.tex")

# Wrap the tables in a full LaTeX document
latex_document <- paste0("
\\documentclass{article}
\\usepackage{booktabs}
\\usepackage{longtable}
\\usepackage{geometry}
\\usepackage[table]{xcolor} % Added this line for cell coloring
\\geometry{a4paper, margin=1in}
\\begin{document}

\\section*{General Descriptive Statistics}
", general_table_latex, "

\\newpage

\\section*{Group Statistics by Cylinders}
", group_table_latex, "

\\end{document}
")

# Save LaTeX document to file
writeLines(latex_document, "descriptive_statistics.tex")

# Compile the LaTeX document into a PDF
tinytex::pdflatex("descriptive_statistics.tex")

##### HIGH DIMENSIONAL FIXED EFFECTS [1] #####
# visit this for more: 
# https://cran.r-project.org/web/packages/fixest/vignettes/fixest_walkthrough.html

# Load the trade data
data(trade)

# Define four expanding model specifications
model_ols_1 <- feols(log(Euros) ~ log(dist_km) | Origin, data = trade)               # Only Origin
model_ols_2 <- feols(log(Euros) ~ log(dist_km) | Origin + Destination, data = trade) # Add Destination
model_ols_3 <- feols(log(Euros) ~ log(dist_km) | Origin + Destination + Product, data = trade) # Add Product
model_ols_4 <- feols(log(Euros) ~ log(dist_km) | Origin + Destination + Product + Year, data = trade) # Add Year

# Combine models into a list
models <- list(
  model_ols_1,
  model_ols_2,
  model_ols_3,
  model_ols_4
)

# Generate a LaTeX table for the models
etable_latex <- etable(
  models,
  #headers = c(
  #  "Origin FE", 
  #  "Origin + Destination FE", 
  #  "Origin + Destination + Product FE", 
  #  "Origin + Destination + Product + Year FE"
  #),
  cluster = ~Origin + Destination,
  tex = TRUE
)

# Save the LaTeX table to a PDF-friendly document
latex_doc <- c(
  "\\documentclass{article}\n",
  "\\usepackage{booktabs}\n",
  "\\usepackage{geometry}\n",
  "\\geometry{a4paper, margin=1in}\n",
  "\\begin{document}\n",
  "\\section*{OLS Models with Expanding Fixed Effects}\n",
  etable_latex,
  "\\end{document}"
)

# Save and compile the document
writeLines(latex_doc, "ols_expanding_fixed_effects.tex")
tinytex::pdflatex("ols_expanding_fixed_effects.tex")

# Display the table in the console
etable_console <- etable(
  models,
  headers = c(
    "Origin FE", 
    "Origin + Destination FE", 
    "Origin + Destination + Product FE", 
    "Origin + Destination + Product + Year FE"
  ),
  cluster = ~Origin + Destination
)

# Use knitr::kable for a beautiful display in the console
kable(etable_console, align = "c", caption = "OLS Models with Expanding Fixed Effects")

##### HIGH DIMENSIONAL FIXED EFFECTS [2] #####
# Set up models
model_pois <- fepois(Euros ~ log(dist_km) | Origin + Destination + Product + Year, data = trade)
model_ols <- feols(log(Euros) ~ log(dist_km) | Origin + Destination + Product + Year, data = trade)
model_negbin <- fenegbin(Euros ~ log(dist_km) | Origin + Destination + Product + Year, data = trade)

# Generate the etable LaTeX table
etable_latex <- etable(
  list(
    "Poisson" = model_pois,
    "OLS" = model_ols,
    "Negative Binomial" = model_negbin
  ),
  cluster = ~Origin + Destination,
  tex = TRUE,        # Output LaTeX code
  title = "High-Dimensional Fixed Effects Results"
)

latex_doc <- c(
  "\\documentclass{article}",
  "\\usepackage{booktabs}",
  "\\usepackage{geometry}",
  "\\geometry{a4paper, margin=1in}",
  "\\begin{document}",
  "\\section*{High-Dimensional Fixed Effects Results}",
  etable_latex,  # Insert the etable LaTeX table directly
  "\\end{document}"
)

# Write the LaTeX document to a file
writeLines(latex_doc, "high_dim_fixed_effects.tex")

# Compile the LaTeX document into a PDF
tinytex::pdflatex("high_dim_fixed_effects.tex")

# Generate a nice table for console output
etable_console <- etable(
  list(model_pois, model_ols, model_negbin),
  headers = c("Poisson", "OLS", "Negative Binomial"),
  cluster = ~Origin + Destination,
  tex = FALSE
)

# Display the table in the console
kable(etable_console, align = "c", caption = "High-Dimensional Fixed Effects Results")

##### DATA VISUALISATION #####

# 1. Distribution of trade flows (Histogram)
ggplot(trade, aes(x = Euros)) +
  geom_histogram(bins = 30, fill = "skyblue", color = "black", alpha = 0.7) +
  labs(title = "Distribution of Trade Flows",
       x = "Trade Flows (Euros)",
       y = "Frequency") +
  theme_minimal()

# 2. Density Plot of Trade Flows
ggplot(trade, aes(x = Euros)) +
  geom_density(fill = "skyblue", alpha = 0.5) +
  labs(title = "Density Plot of Trade Flows",
       x = "Trade Flows (Euros)",
       y = "Density") +
  theme_minimal()

# 3. Log-Transformed Distribution of Trade Flows
ggplot(trade, aes(x = log1p(Euros))) +
  geom_histogram(bins = 30, fill = "orange", color = "black", alpha = 0.7) +
  labs(title = "Log-Scaled Distribution of Trade Flows",
       x = "Log Trade Flows (log(Euros))",
       y = "Frequency") +
  theme_minimal()

# 4. Log-Transformed Density Plot
ggplot(trade, aes(x = log1p(Euros))) +
  geom_density(fill = "orange", alpha = 0.5) +
  labs(title = "Log-Scaled Density Plot of Trade Flows",
       x = "Log Trade Flows (log(Euros))",
       y = "Density") +
  theme_minimal()

# 5. Beautiful The Economist style plot
# Add the Economist font "Roboto Slab"
font_add_google(name = "Roboto Slab", family = "Roboto Slab")
showtext_auto()

# Define the Economist-style muted color palette
economist_colors <- c("BE" = "#0073C2", "DE" = "#D55E00", "FR" = "#009E73",
                      "IT" = "#F0E442", "NL" = "#CC79A7", "ES" = "#56B4E9")

# Selected countries for density plot
# Germany (DE), France (FR), Netherlands (NL)
# Belgium (BE), Italy (IT), and Spain (ES)
selected_countries <- c("BE", "DE", "FR", "IT", "NL", "ES")

# Filter and transform the data
trade_filtered <- trade %>%
  filter(Destination %in% selected_countries) %>%
  mutate(log_Euros = log(Euros))

# Create the density plot with updates
plot <- ggplot(trade_filtered, aes(x = log_Euros, fill = Destination)) +
  geom_density(alpha = 0.7, size = 0.5, color = NA) +  # Removed outlines for densities
  scale_fill_manual(values = economist_colors) +
  labs(
    title = "Density of Log Trade Flows by Country",
    subtitle = "Trade flows for selected European countries",
    x = "Log Trade Flows",
    y = "Density",
    caption = "Source: Trade Data | Chart by @yourname"
  ) +
  theme(
    # General plot appearance
    text = element_text(family = "Roboto Slab"),
    plot.margin = margin(t = 1, r = 1, b = 1, l = 1, unit = "cm"),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank(),
    panel.grid.major.y = element_line(color = "#dcdbd8"),
    panel.grid.minor.y = element_blank(),
    # Axis text and title sizes
    axis.text = element_text(size = 24, color = "gray8"),
    axis.title = element_text(size = 28, color = "gray8"),
    axis.line.x = element_line(color = "gray8"),
    axis.ticks.y = element_blank(),
    # Title and subtitle sizes
    plot.title = element_text(size = rel(2.2), hjust = 0, face = "bold"),
    plot.subtitle = element_text(size = rel(1.8), hjust = 0),
    plot.caption = element_text(hjust = 0, size = 14, color = "#4B4B4B"),
    # Legend customization
    legend.title = element_blank(),
    legend.position = c(-0, 0.78),  # Fine-tuned closer to the axis
    legend.direction = "vertical",   # Legend in a vertical format
    legend.justification = "left",   # Aligned to the left side
    legend.key = element_blank(),    # Removed legend item frames
    legend.text = element_text(size = 24, margin = margin(l = 3))
  )
# Save the plot as a standalone image
ggsave(plot = plot, filename = "density_plot.png", width = 8, height = 5)

# 6. Scatter plot for trade flows and distance
# Scatter Plot: Log(Distance) vs Log(Trade Flows)
scatter_plot <- ggplot(trade_filtered, aes(x = log(dist_km), y = log_Euros)) +
  geom_point(aes(color = Destination), size = 3, alpha = 0.7) +  # Scatter points
  geom_smooth(method = "lm", se = FALSE, color = "black", linetype = "dashed", size = 1.5) +  # Black dashed trend line
  scale_color_manual(values = economist_colors) +  # Use the same colors for consistency
  labs(
    title = "Relationship Between Distance and Trade Flows",
    subtitle = "Trade flows vs distance for selected European countries",
    x = "Log(Distance)",
    y = "Log(Trade Flows)",
    caption = "Source: Trade Data | Chart by @yourname"
  ) +
  theme(
    # General plot appearance
    text = element_text(family = "Roboto Slab"),
    plot.margin = margin(t = 1, r = 1, b = 1, l = 1, unit = "cm"),
    plot.background = element_rect(fill = "white", color = NA),
    panel.background = element_rect(fill = "white"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor.x = element_blank(),
    panel.grid.major.y = element_line(color = "#dcdbd8"),
    panel.grid.minor.y = element_blank(),
    # Axis text and title sizes (slightly reduced)
    axis.text = element_text(size = 36, color = "gray8"),
    axis.title = element_text(size = 44, color = "gray8"),
    axis.line.x = element_line(color = "gray8"),
    axis.line.y = element_line(color = "gray8"),
    # Title and subtitle sizes (slightly reduced)
    plot.title = element_text(size = rel(3.5), hjust = 0, face = "bold"),
    plot.subtitle = element_text(size = rel(2.8), hjust = 0),
    plot.caption = element_text(hjust = 0, size = 22, color = "#4B4B4B"),
    # Legend customization
    legend.title = element_blank(),
    legend.position = "none"  # Remove legend for simplicity
  )

# Save the scatter plot
ggsave(plot = scatter_plot, filename = "scatter_plot.png", width = 10, height = 6)

##### NONLINEAR MODELS [1]: LOGIT & PROBIT #####
# Generate dataset with 1000 observations
set.seed(123)
data <- tibble(
  X1 = rnorm(1000, mean = 0, sd = 1),
  X2 = rnorm(1000, mean = 5, sd = 2),
  X3 = rnorm(1000, mean = -3, sd = 1.5)
)

# Create a binary outcome (Y) based on a latent variable
latent = 0.5 * data$X1 - 0.3 * data$X2 + 0.2 * data$X3 + rnorm(1000)
data <- data %>% mutate(Y = ifelse(latent > 0, 1, 0))

# Fit Logit model
logit_model <- glm(Y ~ X1 + X2 + X3, data = data, family = binomial(link = "logit"))

# Fit Probit model
probit_model <- glm(Y ~ X1 + X2 + X3, data = data, family = binomial(link = "probit"))

# Fit OLS model
ols_model <- lm(Y ~ X1 + X2 + X3, data = data)

# Let's see equations' estimates in console
stargazer(
  logit_model, probit_model, ols_model,
  type = "text",
  title = "Regression Results",
  dep.var.labels = c("Probability of Y"),
  covariate.labels = c("X1", "X2", "X3"),
  #column.labels = c("Logit", "Probit", "OLS"),
  digits = 3,
  align = TRUE,
  single.row = TRUE
)

# Recovering true DGP parameters:
# Scale Logit coefficients by pi/sqrt(3) (~1.814) due to the logistic variance.
# Probit coefficients directly match the DGP scale.

# Compute marginal effects for Logit and Probit models
logit_mfx <- summary(margins(logit_model))
probit_mfx <- summary(margins(probit_model))

# Adjust column names dynamically based on the `margins` output
logit_mfx_tidy <- logit_mfx %>%
  select(contains("Factor"), contains("AME")) %>%
  rename(term = contains("Factor"), logit_mfx = contains("AME"))

probit_mfx_tidy <- probit_mfx %>%
  select(contains("Factor"), contains("AME")) %>%
  rename(term = contains("Factor"), probit_mfx = contains("AME"))

# Extract coefficients for OLS and combine with marginal effects
ols_coeffs <- tidy(ols_model) %>%
  select(term, estimate) %>%
  rename(ols_coeff = estimate)

# Combine all results into a single table
results_table <- full_join(logit_mfx_tidy, probit_mfx_tidy, by = "term") %>%
  full_join(ols_coeffs, by = "term") %>%
  mutate(term = as.character(term),
         term = dplyr::recode(term, "(Intercept)" = "Intercept"))

# Create a LaTeX document to display marginal effects
latex_doc <- c(
  "\\documentclass{article}",
  "\\usepackage{booktabs}",
  "\\usepackage{geometry}",
  "\\geometry{a4paper, margin=1in}",
  "\\begin{document}",
  "\\section*{Logit, Probit, and OLS Model Results}",
  "\\subsection*{Marginal Effects}",
  "\\begin{tabular}{lccc}",
  "\\toprule",
  "Term & Logit Marginal Effect & Probit Marginal Effect & OLS Coefficient \\\\",
  "\\midrule",
  paste(
    results_table$term,
    "&",
    formatC(results_table$logit_mfx, digits = 3, format = "f"),
    "&",
    formatC(results_table$probit_mfx, digits = 3, format = "f"),
    "&",
    formatC(results_table$ols_coeff, digits = 3, format = "f"),
    "\\\\",
    collapse = "\n"
  ),
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{document}"
)

# Write the LaTeX document to a file
writeLines(latex_doc, "marginal_effects_results.tex")
# Compile the LaTeX document into a PDF
tinytex::pdflatex("marginal_effects_results.tex")

# Marginal effects differ from DGP parameters because:
# 1. Marginal effects measure the change in probability of the outcome when a regressor changes by 1 unit,
#    whereas DGP parameters describe the linear contribution to the latent variable.
# 2. For nonlinear models (e.g., Logit and Probit), marginal effects depend on the distribution's slope at the predicted probability,
#    which varies across observations, making marginal effects context-specific and not directly comparable to DGP parameters.



##### NONLINEAR MODELS [2]: TOBIT #####
# Generate data
set.seed(123)
n <- 1000

# Generate a single continuous regressor and a censored outcome
X1 <- rnorm(n, mean = 0, sd = 1)
latent_Y <- 1 + 2 * X1 + rnorm(n, sd = 1)  # True relationship with intercept
Y <- pmax(latent_Y, 0)  # Censor Y at 0 (Tobit model)

# Combine data into a data frame
data_tobit_simple <- data.frame(
  X1 = X1,
  latent_Y = latent_Y,
  Y = Y
)

# Estimate Tobit model
tobit_model_simple <- tobit(Y ~ X1, left = 0, data = data_tobit_simple)

# Add fitted values to the dataset
data_tobit_simple$predicted_Y <- predict(tobit_model_simple, newdata = data_tobit_simple)  # Predicted latent Y
data_tobit_simple$predicted_observed_Y <- pmax(data_tobit_simple$predicted_Y, 0)  # Apply censoring to predicted Y

# Visualization
ggplot(data_tobit_simple, aes(x = X1)) +
  # Plot observed points
  geom_point(aes(y = Y), color = "blue", alpha = 0.5, size = 1.5) +
  # Plot the predicted fit (latent Y)
  geom_line(aes(y = predicted_Y), color = "red", linewidth = 1) +
  # Plot the predicted observed Y (accounting for censoring)
  geom_line(aes(y = predicted_observed_Y), color = "green", linewidth = 1, linetype = "dotted") +
  # Add true underlying relationship for reference
  geom_abline(intercept = 1, slope = 2, linetype = "dashed", color = "black") +
  labs(
    title = "Tobit Model: Observed, Predicted, and True Latent Values",
    subtitle = "Predicted observed Y (green), predicted latent (red), and true latent (black)",
    x = "X1",
    y = "Y"
  ) +
  theme_minimal(base_size = 14)

summary(tobit_model_simple)

##### NONLINEAR MODELS [3]: POISSON #####
# Generate data
set.seed(123)
n <- 1000

# Generate a single continuous regressor and count outcome
X1 <- rnorm(n, mean = 2, sd = 1)  # Regressor
lambda <- exp(0.5 + 0.3 * X1)  # True Poisson mean
Y <- rpois(n, lambda)  # Poisson-distributed outcome

# Combine data into a data frame
data_poisson <- data.frame(
  X1 = X1,
  Y = Y,
  lambda = lambda  # Store the true lambda for reference
)

# Visualize the distribution of Y
ggplot(data_poisson, aes(x = Y)) +
  geom_histogram(binwidth = 1, fill = "skyblue", color = "black", alpha = 0.7) +
  labs(
    title = "Distribution of Dependent Variable (Y)",
    subtitle = "Illustrating the discrete and skewed nature of the Poisson-distributed outcome",
    x = "Y (Count Outcome)",
    y = "Frequency"
  ) +
  theme_minimal(base_size = 14)

# Fit Poisson regression
poisson_model <- glm(Y ~ X1, family = poisson(link = "log"), data = data_poisson)

# Fit OLS regression
ols_model <- lm(Y ~ X1, data = data_poisson)

# Add fitted values to the dataset
data_poisson$poisson_fit <- predict(poisson_model, type = "response")  # Poisson fitted values
data_poisson$ols_fit <- predict(ols_model)  # OLS fitted values

# Scatter plot with fitted values
ggplot(data_poisson, aes(x = X1, y = Y)) +
  # Observed points
  geom_point(color = "blue", alpha = 0.5, size = 1.5) +
  # Poisson fitted values
  geom_line(aes(y = poisson_fit, color = "Poisson Fit"), linewidth = 1) +
  # OLS fitted values
  geom_line(aes(y = ols_fit, color = "OLS Fit"), linewidth = 1, linetype = "dashed") +
  # Customize legend
  scale_color_manual(
    values = c("Poisson Fit" = "red", "OLS Fit" = "black"),
    name = NULL  # Remove the word "Legend"
  ) +
  labs(
    title = "Scatter Plot with Fitted Values",
    subtitle = "Comparison of Poisson and OLS fits for count data",
    x = "X1",
    y = "Y (Count Outcome)"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "top",              # Move legend to the top
    legend.justification = "left",        # Align legend to the left
    legend.box.just = "left",             # Adjust box justification
    legend.text = element_text(size = 12) # Increase legend text size
  )

# Generate comparison table
stargazer(
  poisson_model, ols_model,
  type = "text",
  title = "Comparison of Poisson and OLS Regression Results",
  dep.var.labels = "Count Outcome (Y)",
  covariate.labels = c("X1", "Intercept"),
  column.labels = c("Poisson", "OLS"),
  align = TRUE
)

# Calculate Residuals and Metrics
data_poisson <- data_poisson %>%
  mutate(
    poisson_resid = Y - poisson_fit,
    ols_resid = Y - ols_fit
  )

# Mean Squared Error (MSE)
mse_poisson <- mean(data_poisson$poisson_resid^2)
mse_ols <- mean(data_poisson$ols_resid^2)

# Mean Absolute Error (MAE)
mae_poisson <- mean(abs(data_poisson$poisson_resid))
mae_ols <- mean(abs(data_poisson$ols_resid))

# Create a comparison table
comparison_table <- data.frame(
  Model = c("Poisson", "OLS"),
  MSE = c(mse_poisson, mse_ols),
  MAE = c(mae_poisson, mae_ols)
)

# Display Comparison Table
kable(
  comparison_table,
  caption = "Comparison of Poisson and OLS Models",
  digits = 3,
  align = "c"
)
