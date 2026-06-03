######################
#     FINANCE 4      #
#   TA SESSION #2    #
#  Timur Magzhanov   #
######################

##### PACKAGES #####
# Install only if not already installed
if (!require("tidyverse")) install.packages("tidyverse")
if (!require("RPostgres")) install.packages("RPostgres")
if (!require("dbplyr")) install.packages("dbplyr")
if (!require("RSQLite")) install.packages("RSQLite")
if (!require("tidyfinance")) install.packages("tidyfinance")
if (!requireNamespace("DBI", quietly = TRUE)) install.packages("DBI")

##### LIBRARIES #####
library(dplyr)
library(tidyr)
library(knitr)          # For generating and displaying tables
library(kableExtra)     # For beautiful tables
library(tinytex)        # For PDF compilation from LaTeX
library(fixest)         # For high dim fixed effects
library(stargazer)
library(ggplot2)
library(ggthemes)       # Awesome themes for ggplot2
library(showtext)       # Text styles on plots
library(curl)           # For auxiliary text styles
library(margins)        # Marginal effects computation
library(AER)            # For Tobit
library(tidyverse)      # Includes ggplot2, dplyr, tidyr, etc.
library(RPostgres)      # For WRDS connection
library(dbplyr)         # Database manipulation with dplyr
library(RSQLite)        # SQLite for local database management
library(tidyfinance)    # Finance-specific tidy tools
library(DBI)
library(stringr)

##### WRDS CONNECTION #####
# Set your WRDS credentials securely (environmental variables)
Sys.setenv(WRDS_USER = "***")
Sys.setenv(WRDS_PASSWORD = "***")

wrds <- dbConnect(
  Postgres(),
  host = "wrds-pgdata.wharton.upenn.edu",
  dbname = "wrds",
  port = 9737,
  sslmode = "require",
  user = Sys.getenv("WRDS_USER"),
  password = Sys.getenv("WRDS_PASSWORD")
)

##### CRSP: collect returns #####
# Load IBES database
ibes_data <- read.csv("IBES.csv")

# Load the CRSP stocknames table for linking
stocknames <- tbl(wrds, Id(schema = "crsp", table = "stocknames"))

# Process the stocknames table for linking
stocknames_processed <- stocknames |>
  mutate(ncusip = coalesce(ncusip, cusip)) |>  # Use ncusip if available, fallback to cusip
  collect()

# List the columns in the crsp.dsf table
columns <- dbGetQuery(wrds, "SELECT * FROM crsp.dsf LIMIT 1;")
names(columns)

# Initialize an empty list to store results
results_list <- list()

# Define the full set of relative column names
all_columns <- c(
  paste0("b", 250:1),  # Columns for days before the event
  "event_day",         # Column for the event day
  paste0("f", 1:25)    # Columns for days after the event
)

# Loop over each row in ibes_data
# Measure start time
start_time <- Sys.time()

# Randomize events to take 100 randomly
# Set seed for reproducibility
set.seed(123)

# Create a random sequence of 100 numbers from 1 to the number of rows in ibes_data
# replace = FALSE insures no duplicates
random_sequence <- sample(1:nrow(ibes_data), size = 1000, replace = FALSE)

for (i in random_sequence) {
  # Extract event details from IBES
  ticker <- ibes_data$OFTIC[i]
  event_date <- as.Date(ibes_data$anndats[i])
  
  # Define date range for returns
  start_date <- event_date - 250
  end_date <- event_date + 25
  
  # Find the corresponding permno using ticker
  linked_row <- stocknames_processed |>
    filter(ticker == !!ticker)  # Match IBES ticker with stocknames ticker
  
  # Check if a match was found
  if (nrow(linked_row) == 0) {
    warning(paste("No matching ticker found in stocknames for IBES row", i))
    next  # Skip to the next iteration
  }
  
  # Extract the permno valid for the event_date
  # Assume that if event_date > nameenddt (the last observation in IBES) then permno holds
  linked_permno <- linked_row |>
    filter(event_date >= namedt & (event_date <= nameenddt | is.na(nameenddt) | nameenddt == max(nameenddt))) |>
    pull(permno)
  
  # Check if a valid permno was found
  if (length(linked_permno) == 0) {
    warning(paste("No valid permno found for ticker", ticker, "on event_date", event_date, "for IBES row", i))
    next
  }
  
  # Use the first valid permno (if multiple are valid, prioritize the first)
  linked_permno <- linked_permno[1]
  
  # Query CRSP daily returns for the specific permno and date range
  crsp_data <- tbl(wrds, Id(schema = "crsp", table = "dsf")) |>
    filter(
      permno == !!linked_permno,  # Use the permno from the linked_row
      date >= start_date,         # Use the correct date column
      date <= end_date
    ) |>
    select(
      permno,                     # Security identifier
      date,                       # Date
      ret                         # Daily returns
    ) |>
    collect()
  
  # Check if any CRSP data was retrieved
  if (nrow(crsp_data) == 0) {
    warning(paste("No CRSP data found for permno", linked_permno, "and row", i))
    next
  }
  
  # Adjust crsp_data to include relative day information
  crsp_data <- crsp_data |>
    mutate(
      relative_day = as.integer(date - event_date)  # Calculate relative days to the event_date
    ) |>
    filter(
      relative_day >= -250 & relative_day <= 25  # Keep only the range of interest
    ) |>
    mutate(
      col_name = case_when(
        relative_day < 0 ~ paste0("b", abs(relative_day)),  # For days before the event
        relative_day > 0 ~ paste0("f", relative_day),      # For days after the event
        relative_day == 0 ~ "event_day"                   # For the event day itself
      )
    )
  
  # Pivot data to create one row per event with columns for each day
  crsp_wide <- crsp_data |>
    select(permno, col_name, ret) |>
    pivot_wider(names_from = col_name, values_from = ret)
  
  # Add missing columns (fill with NA)
  for (col in all_columns) {
    if (!col %in% names(crsp_wide)) {
      crsp_wide[[col]] <- NA
    }
  }
  
  # Reorder columns to match the desired order
  crsp_wide <- crsp_wide |>
    select(permno, all_of(all_columns))
  
  # Add the event_date column
  crsp_wide <- crsp_wide |>
    mutate(event_date = event_date)
  
  # Add the ticker column
  crsp_wide <- crsp_wide |>
    mutate(ticker = ticker)
  
  # Append CRSP data to results list
  results_list[[i]] <- crsp_wide
}

