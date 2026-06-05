# Central Bank Parsers

Набор парсеров для регулярного сбора пресс-релизов/новостей/публикаций с сайтов центральных банков и регуляторов. Результаты сохраняются локально в папку `data/` (JSON записи + бд + PDF).

## Источники (парсеры)

В проекте подключены следующие источники:

- **BoE (UK)** - Bank of England (news / publications)
- **NBS (Serbia)** - National Bank of Serbia
- **MNB (Hungary)** - Magyar Nemzeti Bank
- **OeNB (Austria)** - Oesterreichische Nationalbank 
- **ACPR (France)** - Autorité de contrôle prudentiel et de résolution (Banque de France)
- **NBKZ (Kazakhstan)** - National Bank of Kazakhstan
- **BNM (Moldova)** - National Bank of Moldova
- **TCMB (Turkey)** - Central Bank of the Republic of Turkey
- **BdE (Spain)** - Banco de España
- **BoC (Canada)** - Bank of Canada (utility-filtered newsroom)
- **CBA (Armenia)** - Central Bank of Armenia (страницы с PDF)
- **CBSL (Sri Lanka)** - Central Bank of Sri Lanka (Monetary Policy Review PDFs)
- **ESRB (EU)** - European Systemic Risk Board (press releases archive by year)
- **CFPB (USA)** - Consumer Financial Protection Bureau (press releases)
- **ICMA (International)** - ICMA News
- **OCC (USA)** - Office of the Comptroller of the Currency (news releases)
- **FSC Korea (KR)** - Financial Services Commission (press releases)
- **NGFS (International)** - Network for Greening the Financial System (press releases)
- **Fed (USA)** - Federal Reserve press releases
- **U.S. Department of the Treasury (USA)** - Press Releases

> Список активных парсеров задаётся в `master.py` или через импорт в `scheduler.py`.

Комментарии и рекомендации по запуску кода через master.py представлены в самом файле в формате комментариев

## Что сохраняется

Каждый документ сохраняется как JSON-запись + pdf + sql


## Требования

- Python 3.10+ (рекомендуется)
- macOS / Linux / Windows

Установка зависимостей - через `requirements.txt`.


## Быстрый старт

### 1) Клонировать репозиторий


git clone https://github.com/annaivanova408/CBR_Parsers.git
cd CBR_Parsers

#Для MacOS/Linux

python3 -m venv .venv
source .venv/bin/activate

#Для Windows (PowerShell):

python -m venv .venv
.venv\Scripts\Activate.ps1

# Установка необходимых зависимостей
pip install -r requirements.txt

### 2) Разовый запуск с окном в N дней:

python scheduler.py --once --days 7

### 3) Регулярный запуск по расписанию (ниже представлен пример, можно поставить любой день недели/время/частоту). Сейчас стоит еженедельный парсинг в 9 часов утра 00 минут. Парсеры запускаются по понедельникам

python scheduler.py --weekday 0 --hour 9 --minute 0 --days 7

