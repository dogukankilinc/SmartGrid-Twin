# SmartGrid-Twin Data Directory

Place your raw SCADA, inverter, or weather station data exports here.

### Supported File Formats:
- **SMA Sunny Portal (Analysis Pro)** CSV exports (`sep=;`, 14-line metadata header, 15-minute resolution).
- **Huawei FusionSolar** smart logger reports (tab-delimited UTF-16LE / UTF-8).
- **Generic Timetable CSVs** with column mappings configured in `config/gesConfig.m` and `src/+ges/+io/`.

> **Note**: Raw data files (`*.csv`, `*.tsv`, `*.mat`) are strictly excluded from version control via `.gitignore` to prevent data leakage and comply with open-source distribution standards.