# Combine all results into a single data frame
final_results <- bind_rows(results_list)

# Deduplicate
final_results <- final_results |>
  distinct(permno, event_date, .keep_all = TRUE)

# Measure end time
end_time <- Sys.time()

# Calculate and display the total time taken
time_taken <- end_time - start_time
print(time_taken)

# 22.8 mins for 1500 events
# >25 hours for 100k+ events

##### Add suescore + quick plot #####

# Ensure event_date in both data frames is of the same type
ibes_data <- ibes_data |> mutate(event_date = as.Date(anndats))  # Convert anndats to Date type

# Perform a left join to merge suescore into final_results
final_results <- final_results |>
  left_join(
    ibes_data |> select(ticker = OFTIC, event_date, suescore),  # Select relevant columns for the join
    by = c("ticker", "event_date")  # Match by ticker and event_date
  )

# Filter for cases where suescore < 0
filtered_results <- final_results |>
  filter(suescore < 0)

# Prepare cumulative returns for all cases
cumulative_returns <- filtered_results |>
  pivot_longer(
    cols = starts_with("b") | starts_with("f") | "event_day",
    names_to = "relative_day",
    values_to = "daily_return"
  ) |>
  mutate(
    relative_day = as.integer(
      gsub("^b", "-", gsub("^f", "", gsub("event_day", "0", relative_day)))
    )
  ) |>
  group_by(permno, relative_day) |>
  summarise(
    daily_return = mean(daily_return, na.rm = TRUE), .groups = "drop"
  ) |>
  group_by(relative_day) |>
  summarise(
    average_cum_return = mean(cumsum(daily_return[!is.na(daily_return)]), na.rm = TRUE)
  )

# Filter cumulative_returns to include only -25 to +25 days
filtered_cumulative_returns <- cumulative_returns |>
  filter(relative_day >= -25 & relative_day <= 25)

# Plot cumulative returns
ggplot(filtered_cumulative_returns, aes(x = relative_day, y = average_cum_return)) +
  geom_line(color = "blue", size = 1) +
  geom_point(color = "red") +
  labs(
    title = "Dynamics of unadjusted returns (SUE < 0)",
    x = "Relative day (Event day = 0)",
    y = "Average unadjusted return"
  ) +
  theme_minimal() +
  theme(
    text = element_text(size = 12),
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold")
  )

##### Merge with Fama-French Factors #####
# Load Fama-French factors
ff_factors <- tbl(wrds, Id(schema = "ff", table = "factors_daily")) |>
  select(date, mktrf, smb, hml, rf) |>
  collect()

# Add Fama-French factors and calculate abnormal returns
#final_results_with_abnormal <- final_results |>
#  left_join(ff_factors, by = c("event_date" = "date")) |>
#  mutate(market_return = mktrf + rf) |> # Calculate the market return
#  mutate(across(
#    starts_with("b") | starts_with("f") | "event_day", 
#    ~ .x - market_return, 
#    .names = "abn_{.col}"
#  ))

# Add Fama-French factors and calculate abnormal returns

#final_results_abn <- final_results |>
#  left_join(ff_factors, by = c("event_date" = "date")) |>
#  mutate(market_return = mktrf + rf) |>
#  mutate(across(
#    starts_with("b") | starts_with("f") | "event_day", 
#    ~ .x - market_return, 
#    .names = "{.col}"
#  )) |>
#  select(
#    permno, ticker, event_date, starts_with("b"), "event_day", starts_with("f")
#  )

