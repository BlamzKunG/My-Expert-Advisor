# MetaTrader 5 Expert Advisors Collection

[![MQL5](https://img.shields.io/badge/Language-MQL5-blue.svg)](https://www.mql5.com)
[![Platform](https://img.shields.io/badge/Platform-MetaTrader%205-orange.svg)](https://www.metatrader5.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A collection of algorithmic trading Expert Advisors (EAs), Scripts, and parameter presets for MetaTrader 5 (MT5).

---

## Repository Structure

```text
.
├── Experts/                      # MQL5 Expert Advisor source files (.mq5)
│   ├── HaruuSignalReceiver.mq5
│   ├── MACD_Martingale_Grid.mq5
│   ├── ORC_Crypto_Ichimoku_H4_EA.mq5
│   ├── XAUUSD_Adaptive_MeanReversion_EA.mq5
│   └── XAUUSD_Advanced_Grid_EA.mq5
├── Indicators/                   # Custom Indicators (Pine Script / MQL5)
│   └── Supertrend_DeMarker_StochRSI_Signal.pine
├── Scripts/                      # MQL5 Script source files (.mq5)
│   └── ExportMultiData_M5.mq5
├── presets/                      # Parameter preset files (.set)
│   ├── Advanced_Grid/
│   │   ├── Conservative_XAUUSD.set
│   │   ├── Balanced_XAUUSD.set
│   │   └── Aggressive_XAUUSD.set
│   └── MeanReversion_Grid/
│       ├── SmallAccount_500USD.set
│       ├── Standard_2000USD.set
│       └── Pro_5000USD.set
├── LICENSE                       # MIT License
└── README.md                     # Repository documentation
```

---

## Available Files

### Expert Advisors
| File | Category / Target Asset | Preset Directory |
| :--- | :--- | :--- |
| [`Experts/XAUUSD_Advanced_Grid_EA.mq5`](Experts/XAUUSD_Advanced_Grid_EA.mq5) | Grid / XAUUSD | [`presets/Advanced_Grid/`](presets/Advanced_Grid/) |
| [`Experts/XAUUSD_Adaptive_MeanReversion_EA.mq5`](Experts/XAUUSD_Adaptive_MeanReversion_EA.mq5) | Mean Reversion / XAUUSD | [`presets/MeanReversion_Grid/`](presets/MeanReversion_Grid/) |
| [`Experts/MACD_Martingale_Grid.mq5`](Experts/MACD_Martingale_Grid.mq5) | Grid / Multi-Asset | - |
| [`Experts/ORC_Crypto_Ichimoku_H4_EA.mq5`](Experts/ORC_Crypto_Ichimoku_H4_EA.mq5) | Trend Following / Crypto | - |
| [`Experts/HaruuSignalReceiver.mq5`](Experts/HaruuSignalReceiver.mq5) | Signal Receiver / Multi-Asset | - |

### Indicators (TradingView / Pine Script)
| File | Platform | Description |
| :--- | :--- | :--- |
| [`Indicators/Supertrend_DeMarker_StochRSI_Signal.pine`](Indicators/Supertrend_DeMarker_StochRSI_Signal.pine) | TradingView (Pine Script v5) | Supertrend Main Trend + DeMarker & Stoch RSI Entry with 10-bar cooldown filter |

### Scripts
| File | Description |
| :--- | :--- |
| [`Scripts/ExportMultiData_M5.mq5`](Scripts/ExportMultiData_M5.mq5) | Multi-Currency M5 Historical Data Exporter |

---

## Installation and Setup (MT5)

1. Clone or Download Repository:
   ```bash
   git clone https://github.com/BlamzKunG/My-Expert-Advisor.git
   ```
2. Copy Files to MT5 Data Folder:
   - In MetaTrader 5, click File -> Open Data Folder.
   - Copy all files from `Experts/` into `MQL5/Experts/`.
   - Copy all files from `Scripts/` into `MQL5/Scripts/`.
   - Copy the `presets/` folder into `MQL5/Presets/`.
3. Compile:
   - Open MetaEditor (F4).
   - Open the target EA or Script from the Navigator panel.
   - Click Compile (F7) and ensure 0 errors, 0 warnings.
4. Attach to Chart:
   - Drag the compiled EA from MT5 Navigator onto your chart.
   - In the EA settings popup, check "Allow Algo Trading".
   - (Optional) Click Load in the Inputs tab to select a `.set` file from `presets/`.

---

## Adding New Files to this Collection

1. Place new Expert Advisors in `Experts/`.
2. Place new Scripts in `Scripts/`.
3. Place associated presets in `presets/<EA_Name>/`.
4. Update the Available Files table in this README.

---

## License and Disclaimer

- License: Distributed under the MIT License.
- Risk Disclaimer: Trading foreign exchange, commodities, and CFDs carries a high level of risk. These Expert Advisors are provided for educational and research purposes. Use at your own discretion.
