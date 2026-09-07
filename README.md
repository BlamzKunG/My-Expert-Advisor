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
│   ├── Zerith_Crypto_Ichimoku_H4_EA.mq5
│   ├── Zerith_Gold_Adaptive_MeanReversion_EA.mq5
│   ├── Zerith_Gold_Advanced_Grid_EA.mq5
│   ├── Zerith_Gold_Trade_Pro_EA.mq5
│   ├── Zerith_London_Breakout_Recovery_EA.mq5
│   ├── Zerith_MACD_Martingale_Grid_EA.mq5
│   ├── Zerith_News_Straddle_ReverseTrailing_EA.mq5
│   ├── Zerith_Oneshot.mq5
│   ├── Zerith_SBR_Liquidity_Sweep_EA.mq5
│   └── Zerith_Supertrend_MultiStrategy_EA.mq5
├── Indicators/                   # Custom Indicators (Pine Script / MQL5)
│   ├── Zerith_Supertrend_DeMarker_Signal.pine
│   └── Zerith_Supertrend_StochRSI_Signal.pine
├── Scripts/                      # MQL5 Script source files (.mq5)
│   └── ExportMultiData_M5.mq5
├── presets/                      # Parameter preset files (.set)
│   ├── Advanced_Grid/
│   │   ├── Conservative_XAUUSD.set
│   │   ├── Balanced_XAUUSD.set
│   │   └── Aggressive_XAUUSD.set
│   ├── MeanReversion_Grid/
│   │   ├── SmallAccount_500USD.set
│   │   ├── Standard_2000USD.set
│   │   └── Pro_5000USD.set
│   ├── News_Straddle/
│   │   ├── XAUUSD_Gold_News_Straddle.set
│   │   └── Forex_Major_News_Straddle.set
│   └── SBR_Liquidity_Sweep/
│       ├── XAUUSD_H4_M15_Gold.set
│       └── EURUSD_H4_M15_Forex.set
├── LICENSE                       # MIT License
└── README.md                     # Repository documentation
```

---

## Available Files

### Expert Advisors (Zerith Series)
| File | Strategy / Target Asset | Description |
| :--- | :--- | :--- |
| [`Experts/Zerith_SBR_Liquidity_Sweep_EA.mq5`](Experts/Zerith_SBR_Liquidity_Sweep_EA.mq5) | Smart Money Concepts (SMC) / Gold & FX | Multi-Timeframe SBR/RBS Flip Zones with LTF Liquidity Sweep & Classic A/V Reversal Trigger |
| [`Experts/Zerith_News_Straddle_ReverseTrailing_EA.mq5`](Experts/Zerith_News_Straddle_ReverseTrailing_EA.mq5) | High-Impact News Straddle / Gold & FX | News Straddle Breakout EA with Opposite Stop Order Trailing SL, Automated Reversal Flip, and Capital Protection |
| [`Experts/Zerith_Gold_Trade_Pro_EA.mq5`](Experts/Zerith_Gold_Trade_Pro_EA.mq5) | Daily Support/Resistance Breakout / XAUUSD | 7 Daily Breakout Modules with Multi-Stage Trailing Stop & Drawdown Protection |
| [`Experts/Zerith_Supertrend_MultiStrategy_EA.mq5`](Experts/Zerith_Supertrend_MultiStrategy_EA.mq5) | Supertrend + 12 MTF DeMarker Matrix / XAUUSD & FX | Multi-Strategy Portfolio Engine with Smart Recovery Grid & Dynamic ATR Spacing |
| [`Experts/Zerith_Oneshot.mq5`](Experts/Zerith_Oneshot.mq5) | 12 MTF DeMarker Matrix / One-Shot + Recovery Grid | First-Instinct One-Shot Initial Entry with Dual-Mode Recovery Grid (100% Original Fixed vs Expanding Multiplier) & Original BE/Trailing Engine |
| [`Experts/Zerith_London_Breakout_Recovery_EA.mq5`](Experts/Zerith_London_Breakout_Recovery_EA.mq5) | London Session Range Breakout (ORB) / GBPUSD & FX | Asian/London Box Breakout with OCO Cancellation & Smart Recovery System |
| [`Experts/Zerith_Gold_Advanced_Grid_EA.mq5`](Experts/Zerith_Gold_Advanced_Grid_EA.mq5) | Advanced Dynamic Grid / XAUUSD | Multi-Tier Dynamic Grid with ATR Volatility Adaptation |
| [`Experts/Zerith_Gold_Adaptive_MeanReversion_EA.mq5`](Experts/Zerith_Gold_Adaptive_MeanReversion_EA.mq5) | Mean Reversion Grid / XAUUSD | Adaptive Statistical Mean Reversion on Gold |
| [`Experts/Zerith_MACD_Martingale_Grid_EA.mq5`](Experts/Zerith_MACD_Martingale_Grid_EA.mq5) | Trend Momentum Grid / Multi-Asset | MACD Zero-Cross Trend Following Grid |
| [`Experts/Zerith_Crypto_Ichimoku_H4_EA.mq5`](Experts/Zerith_Crypto_Ichimoku_H4_EA.mq5) | Trend Following / Crypto | H4 Multi-Timeframe Ichimoku Kinko Hyo Cloud Breakout |
| [`Experts/HaruuSignalReceiver.mq5`](Experts/HaruuSignalReceiver.mq5) | Signal Receiver / Multi-Asset | Webhook / Telegram Signal Execution Engine |

### Indicators (TradingView / Pine Script)
| File | Platform | Description |
| :--- | :--- | :--- |
| [`Indicators/Zerith_Supertrend_DeMarker_Signal.pine`](Indicators/Zerith_Supertrend_DeMarker_Signal.pine) | TradingView (Pine Script v6) | 12-Strategy MTF DeMarker Engine with Supertrend Trend Filter & Live Dashboard |
| [`Indicators/Zerith_Supertrend_StochRSI_Signal.pine`](Indicators/Zerith_Supertrend_StochRSI_Signal.pine) | TradingView (Pine Script v6) | Supertrend Trend Following + DeMarker & Stoch RSI Entry with Cooldown & Anti-Sideway Filters |

### Scripts
| File | Description |
| :--- | :--- |
| [`Scripts/ExportMultiData_M5.mq5`](Scripts/ExportMultiData_M5.mq5) | Multi-Currency M5 Historical Data Exporter |

---

## ⚡ Zerith News Straddle Reverse-Trailing EA (Opposite Stop Order Trailing SL)

Designed specifically for high-volatility news events (US Non-Farm Payrolls, CPI Inflation, FOMC Rate Decisions, PPI, GDP).

### Core Strategy Mechanics:
1. **News Straddle Entry**:
   - Places a **Buy Stop** above Ask and a **Sell Stop** below Bid at a configurable distance (`InpStraddleDistancePoints`).
   - Triggered either manually via on-chart button (`[🚀 PLACE NOW]`), immediately upon launch, or scheduled before news time countdown.
2. **Opposite Stop Order Trailing SL**:
   - When a breakout occurs and **Buy Stop** triggers at e.g. 4000:
     - The pending **Sell Stop** (at 3998) is retained on the book and acts as both the **Stop Loss** and the **Reversal Entry**.
     - As price advances into profit (e.g. price reaches 4001), the Sell Stop is dynamically trailed up to 4000 (locking in breakeven/profit).
     - As price continues advancing (4002, 4003...), the Sell Stop continually trails upward behind the market.
3. **Automated Reversal & Direction Flip**:
   - If market whip-saws and hits the trailed Sell Stop:
     - The Sell Stop executes into an active **SELL position**.
     - The EA immediately **closes the previous BUY position**.
     - A brand-new **BUY STOP** is placed above the current price at the specified distance.
     - The new Buy Stop now becomes the dynamic trailing SL and reversal trigger for the Sell trade.
   - Supports configurable lot multipliers (`InpReverseMultiplier`) and maximum reversal cycles (`InpMaxReversals`).
4. **Safety & Capital Protection**:
   - Spread filter prevents order placement if broker spread widens excessively right before news releases.
   - Max Daily Loss % and Floating Drawdown % equity guards.
   - On-chart interactive HUD dashboard with one-click **[PLACE NOW]**, **[CANCEL PENDING]**, and **[CLOSE ALL & RESET]** buttons.

---

## 🎯 Zerith SBR/RBS + Classic A/V + Liquidity Sweep EA (Smart Money Concepts)

Designed to automate the institutional Smart Money Concepts (SMC) reversal methodology using a 3-layer confluence model.

```mermaid
flowchart TD
    A[HTF Market Structure & BOS Detection\nPERIOD_H4] --> B[SBR / RBS Flip Zone Identified\nSupport <-> Resistance]
    B --> C{1st Retest Discipline\nretest_count == 0?}
    C -- No --> Z[Ignore / Wait Next Zone]
    C -- Yes --> D[LTF Liquidity Sweep\nPERIOD_M15]
    D --> E{Upper/Lower Wick >= 45%\nPrice closes back inside?}
    E -- No --> Z
    E -- Yes --> F[Classic A / V Reversal Pattern\nPinbar / Engulfing Candle]
    F --> G[Open Order: Market Execution]
    G --> H[SL: Past Sweep Wick + ATR Buffer\nTP: Fixed R:R 1:2.5 or 1:3.0]
    H --> I[Breakeven Guard: Lock at 1:1 R:R]
