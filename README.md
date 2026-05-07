# My-Expert-Advisor

## MACD Martingale Grid EA (MT5)

This Expert Advisor (EA) is designed for MetaTrader 5, optimized for highly volatile assets like **XAUUSD**. It combines a **MACD Trend Filter** with a **Martingale/Grid position sizing system**.

### Strategy Logic

1. **Trend Identification**: Uses MACD (Main and Signal lines) to determine the current trend state (Uptrend, Downtrend, or None).
2. **Initial Entry**:
   - Opens a **Buy** position if MACD indicates an Uptrend and no Buy positions are open.
   - Opens a **Sell** position if MACD indicates a Downtrend and no Sell positions are open.
3. **Grid Expansion**: If the price moves against the initial position by a defined step (e.g., 100 pips), it opens additional positions in the same direction with an increased lot size (Martingale).
4. **Risk Management**:
   - **Basket Take Profit**: Closes all positions in a direction once their total net profit reaches a target USD amount.
   - **Trend Reversal Cut**: Closes all positions if the MACD trend completely flips against them.
   - **Equity Protector**: Closes all open positions if the account drawdown exceeds a specified percentage.

### Input Parameters

- **MACD Settings**: Fast EMA, Slow EMA, Signal SMA.
- **Grid Settings**: Initial Lot, Grid Step (Pips), Lot Multiplier, Max Grid Levels.
- **Risk Management**: Basket TP (USD), Equity Stop (%).

### Installation

1. Copy `MACD_Martingale_Grid.mq5` to your MetaTrader 5 `MQL5/Experts` folder.
2. Compile the code or restart MT5.
3. Drag and drop the EA onto the chart (e.g., XAUUSD, H1).
4. Ensure **Algo Trading** is enabled.

---
*Disclaimer: Trading involves significant risk. Use this EA at your own risk.*