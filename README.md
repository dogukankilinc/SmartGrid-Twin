# SmartGrid-Twin: Physics-Informed Digital Twin & Multi-Agent Autonomous Diagnosis Framework for Solar PV and Smart Grids

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![MATLAB](https://img.shields.io/badge/MATLAB-R2023b%2B%20%7C%20R2024b-orange.svg)](https://www.mathworks.com/products/matlab.html)
[![Physics-Informed AI](https://img.shields.io/badge/Physics--Informed-Digital%20Twin-success.svg)](#physics-informed-modeling)
[![Architecture](https://img.shields.io/badge/Architecture-Three--Opinion%20Consensus-purple.svg)](#three-opinion-consensus-architecture)
[![Open Source for Energy](https://img.shields.io/badge/Open%20Source-Energy%20Transition-brightgreen.svg)](https://github.com/)

**SmartGrid-Twin** is an open-source, physics-informed digital twin and multi-agent autonomous monitoring system for solar photovoltaic (PV) generation and smart grid integration. Developed with a strict **"Zero-Unused-Data"** architecture, it transforms raw high-resolution inverter and SCADA telemetry into verifiable physical parameters, electrical twins, automated fault diagnostics, and natural-language expert incident reports.

---

## 🌟 Key Highlights & Scientific Innovations

```
                                  +---------------------------------------+
                                  |     Raw SCADA / Inverter Telemetry    |
                                  | (V_dc, I_dc, U_L1, I_L1, f, R_iso...) |
                                  +---------------------------------------+
                                                      |
                                                      v
                                  +---------------------------------------+
                                  |    Physics-Informed Ingestion Engine  |
                                  |  - Erbs + HDKR POA Irradiance (G_poa) |
                                  |  - Faiman Wind-Cooled Cell Temp       |
                                  |  - Relay Duty De-aliasing (alpha=k/18)|
                                  +---------------------------------------+
                                                      |
                        +-----------------------------+-----------------------------+
                        |                                                           |
                        v                                                           v
         +------------------------------+                            +------------------------------+
         |     1st Opinion: Sensor      |                            |     2nd Opinion: Visual      |
         | Physics Rules & 4-Quadrant   |                            | Multi-Label ResNet-18        |
         | MPP Envelopes (dV, dI, R_iso)|                            | Dual-Branch CWT Scalograms   |
         +------------------------------+                            +------------------------------+
                        |                                                           |
                        +-----------------------------+-----------------------------+
                                                      |
                                                      v
                                       +------------------------------+
                                       |     3rd Opinion: Twin/Peer   |
                                       | Electrical Hardware Twin &   |
                                       | Historical Self-Peer k-NN    |
                                       +------------------------------+
                                                      |
                                                      v
                                       +------------------------------+
                                       | Transperent Consensus Engine |
                                       | (Consensus, Conformal Alarms)|
                                       +------------------------------+
                                                      |
                        +-----------------------------+-----------------------------+
                        |                                                           |
                        v                                                           v
         +------------------------------+                            +------------------------------+
         |  Interactive GesDashboard UI |                            | Causal Local LLM/VLM Agent   |
         |  - 5-Node Topology SVG Map   |                            |  - PageChat / In-context RAG |
         |  - 4 Engineering Chart Modes |                            |  - Automated Root-Cause Text |
         +------------------------------+                            +------------------------------+
```

### 1. Zero-Unused-Data Architecture
Industrial solar telemetry typically discards or underutilizes grid frequencies, DC insulation resistances, secondary weather channels, and partial relay intervals. SmartGrid-Twin utilizes **100% of all 21 available telemetry channels**:
- **DC Input ($V_{dc}, I_{dc}$)**: 4-Quadrant MPP envelope trajectory ($dV$ vs. $dI$) detecting hidden thermal derating, bypass diode short-circuits, and partial string disconnection.
- **AC Grid Interconnection ($U_{L1}, I_{L1}, f_{grid}$)**: Local grid Thevenin resistance estimation ($R_{th} = \partial U_{L1} / \partial I_{L1}$), EN 50160 voltage rise/sag detection, and apparent power / power factor verification.
- **Relay Duty Cycle De-aliasing ($\alpha_{relay} = f_{grid}/50 = k/18$)**: Detects sub-interval synchronization switching in low-irradiance regimes, completely eliminating false positive grid failure alarms.
- **Insulation Resistance ($R_{iso}$)**: Diurnal dew/condensation tracking, connector moisture degradation early warnings ($R_{iso} < 1500\ \text{k}\Omega$), and automated rain cleaning validation.
- **Meteorology & Aerodynamics ($G, T_{amb}, T_{mod}, v_{wind}$)**: Distinguishes between synthetic module formulas and true wind convective cooling gains ($\Delta T_{wind}, \Delta E_{wind}$).

### 2. Physics-Informed Digital Twin
- **HDKR Anisotropic POA Transposition**: Decomposes horizontal global irradiance (GHI) via the Erbs model into beam and diffuse components, transposing to arbitrary array plane tilts ($\beta$) and azimuths ($\gamma$) with ASHRAE incident angle modifier (IAM).
- **Dynamic Faiman Cell Temperature Twin**: Couples solar irradiance with dynamic wind cooling:
  $$T_{cell,dyn}(t) = \alpha_{th} T_{cell,dyn}(t-1) + (1-\alpha_{th})\left[T_{amb}(t) + \frac{G_{poa}(t)(1-\eta_{pv})}{U_0 + U_1 v_{wind}(t)}\right]$$
- **Sandia 3-Term Inverter Loss Model**: Calibrates non-linear conversion efficiency $\eta_{inv}(P_{dc}, V_{dc})$ across all operating voltages.
- **8-Stage Physical Loss Waterfall**: Quantifies and attributes energy losses from STC potential to the grid interconnection.

### 3. Three-Opinion Consensus Diagnosis Framework
Rather than relying on a single fallible neural network or rigid heuristic, decisions are formed by a multi-agent **Three-Opinion Architecture**:
1. **1st Opinion (Physics & Sensor Rules)**: Determinate constraints over current, voltage, insulation, and frequency boundaries with conformal false-alarm bounds ($\alpha \le 0.05$).
2. **2nd Opinion (Multi-Label Deep Scalogram CNN)**: Continuous Wavelet Transform (CWT) analytical Morlet scalograms fed into a multi-label ResNet-18 with adaptive batch normalization (`AdaBN`).
3. **3rd Opinion (Electrical Twin & Historical Self-Peer k-NN)**: For single-inverter installations, compares real-time DC-to-AC conversion with an electrical hardware twin and historical self-peer operational distributions under matching solar geometry.
4. **Transparent Consensus Engine**: Resolves discrepancies into audited states (`grid_event`, `inverter_trip`, `string_fault`, `thermal_derating`, `soiling`, `healthy`) with actionable field inspection recommendations.

### 4. Interactive Dashboard & Causal LLM/VLM Agent
- **GesDashboard**: Desktop interface built in MATLAB App Designer featuring 4 real-time engineering chart modes.
- **Interactive 5-Node Laboratory Topology Map**: Embedded SVG/HTML5 energy flow visualization (`app/web/plantmap.html`).
- **PageChat Agent**: Contextual RAG engine powered by local Ollama LLMs with 5-gram tokenization and exact causal explanations for complex grid events.

---

## 📂 Repository Structure

```
SmartGrid-Twin/
├── config/
│   └── gesConfig.m              # Central configuration, site coordinates & physics constants
├── src/
│   └── +ges/
│       ├── +io/                 # Multi-vendor SCADA parsers (SMA, Huawei, generic)
│       ├── +ingest/             # Workspace cataloging & temporal state manager
│       ├── +prep/               # Feature engineering, status flags, string voltages
│       ├── +solar/              # HDKR transposition, Faiman thermal twin, sun geometry
│       ├── +anomaly/            # 4-quadrant MPP envelopes, episode builders, derating scan
│       ├── +model/              # M1 expected power regression & conformal alarms
│       ├── +opinions/           # Three-Opinion consensus engine & historical self-peer
│       ├── +scalogram/          # CWT Morlet image generation (RGB-power & RGB-elec)
│       ├── +federated/          # FedAvg & AdaBN domain adaptation algorithms
│       ├── +soiling/            # Theil-Sen degradation & R_iso-verified rain cleaning
│       ├── +forecast/           # Open-Meteo weather integration & thermal early warning
│       ├── +agents/             # PageChat RAG engine, causal arbiter, diagnosis generator
│       ├── +llm/                # Local Ollama client & multi-modal base64 pipeline
│       └── +runtime/            # ReplayEngine for deterministic real-time simulation
├── app/
│   ├── @GesDashboard/           # Modular MATLAB App Designer dashboard
│   └── web/                     # Interactive HTML5/CSS3 WebViews (plantmap, chat, notify)
├── scripts/
│   ├── s01_build_dataset.m      # Stage 1a: Telemetry ingestion & alignment
│   ├── s02_estimate_orientation.m# Stage 1b: Empirical array tilt/azimuth estimation
│   ├── s03_build_features.m     # Stage 1c: POA transposition & feature matrix
│   └── v2/                      # Advanced analytics (soiling, losses, thermal twin)
├── tests/                       # Unit & regression test suite (tGesIo, tOpinions, etc.)
├── docs/                        # Complete technical specifications (00 to 05)
├── data/                        # Raw telemetry directory (git-ignored)
├── artifacts/                   # Pre-allocated model & cache directories (git-ignored)
├── setupGes.m                   # Environment & path initialization
├── GES_Baslat.m                 # Single-click entry point
├── LICENSE                      # Apache-2.0 License
├── CONTRIBUTING.md               # Contribution guidelines
└── README.md                    # Project documentation
```

---

## 🚀 Quick Start

### Prerequisites
- **MATLAB** R2023b or R2024b
- *Recommended Toolboxes*: Deep Learning Toolbox, Signal Processing Toolbox, Statistics and Machine Learning Toolbox, Parallel Computing Toolbox.
- *(Optional)* [Ollama](https://ollama.ai/) with `llama3` or `qwen2.5:7b` for local offline AI assistance.

### Installation
Clone the repository:
```bash
git clone https://github.com/your-username/SmartGrid-Twin.git
cd SmartGrid-Twin
```

### Running the System
Open MATLAB in the project directory and execute:
```matlab
% 1. Initialize project paths and toolboxes
setupGes();

% 2. Run unit & regression test suite
runAllTests();

% 3. Launch the Interactive Dashboard & Autonomous Agent
GES_Baslat();
```

---

## 📊 Comprehensive Technical Documentation

Detailed mathematical formulations and architectural design documents are available in the [`docs/`](docs/) directory:
- [**docs/00_INDEX_ve_Genel_Bakis.md**](docs/00_INDEX_ve_Genel_Bakis.md): Architecture overview and empirical discovery summary.
- [**docs/01_Veri_Hatti_IO_Ingest_Prep_Runtime.md**](docs/01_Veri_Hatti_IO_Ingest_Prep_Runtime.md): Ingestion pipeline, asynchronous reboot event latching, and coalesce logic.
- [**docs/02_Fiziksel_Modelleme_Solar_Termal_Kirlenme_Tahmin.md**](docs/02_Fiziksel_Modelleme_Solar_Termal_Kirlenme_Tahmin.md): HDKR transposition, Faiman thermal models, and 8-stage loss waterfall.
- [**docs/03_Anomali_Tespiti_3Gorus_Scalogram_DerinOgrenme.md**](docs/03_Anomali_Tespiti_3Gorus_Scalogram_DerinOgrenme.md): Three-opinion consensus, 4-quadrant MPP space, and AdaBN domain adaptation.
- [**docs/04_Dashboard_UI_Web_LLM_Ajan_ve_Test_Mimarisi.md**](docs/04_Dashboard_UI_Web_LLM_Ajan_ve_Test_Mimarisi.md): Interactive GUI components, 5-node topology SVG map, and RAG assistant.
- [**docs/05_Veri_Maksimizasyonu_Eksikler_ve_Uygulama_Yol_Haritasi.md**](docs/05_Veri_Maksimizasyonu_Eksikler_ve_Uygulama_Yol_Haritasi.md): 21-column telemetry matrix and implementation roadmap.

---

## 🤝 Application for OpenAI Codex for Open Source

SmartGrid-Twin is submitted to the **[OpenAI Codex for Open Source](https://openai.com/tr-TR/form/codex-for-oss/)** program to accelerate the development of:
1. **Automated Multi-Vendor SCADA Parser Synthesis**: Employing Codex to autonomously generate, test, and validate data ingestion modules across hundreds of proprietary industrial inverter protocols.
2. **Physics-Informed Symbolic Code Derivation**: Utilizing LLM code generation to automatically formulate analytical thermal and optical models for diverse renewable energy assets.
3. **Multi-Agent Collaborative Grid Optimization**: Scaling the agentic reasoning layer to support bi-directional grid dispatch, battery energy storage systems (BESS), and EV microgrid simulations.

---

## 📜 License
This project is licensed under the **Apache License 2.0** - see the [LICENSE](LICENSE) file for details.

---

## ✉️ Contact & Acknowledgments
- **Project Lead**: Doğukan Kılınç
- **Institution / Affiliation**: Renewable Energy Research Facility Smart Grid Laboratory (`SmartGridLab`)
- For inquiries, collaborations, or bug reports, please open an Issue or Pull Request on GitHub.