```

### Core Strategy Mechanics:
1. **Multi-Timeframe Structure & Flip Zones (HTF - H4/D1)**:
   - Scans HTF pivot points using swing left/right validation.
   - Detects Break of Structure (BOS):
     - **Bearish BOS:** HTF bar closes below previous Swing Low $\rightarrow$ Flips into **SBR (Support Becomes Resistance)**.
     - **Bullish BOS:** HTF bar closes above previous Swing High $\rightarrow$ Flips into **RBS (Resistance Becomes Support)**.
   - Dynamic Zone Buffer calculated automatically via `ATR(HTF) * InpZoneAtrMult`.
2. **Strict 1st Retest Discipline**:
   - Only trades the **very first retest** of the freshly formed flip zone (`InpOnlyFirstRetest = true`).
   - Prevents chasing degraded zones where institutional liquidity has already been exhausted.
3. **LTF Liquidity Sweep / Stop Hunt Trigger (LTF - M15/M5)**:
   - Verifies price sweeps beyond the SBR/RBS level to purge retail stop orders.
   - **Wick Ratio Rule:** Candlestick wick must constitute $\ge 45\%$ of total candle range.
   - **Rejection Close:** Candle must close back inside/below SBR (for Sell) or inside/above RBS (for Buy).
4. **Classic A / Classic V Reversal Patterns**:
   - **Classic A (Top Reversal):** Fast run-up into resistance, culminating in a sharp A-peak rejection (Shooting star pinbar or Bearish Engulfing).
   - **Classic V (Bottom Reversal):** Fast sell-off into support, culminating in a sharp V-trough rebound (Hammer pinbar or Bullish Engulfing).
5. **Trade Execution & Capital Protection**:
   - **Stop Loss:** Anchored directly behind the liquidity sweep wick plus ATR buffer.
   - **Take Profit:** Configured with positive mathematical expectancy ($1:2.5$ or $1:3.0$ R:R).
   - **Breakeven Engine:** Automatically locks Stop Loss to entry $+ \text{buffer}$ once the position hits $1:1$ R:R.
   - **Prop-Firm Guards:** Max Daily Loss % and Max Floating Drawdown % equity limits.

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
