# My-Expert-Advisor

## MACD Martingale Grid EA
A MetaTrader 5 Expert Advisor that uses MACD for trend identification combined with a Martingale Grid strategy for position management.

### Features
- **MACD Trend Identification**: Uses MACD main line and signal line crossovers to determine trade direction.
- **Martingale Grid**: Automatically adds positions at set grid steps with a lot multiplier.
- **Basket Take Profit**: Closes all positions in a direction when the total profit reaches a target in USD.
- **Equity Protection**: Automatically closes all positions if the account drawdown exceeds a specified percentage.
- **Trend Reversal Cut**: Optionally closes positions if the MACD trend reverses against the current basket.
- **Trailing Stop**: (New in v1.01) Automatically trails the stop loss to lock in profits.
- **Max Spread Filter**: (New in v1.01) Prevents opening new positions when the market spread is too high.
- **Magic Number Support**: (New in v1.01) Allows running multiple instances on the same symbol.

### Version History
- **v1.02**: 
    - Added EMA Trend Filter on higher timeframes (e.g., H4 EMA 200).
    - Added Dynamic Grid Step based on ATR.
    - Improved MACD entry logic for better responsiveness.
    - Optimized indicator handling and memory management.
- **v1.01**: 
    - Added Trailing Stop feature.
    - Added Max Spread filter.
    - Added Magic Number input.
    - Improved Pip/Point calculation for 3/5 digit brokers.
    - Optimized position management logic.
- **v1.00**: Initial release.

### Disclaimer
Trading involves significant risk. This EA is for educational purposes only. Always test on a demo account before using real funds.
