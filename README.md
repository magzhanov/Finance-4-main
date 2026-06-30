# Finance / Macroeconomics Workspace

This repository combines three independent educational and research-oriented projects:

- `CBR_Parsers-main` - Python parsers for publications from central banks and financial regulators.
- `DSGE` - MATLAB/Dynare scripts for New Keynesian, DSGE, IRF, Blanchard-Kahn, and optimal policy analysis.
- `Finance-4-main` - Finance 4 TA session materials in R, covering regressions, fixed effects, event studies, Difference-in-Differences, and instrumental variables.

## Project Structure

```text
.
├── CBR_Parsers-main/
├── DSGE/
└── Finance-4-main/
```

Each folder is a separate project with its own dependencies and workflow.

## 1. `CBR_Parsers-main`

This folder contains a Python project for collecting press releases, news, and publications from central banks, financial regulators, and international financial organizations.

### Main Files

- `master.py` - manual runner for selected parsers over a defined time window.
- `scheduler.py` - one-time or scheduled runner for all configured parsers.
- `requirements.txt` - Python dependencies.
- `parsers/` - source-specific parser modules.
- `storage/local.py` - local storage logic.
- `logs/` - run logs.

### Data Sources

The project includes parsers for sources such as the Bank of England, National Bank of Serbia, Magyar Nemzeti Bank, OeNB, ACPR, National Bank of Kazakhstan, Bank of Canada, Central Bank of Armenia, ESRB, CFPB, OCC, FSC Korea, NGFS, Federal Reserve, U.S. Treasury, and others.

### Installation

```bash
cd CBR_Parsers-main
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

For Windows PowerShell:

```powershell
cd CBR_Parsers-main
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### Usage

Run once for the last 7 days:

```bash
python scheduler.py --once --days 7
```

Run every Monday at 09:00:

```bash
python scheduler.py --weekday 0 --hour 9 --minute 0 --days 7
```

Manual run through `master.py`:

```bash
python master.py
```

Before using `master.py`, edit the `PARSERS` list if needed: uncomment the required parsers and adjust the collection window.

### Output

Collected results are saved locally in the `data/` folder:

- JSON document records;
- PDF files when available from the source;
- local database and storage-related files.

## 2. `DSGE`

This folder contains MATLAB and Dynare materials for New Keynesian / DSGE model analysis.

### Main Files

- `nk_tfp_3shocks.mod` - Dynare New Keynesian model under rational expectations with three shocks: TFP, cost-push, and monetary policy.
- `nk_tfp_3shocks_DE.mod` - model version with diagnostic expectations.
- `simple_RE.m` - analytical solution of the RE model and comparison of IRFs with Dynare.
- `simple_IRFs.m` - IRF and forecast trajectory generation for RE/DE models.
- `BK_test.m` - manual and Dynare-based Blanchard-Kahn condition checks.
- `optimal_policy.m` - analytical comparison of Ramsey commitment and optimal discretion under a cost-push shock.

### Requirements

- MATLAB.
- Dynare.

The `.m` files contain an explicit Dynare path, for example:

```matlab
dynarePath = 'C:\dynare\4.5.7\matlab';
addpath(dynarePath);
```

Before running the scripts on another machine, replace this path with the local path to the installed Dynare version.

### Usage

Open MATLAB and move to the folder:

```matlab
cd DSGE
```

Run the desired script:

```matlab
simple_RE
simple_IRFs
BK_test
optimal_policy
```

Dynare model files can also be run directly:

```matlab
dynare nk_tfp_3shocks.mod
dynare nk_tfp_3shocks_DE.mod
```

### Output

The scripts generate IRF figures, compare analytical and Dynare solutions, print diagnostic metrics, and check determinacy conditions. `simple_IRFs.m` also saves PNG figures to `DSGE/images/`.

## 3. `Finance-4-main`

This folder contains an R project with TA session materials for the Finance 4 course.

### Structure

- `Finance-4.Rproj` - RStudio project file.
- `Session 1/` - descriptive statistics, LaTeX/PDF tables, OLS, fixed effects, logit/probit, and marginal effects.
- `Session 2-3/` - event study using IBES/CRSP, WRDS connection, and stock return processing around event dates.
- `Session 4-5/` - staggered Difference-in-Differences, TWFE, Goodman-Bacon decomposition, `did`, and `did2s`.
- `Session 6/` - instrumental variables, weak instruments, first stage diagnostics, and LATE/ATE distortion.

### Requirements

- R.
- RStudio is recommended but not required.
- LaTeX/TinyTeX is required for some PDF outputs.
- WRDS access is required for `Session 2-3`.

Main R packages:

- `dplyr`, `tidyr`, `tidyverse`;
- `knitr`, `kableExtra`, `tinytex`;
- `fixest`, `stargazer`;
- `ggplot2`, `ggthemes`;
- `margins`, `AER`;
- `RPostgres`, `dbplyr`, `RSQLite`, `DBI`, `tidyfinance`;
- `bacondecomp`, `did`, `did2s`;
- `broom`, `stringr`.

### Usage

Open `Finance-4.Rproj` in RStudio or set the working directory in R:

```r
setwd("Finance-4-main")
```

Run the required session:

```r
source("Session 1/Session 1.R")
source("Session 2-3/Session 2-3.R")
source("Session 4-5/Session 4-5.R")
source("Session 6/Session 6.R")
```

### WRDS Credentials

`Session 2-3/Session 2-3.R` uses environment variables:

```r
Sys.setenv(WRDS_USER = "***")
Sys.setenv(WRDS_PASSWORD = "***")
```

Before running the script with real WRDS access, replace these placeholders with your own credentials or set the credentials securely outside the code.

### Output

The scripts generate tables, plots, PDF/LaTeX reports, and CSV results. For example, `Session 1/` already contains generated `.tex` and `.pdf` files with tables and model results, while `Session 2-3/` contains `final_results_1000.csv`.

