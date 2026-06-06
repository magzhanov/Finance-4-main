# Finance / Macroeconomics Workspace

Этот репозиторий объединяет три независимых учебно-исследовательских проекта:

- `CBR_Parsers-main` - Python-парсеры публикаций центральных банков и финансовых регуляторов.
- `DSGE` - MATLAB/Dynare-скрипты для моделей New Keynesian, DSGE, IRF, BK-test и оптимальной политики.
- `Finance-4-main` - материалы TA sessions по Finance 4 на R: регрессии, fixed effects, event study, DiD и IV.

## Структура проекта

```text
.
├── CBR_Parsers-main/
├── DSGE/
└── Finance-4-main/
```

Каждая папка запускается отдельно и имеет собственные зависимости.

## 1. `CBR_Parsers-main`

Папка содержит Python-проект для регулярного сбора пресс-релизов, новостей и публикаций с сайтов центральных банков, финансовых регуляторов и международных организаций.

### Основные файлы

- `master.py` - ручной запуск выбранных парсеров за заданное окно времени.
- `scheduler.py` - запуск всех подключенных парсеров один раз или по расписанию.
- `requirements.txt` - зависимости Python.
- `parsers/` - отдельные парсеры по источникам.
- `storage/local.py` - локальное сохранение результатов.
- `logs/` - логи запусков.

### Источники данных

В проекте есть парсеры для Bank of England, National Bank of Serbia, Magyar Nemzeti Bank, OeNB, ACPR, National Bank of Kazakhstan, Bank of Canada, Central Bank of Armenia, ESRB, CFPB, OCC, FSC Korea, NGFS, Federal Reserve, U.S. Treasury и других источников.

### Установка

```bash
cd CBR_Parsers-main
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Для Windows PowerShell:

```powershell
cd CBR_Parsers-main
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### Запуск

Разовый запуск за последние 7 дней:

```bash
python scheduler.py --once --days 7
```

Регулярный запуск по понедельникам в 09:00:

```bash
python scheduler.py --weekday 0 --hour 9 --minute 0 --days 7
```

Ручной запуск через `master.py`:

```bash
python master.py
```

Перед ручным запуском можно отредактировать список `PARSERS` в `master.py`: раскомментировать нужные парсеры и изменить окно сбора данных.

### Результаты

Результаты сохраняются локально в папку `data/`:

- JSON-записи документов;
- PDF-файлы, если они доступны у источника;
- локальная база/служебные файлы хранения.

## 2. `DSGE`

Папка содержит MATLAB- и Dynare-материалы для анализа New Keynesian / DSGE-моделей.

### Основные файлы

- `nk_tfp_3shocks.mod` - Dynare-модель New Keynesian под rational expectations с тремя шоками: TFP, cost-push и monetary policy.
- `nk_tfp_3shocks_DE.mod` - версия модели с diagnostic expectations.
- `simple_RE.m` - аналитическое решение RE-модели и сравнение IRF с Dynare.
- `simple_IRFs.m` - построение IRF и forecast trajectories для RE/DE-моделей.
- `BK_test.m` - проверка условий Blanchard-Kahn вручную и через Dynare.
- `optimal_policy.m` - аналитическое сравнение Ramsey commitment и optimal discretion для cost-push shock.

### Требования

- MATLAB.
- Dynare.

В `.m`-файлах путь к Dynare задан явно, например:

```matlab
dynarePath = 'C:\dynare\4.5.7\matlab';
addpath(dynarePath);
```

Перед запуском на другом компьютере нужно заменить путь на локальный путь к установленному Dynare.

### Запуск

Открыть MATLAB, перейти в папку:

```matlab
cd DSGE
```

Запустить нужный скрипт:

```matlab
simple_RE
simple_IRFs
BK_test
optimal_policy
```

Dynare-модель можно запустить напрямую:

```matlab
dynare nk_tfp_3shocks.mod
dynare nk_tfp_3shocks_DE.mod
```

### Выходные результаты

Скрипты строят графики IRF, сравнивают аналитические и Dynare-решения, печатают диагностические показатели и проверяют условия детерминированности. `simple_IRFs.m` дополнительно сохраняет PNG-графики в папку `DSGE/images/`.

## 3. `Finance-4-main`

Папка содержит R-проект с материалами TA sessions по курсу Finance 4.

### Структура

- `Finance-4.Rproj` - RStudio project.
- `Session 1/` - описательная статистика, LaTeX/PDF-таблицы, OLS, fixed effects, logit/probit, marginal effects.
- `Session 2-3/` - event study на IBES/CRSP, WRDS-подключение, обработка доходностей вокруг событий.
- `Session 4-5/` - staggered Difference-in-Differences, TWFE, Goodman-Bacon decomposition, did/did2s.
- `Session 6/` - instrumental variables: weak instruments, first stage, LATE/ATE distortion.

### Требования

- R.
- RStudio рекомендуется, но не обязателен.
- Для части скриптов нужен LaTeX/TinyTeX.
- Для `Session 2-3` нужен доступ к WRDS.

Основные R-пакеты:

- `dplyr`, `tidyr`, `tidyverse`;
- `knitr`, `kableExtra`, `tinytex`;
- `fixest`, `stargazer`;
- `ggplot2`, `ggthemes`;
- `margins`, `AER`;
- `RPostgres`, `dbplyr`, `RSQLite`, `DBI`, `tidyfinance`;
- `bacondecomp`, `did`, `did2s`;
- `broom`, `stringr`.

### Запуск

Открыть `Finance-4.Rproj` в RStudio или перейти в папку проекта в R:

```r
setwd("Finance-4-main")
```

Запустить нужную сессию:

```r
source("Session 1/Session 1.R")
source("Session 2-3/Session 2-3.R")
source("Session 4-5/Session 4-5.R")
source("Session 6/Session 6.R")
```

### Важное про WRDS

В `Session 2-3/Session 2-3.R` используются переменные окружения:

```r
Sys.setenv(WRDS_USER = "***")
Sys.setenv(WRDS_PASSWORD = "***")
```

Перед реальным запуском нужно заменить значения на свои учетные данные или задать их безопасно вне кода.

### Выходные результаты

Скрипты создают таблицы, графики, PDF/LaTeX-отчеты и CSV-результаты. Например, в `Session 1/` уже есть сгенерированные `.tex` и `.pdf` файлы с таблицами и результатами моделей, а в `Session 2-3/` есть `final_results_1000.csv`.

## Рекомендуемый порядок работы

1. Если нужна автоматизация сбора новостей регуляторов, начинать с `CBR_Parsers-main`.
2. Если нужна макроэкономическая модель или IRF-анализ, работать с `DSGE`.
3. Если нужны учебные материалы и эмпирические упражнения по Finance 4, использовать `Finance-4-main`.

## Примечания

- Папки независимы друг от друга.
- Python, R и MATLAB-зависимости устанавливаются отдельно.
- Сгенерированные данные, логи, PDF и графики могут занимать место; при необходимости их можно хранить отдельно от исходного кода.
- Перед публикацией проекта стоит проверить, что в коде нет реальных логинов, паролей и приватных данных.