final_results_abn <- final_results |>
  left_join(ff_factors, by = c("event_date" = "date")) |>
  mutate(market_return = mktrf + rf) |>
  mutate(across(
    starts_with("b") | starts_with("f") | "event_day", 
    ~ .x - market_return, 
    .names = "abn_{.col}"  # Correctly prepend "abn_" to column names
  )) |>
  select(
    permno, ticker, event_date, starts_with("abn_b"), "abn_event_day", starts_with("abn_f")
  )

##### Compute CARs (Method 1) #####
car_results_method1 <- final_results_abn |>
  mutate(
    car_1_1 = rowSums(across(c("abn_b1", "abn_event_day", "abn_f1")), na.rm = TRUE),
    car_3_3 = rowSums(across(c("abn_b3", "abn_b2", "abn_b1", "abn_event_day", "abn_f1", "abn_f2", "abn_f3")), na.rm = TRUE),
    car_5_5 = rowSums(across(c("abn_b5", "abn_b4", "abn_b3", "abn_b2", "abn_b1", "abn_event_day", 
                               "abn_f1", "abn_f2", "abn_f3", "abn_f4", "abn_f5")), na.rm = TRUE)
  )

##### Compute CARs (Method 2: Fama-French 3-Factor Model) #####

# Dynamically merge Fama-French factors for the pre-event window
ff_factors_pre_event <- ff_factors |>
  filter(date >= min(final_results$event_date - 250) & date <= max(final_results$event_date - 22))

# Prepare pre-event data with dynamically aligned Fama-French factors
pre_event_data <- final_results |>
  pivot_longer(
    cols = starts_with("b") | starts_with("f") | "event_day", # Pivot relative days into long format
    names_to = "relative_day",
    values_to = "daily_return"
  ) |>
  mutate(
    relative_day = as.integer(gsub("^b", "-", gsub("^f", "", gsub("^event_day", "0", relative_day)))), # Convert relative_day to integer
    actual_date = event_date + relative_day # Calculate the actual date for each relative day
  ) |>
  left_join(ff_factors, by = c("actual_date" = "date")) |> # Merge Fama-French factors dynamically
  filter(relative_day >= -250 & relative_day <= -22) # Filter for pre-event window

# Run regressions for each permno-event_date combination
ff_model_results <- pre_event_data |>
  group_by(permno, event_date) |>
  summarise(
    # Check if there are sufficient non-NA values to run the regression
    # Only runs the regression if there’s at least one non-NA daily_return
    alpha = if (sum(!is.na(daily_return)) > 0) coef(lm(daily_return ~ mktrf + smb + hml, na.action = na.omit))[1] else NA,
    beta_mktrf = if (sum(!is.na(daily_return)) > 0) coef(lm(daily_return ~ mktrf + smb + hml, na.action = na.omit))[2] else NA,
    beta_smb = if (sum(!is.na(daily_return)) > 0) coef(lm(daily_return ~ mktrf + smb + hml, na.action = na.omit))[3] else NA,
    beta_hml = if (sum(!is.na(daily_return)) > 0) coef(lm(daily_return ~ mktrf + smb + hml, na.action = na.omit))[4] else NA,
    .groups = "drop"
  )

# Merge regression results back into the main dataset
final_results_with_factors <- final_results |>
  left_join(ff_model_results, by = c("permno", "event_date")) |>
  left_join(ff_factors, by = c("event_date" = "date"))

# Calculate expected return and abnormal returns
final_results_with_factors <- final_results_with_factors |>
  mutate(
    expected_return = alpha + beta_mktrf * mktrf + beta_smb * smb + beta_hml * hml
  ) |>
  mutate(
    across(
      starts_with("b") | starts_with("f") | "event_day",
      ~ .x - expected_return,
      .names = "ff_abn_{.col}"  # Prefix abnormal returns with "ff_abn_"
    )
  )

# Compute CARs using Fama-French adjusted abnormal returns
car_results_method2 <- final_results_with_factors |>
  mutate(
    car_1_1_ff = rowSums(across(c("ff_abn_b1", "ff_abn_event_day", "ff_abn_f1")), na.rm = TRUE),
    car_3_3_ff = rowSums(across(c("ff_abn_b3", "ff_abn_b2", "ff_abn_b1", 
                                  "ff_abn_event_day", "ff_abn_f1", "ff_abn_f2", 
                                  "ff_abn_f3")), na.rm = TRUE),
    car_5_5_ff = rowSums(across(c("ff_abn_b5", "ff_abn_b4", "ff_abn_b3", 
                                  "ff_abn_b2", "ff_abn_b1", "ff_abn_event_day", 
                                  "ff_abn_f1", "ff_abn_f2", "ff_abn_f3", 
                                  "ff_abn_f4", "ff_abn_f5")), na.rm = TRUE)
  )
##### Compare CARs from Method 1 and Method 2 #####

# Deduplicate car_results_method1
car_results_method1 <- car_results_method1 |>
  distinct(permno, event_date, .keep_all = TRUE)

