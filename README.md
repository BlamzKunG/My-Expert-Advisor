# MetaTrader 5 Expert Advisors Collection

Collection of automated trading Expert Advisors (EA) and utility scripts written in MQL5 for MetaTrader 5.

## Included Expert Advisors

### 1. MACD Martingale Grid EA (`MACD_Martingale_Grid.mq5`)
- Strategy: Combines MACD trend momentum with dynamic grid positioning and position management.
- Platform: MetaTrader 5

### 2. ORC Crypto Ichimoku H4 EA (`ORC_Crypto_Ichimoku_H4_EA.mq5`)
- Strategy: Quantitative crypto trading strategy utilizing Ichimoku Kinko Hyo indicator cloud breakouts and Tenkan/Kijun crosses on the 4-Hour (H4) timeframe.
- Platform: MetaTrader 5

### 3. Haruu Signal Receiver EA (`HaruuSignalReceiver.mq5`)
- Strategy: Client-side signal listener EA that connects to the Haruu Signal API to execute real-time copy trade orders with local lot management and risk filters.
- Platform: MetaTrader 5

### 4. Export Multi Data Script (`ExportMultiData_M5.mq5`)
- Utility: Historical multi-currency candlestick and tick data exporter for AI training pipelines and backtesting datasets.
- Platform: MetaTrader 5

## Installation
1. Open MetaTrader 5.
2. Go to `File` > `Open Data Folder`.
3. Copy `.mq5` files into `MQL5/Experts/` (or `MQL5/Scripts/` for export scripts).
4. In MetaEditor, click `Compile`.
5. Attach the EA to your desired chart with `Allow Algo Trading` enabled.

## License
MIT License