# Deduplicate car_results_method2
car_results_method2 <- car_results_method2 |>
  distinct(permno, event_date, .keep_all = TRUE)

# Consolidate CARs into a single dataset using both permno and event_date
car_results_combined <- car_results_method1 |>
  select(permno, event_date, car_1_1, car_3_3, car_5_5) |>
  left_join(
    car_results_method2 |> select(permno, event_date, car_1_1_ff, car_3_3_ff, car_5_5_ff),
    by = c("permno", "event_date")
  )

# Summarize average CARs for both methods
car_summary <- car_results_combined |>
  summarise(
    avg_car_1_1 = mean(car_1_1, na.rm = TRUE),
    avg_car_3_3 = mean(car_3_3, na.rm = TRUE),
    avg_car_5_5 = mean(car_5_5, na.rm = TRUE),
    avg_car_1_1_ff = mean(car_1_1_ff, na.rm = TRUE),
    avg_car_3_3_ff = mean(car_3_3_ff, na.rm = TRUE),
    avg_car_5_5_ff = mean(car_5_5_ff, na.rm = TRUE)
  )

print(car_summary)

# Perform paired t-tests to compare CARs
car_tests <- list(
  car_1_1 = t.test(car_results_combined$car_1_1, car_results_combined$car_1_1_ff, paired = TRUE, na.rm = TRUE),
  car_3_3 = t.test(car_results_combined$car_3_3, car_results_combined$car_3_3_ff, paired = TRUE, na.rm = TRUE),
  car_5_5 = t.test(car_results_combined$car_5_5, car_results_combined$car_5_5_ff, paired = TRUE, na.rm = TRUE)
)

# Extract test statistics and p-values into a summary table
car_test_summary <- tibble(
  Window = c("(-1, +1)", "(-3, +3)", "(-5, +5)"),
  Statistic = sapply(car_tests, function(x) x$statistic),
  P_Value = sapply(car_tests, function(x) x$p.value),
  `Significance` = case_when(
    sapply(car_tests, function(x) x$p.value) < 0.01 ~ "*** (p < 0.01)",
    sapply(car_tests, function(x) x$p.value) < 0.05 ~ "** (p < 0.05)",
    sapply(car_tests, function(x) x$p.value) < 0.1 ~ "* (p < 0.1)",
    TRUE ~ "Not Significant"
  )
)

# Display the summary table
kable(car_test_summary, caption = "T-Test Results for CAR Comparison Between Methods")

# Combine CARs into a long-format table
car_results_long <- car_results_combined |> 
  pivot_longer(
    cols = starts_with("car_"),
    names_to = c("Window", "Method"),
    names_pattern = "car_(\\d_\\d)(_ff)?", # Matches Method 1 (no _ff) and Method 2 (_ff)
    values_to = "CAR"
  ) |> 
  mutate(
    Window = case_when(
      Window == "1_1" ~ "(-1, +1)",
      Window == "3_3" ~ "(-3, +3)",
      Window == "5_5" ~ "(-5, +5)",
      TRUE ~ Window
    ),
    Method = case_when(
      is.na(Method) ~ "Method 1",  # If `_ff` is missing, it's Method 1
      Method == "_ff" ~ "Method 2" # If `_ff` is present, it's Method 2
    )
  ) |> 
  arrange(permno, event_date, Window, Method) # Proper ordering

car_results_long <- car_results_long |>
  mutate(
    Method = case_when(
      is.na(Method) ~ "Method 1", 
      Method == "Method 2" ~ "Method 2"
      )
  )

# Create box plots for each event window
ggplot(car_results_long, aes(x = Method, y = CAR, fill = Method)) +
  geom_boxplot() +
  facet_wrap(~ Window, scales = "free_y") +
  coord_cartesian(ylim = c(-1, 1)) +  # Align zero level across plots
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +  # Add a reference line at zero
  labs(
    title = "Comparison of CARs by Event Window",
    x = NULL,  # Remove x-axis label
    y = "Cumulative Abnormal Return (CAR)"
  ) +
  theme_minimal() +
  theme(
    text = element_text(size = 12),
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
    legend.title = element_blank(),  # Remove legend title
    legend.position = "bottom"
  )

##### Add SUE from IBES and separate Data (Method 1) #####
# Deduplicate
final_results_abn <- final_results_abn |>
  distinct(permno, event_date, .keep_all = TRUE)

# Add SUE data to final_results_abn
final_results_abn <- final_results_abn |>
  left_join(
    ibes_data |> select(ticker = OFTIC, event_date, suescore),
    by = c("ticker", "event_date")
  )

# Separate the data by positive and negative SUE
data_positive_sue <- final_results_abn |> filter(suescore > 0)
data_negative_sue <- final_results_abn |> filter(suescore < 0)

# Perform t-tests for CARs (Method 1) against zero
# Function to compute CARs for a given dataset
compute_cars <- function(data) {
  data |>
    mutate(
      CAR_1_1 = rowSums(across(c("abn_b1", "abn_event_day", "abn_f1")), na.rm = TRUE),
      CAR_3_3 = rowSums(across(c("abn_b3", "abn_b2", "abn_b1", "abn_event_day", "abn_f1", "abn_f2", "abn_f3")), na.rm = TRUE),
      CAR_5_5 = rowSums(across(c("abn_b5", "abn_b4", "abn_b3", "abn_b2", "abn_b1", "abn_event_day", 
                                 "abn_f1", "abn_f2", "abn_f3", "abn_f4", "abn_f5")), na.rm = TRUE)
    )
}

# Apply the function to compute CARs
data_positive_sue <- compute_cars(data_positive_sue)
data_negative_sue <- compute_cars(data_negative_sue)

# For Positive SUE Group
t_test_positive <- data_positive_sue |>
  summarise(
    CAR_1_1_p = t.test(CAR_1_1, mu = 0)$p.value,
    CAR_3_3_p = t.test(CAR_3_3, mu = 0)$p.value,
    CAR_5_5_p = t.test(CAR_5_5, mu = 0)$p.value
  )

# For Negative SUE Group
t_test_negative <- data_negative_sue |>
  summarise(
    CAR_1_1_p = t.test(CAR_1_1, mu = 0)$p.value,
    CAR_3_3_p = t.test(CAR_3_3, mu = 0)$p.value,
    CAR_5_5_p = t.test(CAR_5_5, mu = 0)$p.value
  )

# Compute Average CARs for Each Group
# For Positive SUE Group
average_cars_positive <- data_positive_sue |>
  summarise(
    CAR_1_1 = mean(CAR_1_1, na.rm = TRUE),
    CAR_3_3 = mean(CAR_3_3, na.rm = TRUE),
    CAR_5_5 = mean(CAR_5_5, na.rm = TRUE)
  )

# For Negative SUE Group
average_cars_negative <- data_negative_sue |>
  summarise(
    CAR_1_1 = mean(CAR_1_1, na.rm = TRUE),
    CAR_3_3 = mean(CAR_3_3, na.rm = TRUE),
    CAR_5_5 = mean(CAR_5_5, na.rm = TRUE)
  )

# Combine test results and averages into a single table
car_tests_combined <- tibble(
  Group = c("Positive SUE", "Negative SUE"),
  `CAR(-1,+1)` = c(
    paste0(format(average_cars_positive$CAR_1_1, digits = 3), " (p = ", format(t_test_positive$CAR_1_1_p, digits = 3), ")"),
    paste0(format(average_cars_negative$CAR_1_1, digits = 3), " (p = ", format(t_test_negative$CAR_1_1_p, digits = 3), ")")
  ),
  `CAR(-3,+3)` = c(
    paste0(format(average_cars_positive$CAR_3_3, digits = 3), " (p = ", format(t_test_positive$CAR_3_3_p, digits = 3), ")"),
    paste0(format(average_cars_negative$CAR_3_3, digits = 3), " (p = ", format(t_test_negative$CAR_3_3_p, digits = 3), ")")
  ),
  `CAR(-5,+5)` = c(
    paste0(format(average_cars_positive$CAR_5_5, digits = 3), " (p = ", format(t_test_positive$CAR_5_5_p, digits = 3), ")"),
    paste0(format(average_cars_negative$CAR_5_5, digits = 3), " (p = ", format(t_test_negative$CAR_5_5_p, digits = 3), ")")
  )
)

# Display the final table with average CARs and p-values
kable(car_tests_combined, caption = "Significance Test Results and Average CARs for SUE Groups")

# Prepare data for plotting abnormal returns (filter out NA SUE groups)
plot_data <- final_results_abn |>
  filter(!is.na(suescore)) |> # Remove rows where suescore is NA
  pivot_longer(
    cols = starts_with("abn_b") | starts_with("abn_f") | "abn_event_day",
    names_to = "relative_day",
    values_to = "abn_return"
  ) |>
  mutate(
    relative_day = as.integer(gsub("^abn_b", "-", gsub("^abn_f", "", gsub("^abn_event_day", "0", relative_day)))),
    sue_group = case_when(
      suescore > 0 ~ "Positive SUE",
      suescore < 0 ~ "Negative SUE",
      TRUE ~ NA_character_
    )
  ) |>
  filter(relative_day >= -21 & relative_day <= 21) |> # Restrict to the range [-21, +21]
  group_by(relative_day, sue_group) |>
  summarise(average_abn_return = mean(abn_return, na.rm = TRUE), .groups = "drop")

# Remove rows where suescore is NA (somehow needed again)
plot_data <- plot_data |>
  filter(!is.na(sue_group))

# Plot average abnormal returns
ggplot(plot_data, aes(x = relative_day, y = average_abn_return, color = sue_group)) +
  geom_line(size = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  labs(
    title = "Average abnormal returns by SUE group",
    x = "Relative day (Event day = 0)",
    y = "Average CAR (Method 1)",
    color = "SUE group"
  ) +
  theme_minimal() +
  theme(
    text = element_text(size = 12),
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
    legend.title = element_blank(),
    legend.position = "bottom"
  )

# Compute average CARs by cumulative sum per sue_group
plot_data <- plot_data |>
  arrange(sue_group, relative_day) |>         # Ensure data is ordered by sue_group and relative_day
  group_by(sue_group) |>                       # Group by SUE group
  mutate(average_CAR = cumsum(average_abn_return)) |>  # Compute cumulative sum
  ungroup()

# Plot average CARs
ggplot(plot_data, aes(x = relative_day, y = average_CAR, color = sue_group)) +
  geom_line(size = 1.2) +  # Slightly thicker lines for better visibility
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +  # Reference line at CAR = 0
  labs(
    title = "Average CAR by SUE group",
    x = "Relative day (Event day = 0)",
    y = "Average CAR (Method 1)",
    color = "SUE Group"
  ) +
  theme_minimal() +
  theme(
    text = element_text(size = 12),
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
    legend.title = element_blank(),
    legend.position = "bottom"
  )

# Remark: CAR(-1,+1) according to the plot is -0.048
# It slightly differs from the average CAR(-1,+1) in the table: -0.042 
# This is because for the table we used CAR(-1, +1) as the cumulated abnormal returns with na.rm = TRUE
# On the plot we see CAR(-1, +1) averaged with na.rm = TRUE
# It means that for table we interpret missing abnormal returns as zeros 
# While the plot ignores missing abnormal returns and computes average across observed

##### Add SUE from IBES and Separate Data (Method 2) #####
# Deduplicate
final_results_with_factors <- final_results_with_factors |>
  distinct(permno, event_date, .keep_all = TRUE)

# Add SUE data to final_results_with_factors
#final_results_with_factors <- final_results_with_factors |>
#  left_join(
#    ibes_data |> select(ticker = OFTIC, event_date, suescore),
#    by = c("ticker", "event_date")
#  )

# Separate the data by positive and negative SUE
data_positive_sue_method2 <- final_results_with_factors |> filter(suescore > 0)
data_negative_sue_method2 <- final_results_with_factors |> filter(suescore < 0)

# Perform t-tests for CARs (Method 2) against zero
# Function to compute CARs for Method 2
compute_cars_method2 <- function(data) {
  data |>
    mutate(
      CAR_1_1 = rowSums(across(c("ff_abn_b1", "ff_abn_event_day", "ff_abn_f1")), na.rm = TRUE),
      CAR_3_3 = rowSums(across(c("ff_abn_b3", "ff_abn_b2", "ff_abn_b1", "ff_abn_event_day", "ff_abn_f1", "ff_abn_f2", "ff_abn_f3")), na.rm = TRUE),
      CAR_5_5 = rowSums(across(c("ff_abn_b5", "ff_abn_b4", "ff_abn_b3", "ff_abn_b2", "ff_abn_b1", "ff_abn_event_day", 
                                 "ff_abn_f1", "ff_abn_f2", "ff_abn_f3", "ff_abn_f4", "ff_abn_f5")), na.rm = TRUE)
    )
}

# Apply the function to compute CARs for Method 2
data_positive_sue_method2 <- compute_cars_method2(data_positive_sue_method2)
data_negative_sue_method2 <- compute_cars_method2(data_negative_sue_method2)

# For Positive SUE Group
t_test_positive_method2 <- data_positive_sue_method2 |>
  summarise(
    CAR_1_1_p = t.test(CAR_1_1, mu = 0)$p.value,
    CAR_3_3_p = t.test(CAR_3_3, mu = 0)$p.value,
    CAR_5_5_p = t.test(CAR_5_5, mu = 0)$p.value
  )

# For Negative SUE Group
t_test_negative_method2 <- data_negative_sue_method2 |>
  summarise(
    CAR_1_1_p = t.test(CAR_1_1, mu = 0)$p.value,
    CAR_3_3_p = t.test(CAR_3_3, mu = 0)$p.value,
    CAR_5_5_p = t.test(CAR_5_5, mu = 0)$p.value
  )

# Compute Average CARs for Each Group
# For Positive SUE Group
average_cars_positive_method2 <- data_positive_sue_method2 |>
  summarise(
    CAR_1_1 = mean(CAR_1_1, na.rm = TRUE),
    CAR_3_3 = mean(CAR_3_3, na.rm = TRUE),
    CAR_5_5 = mean(CAR_5_5, na.rm = TRUE)
  )

# For Negative SUE Group
average_cars_negative_method2 <- data_negative_sue_method2 |>
  summarise(
    CAR_1_1 = mean(CAR_1_1, na.rm = TRUE),
    CAR_3_3 = mean(CAR_3_3, na.rm = TRUE),
    CAR_5_5 = mean(CAR_5_5, na.rm = TRUE)
  )

# Combine test results and averages for Method 2 into a single table
car_tests_combined_method2 <- tibble(
  Group = c("Positive SUE", "Negative SUE"),
  `CAR(-1,+1)` = c(
    paste0(format(average_cars_positive_method2$CAR_1_1, digits = 3), " (p = ", format(t_test_positive_method2$CAR_1_1_p, digits = 3), ")"),
    paste0(format(average_cars_negative_method2$CAR_1_1, digits = 3), " (p = ", format(t_test_negative_method2$CAR_1_1_p, digits = 3), ")")
  ),
  `CAR(-3,+3)` = c(
    paste0(format(average_cars_positive_method2$CAR_3_3, digits = 3), " (p = ", format(t_test_positive_method2$CAR_3_3_p, digits = 3), ")"),
    paste0(format(average_cars_negative_method2$CAR_3_3, digits = 3), " (p = ", format(t_test_negative_method2$CAR_3_3_p, digits = 3), ")")
  ),
  `CAR(-5,+5)` = c(
    paste0(format(average_cars_positive_method2$CAR_5_5, digits = 3), " (p = ", format(t_test_positive_method2$CAR_5_5_p, digits = 3), ")"),
    paste0(format(average_cars_negative_method2$CAR_5_5, digits = 3), " (p = ", format(t_test_negative_method2$CAR_5_5_p, digits = 3), ")")
  )
)

# Display the final table with average CARs and p-values for Method 2
kable(car_tests_combined_method2, caption = "Significance Test Results and Average CARs for SUE Groups (Method 2)")

# Prepare data for plotting abnormal returns for Method 2 (filter out NA SUE groups)
plot_data_method2_abn <- final_results_with_factors |>
  filter(!is.na(suescore)) |> # Remove rows where suescore is NA
  pivot_longer(
    cols = starts_with("ff_abn_b") | starts_with("ff_abn_f") | "ff_abn_event_day",
    names_to = "relative_day",
    values_to = "abn_return"
  ) |>
  mutate(
    # Convert relative day names into integer days
    relative_day = as.integer(gsub("^ff_abn_b", "-", gsub("^ff_abn_f", "", gsub("^ff_abn_event_day", "0", relative_day)))),
    sue_group = case_when(
      suescore > 0 ~ "Positive SUE",
      suescore < 0 ~ "Negative SUE",
      TRUE ~ NA_character_
    )
  ) |>
  filter(relative_day >= -21 & relative_day <= 21) |> # Restrict to the range [-21, +21]
  group_by(relative_day, sue_group) |>
  summarise(average_abn_return = mean(abn_return, na.rm = TRUE), .groups = "drop")

# Remove rows where suescore is NA (somehow needed again)
plot_data_method2_abn <- plot_data_method2_abn |>
  filter(!is.na(sue_group))

# Plot average abnormal returns for Method 2
ggplot(plot_data_method2_abn, aes(x = relative_day, y = average_abn_return, color = sue_group)) +
  geom_line(size = 1) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +
  labs(
    title = "Average abnormal returns by SUE group (Method 2)",
    x = "Relative day (Event day = 0)",
    y = "Average Abnormal Return (Method 2)",
    color = "SUE group"
  ) +
  theme_minimal() +
  theme(
    text = element_text(size = 12),
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
    legend.title = element_blank(),
    legend.position = "bottom"
  )

# Prepare data for plotting CARs for Method 2
plot_data_method2 <- final_results_with_factors |>
  filter(!is.na(suescore)) |> # Remove rows where suescore is NA
  pivot_longer(
    cols = starts_with("ff_abn_b") | starts_with("ff_abn_f") | "ff_abn_event_day",
    names_to = "relative_day",
    values_to = "abn_return"
  ) |>
  mutate(
    relative_day = as.integer(gsub("^ff_abn_b", "-", gsub("^ff_abn_f", "", gsub("^ff_abn_event_day", "0", relative_day)))),
    sue_group = case_when(
      suescore > 0 ~ "Positive SUE",
      suescore < 0 ~ "Negative SUE",
      TRUE ~ NA_character_
    )
  ) |>
  filter(relative_day >= -21 & relative_day <= 21) |> # Restrict to the range [-21, +21]
  group_by(relative_day, sue_group) |>
  summarise(average_abn_return = mean(abn_return, na.rm = TRUE), .groups = "drop")

# Remove rows where suescore is NA (somehow needed again)
plot_data_method2 <- plot_data_method2 |>
  filter(!is.na(sue_group))

# Compute average CARs for plotting by cumulative sum per sue_group
plot_data_method2 <- plot_data_method2 |>
  arrange(sue_group, relative_day) |>         # Ensure data is ordered by sue_group and relative_day
  group_by(sue_group) |>                       # Group by SUE group
  mutate(average_CAR = cumsum(average_abn_return)) |>  # Compute cumulative sum
  ungroup()

# Plot average CARs for Method 2
ggplot(plot_data_method2, aes(x = relative_day, y = average_CAR, color = sue_group)) +
  geom_line(size = 1.2) +  # Slightly thicker lines for better visibility
  geom_hline(yintercept = 0, linetype = "dashed", color = "black") +  # Reference line at CAR = 0
  labs(
    title = "Average CAR by SUE group",
    x = "Relative day (Event day = 0)",
    y = "Average CAR (Method 2)",
    color = "SUE Group"
  ) +
  theme_minimal() +
  theme(
    text = element_text(size = 12),
    plot.title = element_text(hjust = 0.5, size = 14, face = "bold"),
    legend.title = element_blank(),
    legend.position = "bottom"
  )

##### Compare CARs (Method 1) vs. (Method 2) by SUE group #####
# Combine CARs from Method 1 and Method 2 for Positive SUE Group
car_results_positive <- data_positive_sue |>
  select(permno, event_date, CAR_1_1, CAR_3_3, CAR_5_5) |>
  left_join(
    data_positive_sue_method2 |>
      select(permno, event_date, CAR_1_1 = CAR_1_1, CAR_3_3 = CAR_3_3, CAR_5_5 = CAR_5_5),
    by = c("permno", "event_date"),
    suffix = c("_method1", "_method2")
  )

# Perform paired t-tests for Positive SUE Group
car_tests_positive_sue <- tibble(
  Window = c("(-1, +1)", "(-3, +3)", "(-5, +5)"),
  `Statistic (Positive SUE)` = c(
    t.test(car_results_positive$CAR_1_1_method1, car_results_positive$CAR_1_1_method2, paired = TRUE)$statistic,
    t.test(car_results_positive$CAR_3_3_method1, car_results_positive$CAR_3_3_method2, paired = TRUE)$statistic,
    t.test(car_results_positive$CAR_5_5_method1, car_results_positive$CAR_5_5_method2, paired = TRUE)$statistic
  ),
  `P-value (Positive SUE)` = c(
    t.test(car_results_positive$CAR_1_1_method1, car_results_positive$CAR_1_1_method2, paired = TRUE)$p.value,
    t.test(car_results_positive$CAR_3_3_method1, car_results_positive$CAR_3_3_method2, paired = TRUE)$p.value,
    t.test(car_results_positive$CAR_5_5_method1, car_results_positive$CAR_5_5_method2, paired = TRUE)$p.value
  )
)

# Combine CARs from Method 1 and Method 2 for Negative SUE Group
car_results_negative <- data_negative_sue |>
  select(permno, event_date, CAR_1_1, CAR_3_3, CAR_5_5) |>
  left_join(
    data_negative_sue_method2 |>
      select(permno, event_date, CAR_1_1 = CAR_1_1, CAR_3_3 = CAR_3_3, CAR_5_5 = CAR_5_5),
    by = c("permno", "event_date"),
    suffix = c("_method1", "_method2")
  )

# Perform paired t-tests for Negative SUE Group
car_tests_negative_sue <- tibble(
  Window = c("(-1, +1)", "(-3, +3)", "(-5, +5)"),
  `Statistic (Negative SUE)` = c(
    t.test(car_results_negative$CAR_1_1_method1, car_results_negative$CAR_1_1_method2, paired = TRUE)$statistic,
    t.test(car_results_negative$CAR_3_3_method1, car_results_negative$CAR_3_3_method2, paired = TRUE)$statistic,
    t.test(car_results_negative$CAR_5_5_method1, car_results_negative$CAR_5_5_method2, paired = TRUE)$statistic
  ),
  `P-value (Negative SUE)` = c(
    t.test(car_results_negative$CAR_1_1_method1, car_results_negative$CAR_1_1_method2, paired = TRUE)$p.value,
    t.test(car_results_negative$CAR_3_3_method1, car_results_negative$CAR_3_3_method2, paired = TRUE)$p.value,
    t.test(car_results_negative$CAR_5_5_method1, car_results_negative$CAR_5_5_method2, paired = TRUE)$p.value
  )
)

# Combine results into one table for both SUE groups
car_comparison_results <- left_join(
  car_tests_positive_sue,
  car_tests_negative_sue,
  by = "Window"
)

# Update column names and format the results with 3 digits
car_comparison_results <- car_comparison_results |>
  mutate(
    `t-stat. (SUE>0)` = round(`Statistic (Positive SUE)`, 3),
    `P-value (SUE>0)` = round(`P-value (Positive SUE)`, 3),
    `t-stat. (SUE<0)` = round(`Statistic (Negative SUE)`, 3),
    `P-value (SUE<0)` = round(`P-value (Negative SUE)`, 3)
  ) |>
  select(
    Window,
    `t-stat. (SUE>0)`,
    `P-value (SUE>0)`,
    `t-stat. (SUE<0)`,
    `P-value (SUE<0)`
  )

# Display the updated table
kable(car_comparison_results, caption = "Comparison of CARs (Method 1 vs. Method 2) by SUE group")

##### Save final results #####
write.csv(final_results, "final_results_1000.csv")
