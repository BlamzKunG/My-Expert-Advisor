//+------------------------------------------------------------------+
//|                                     MACD_Martingale_Grid.mq5      |
//|                                  Copyright 2026, BlamzKunG        |
//|                                             https://github.com/   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BlamzKunG"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "2.20"
#property strict

//--- Include
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Enums
enum ENUM_LOT_MODE
{
   LOT_MODE_STEP_ADD,   // Step Additive (e.g. +0.01 every N levels) - Recommended
   LOT_MODE_MARTINGALE  // Standard Martingale (Multiplier per level)
};

//--- Input Parameters
input group "=== MACD Settings ==="
input int               InpFastEMA                 = 12;          // Fast EMA Period
input int               InpSlowEMA                 = 26;          // Slow EMA Period
input int               InpSignalSMA               = 9;           // Signal SMA Period
input bool              InpRequireMACDCross        = true;        // Initial Entry on MACD Cross Only (false = state)

input group "=== Trend Filter (Higher TF) ==="
input bool              InpUseTrendFilter          = true;        // Use EMA Trend Filter (Initial Entry Only)
input ENUM_TIMEFRAMES   InpTrendTF                 = PERIOD_H4;   // Trend Timeframe
input int               InpTrendEMA                = 200;         // Trend EMA Period

input group "=== Dynamic Grid (ATR) ==="
input bool              InpUseDynamicGrid          = true;        // Use ATR for Grid Step
input int               InpATRPeriod               = 14;          // ATR Period
input double            InpATRMultiplier           = 2.0;         // ATR Multiplier for Step
input int               InpMinGridStepPips         = 50;          // Minimum Grid Step (Pips)

input group "=== Grid & Lot Sizing Settings ==="
input ENUM_LOT_MODE     InpLotMode                 = LOT_MODE_STEP_ADD; // Lot Calculation Mode
input double            InpInitialLot              = 0.01;        // Initial Lot Size
input double            InpMaxLotLimit             = 0.20;        // Max Single Order Lot Cap
input double            InpLotMultiplier           = 1.5;         // Lot Multiplier (If Martingale Mode)
input int               InpStepEveryNLevels        = 5;           // Increase Lot Every N Levels (If Step Mode)
input double            InpStepLotAdd              = 0.01;        // Lot Amount to Add per Tier (If Step Mode)
input int               InpGridStepPips            = 100;         // Base Grid Step in Pips (if ATR disabled)
input double            InpGridStepMultiplier      = 1.0;         // Grid Step Expansion (1.0 = Fixed, >1.0 = Expands)
input int               InpMaxGridLevels           = 10;          // Max Grid Levels

input group "=== Smart Hedge Recovery (Reduce DD) ==="
input bool              InpEnableHedge             = true;        // Enable Hedge Follow Order
input int               InpStartHedgeAtLevel       = 5;           // Start Hedge when Grid Count >= N
input double            InpHedgeLotRatio           = 0.5;         // Hedge Lot Ratio of Trapped Volume (0.5 = 50%)
input bool              InpAllowIndividualHedgeTP  = false;       // Allow Hedge to Take Profit Individually
input double            InpHedgeTPUSD              = 5.0;         // Individual Hedge TP (USD, if enabled)

input group "=== Profit & Risk Management ==="
input double            InpBasketTPUSD             = 10.0;        // Standard Basket TP (Account Currency $)
input double            InpNetBasketTPUSD          = 5.0;         // Net Basket TP when Hedged (Account Currency $)
input bool              InpUseBasketTrail          = true;        // Use Basket Trailing Profit in USD (Guaranteed Win)
input double            InpBasketTrailStartUSD     = 10.0;        // Profit to Start Trailing ($)
input double            InpBasketTrailStepUSD      = 3.0;         // Trailing Callback Buffer ($)
input double            InpEquityStopPercent       = 20.0;        // Equity Stop Percent (Drawdown Cut)
input int               InpMaxSpread               = 30;          // Max Spread in Pips (0 to disable)
input bool              InpUseTrendCut             = false;       // Close Basket on MACD Reversal (Caution)

input group "=== Advanced Settings ==="
input int               InpMagicNumber             = 123456;      // Magic Number

//--- Global Variables
CTrade         m_trade;              // Trading class
CPositionInfo  m_position;           // Position info class
int            m_handle_macd;        // MACD handle
int            m_handle_ema_trend;   // EMA Trend handle
int            m_handle_atr;         // ATR handle
double         m_macd_main[];        // MACD main buffer
double         m_macd_signal[];      // MACD signal buffer
double         m_ema_trend[];        // EMA trend buffer
double         m_atr_buffer[];       // ATR buffer
int            m_pips_multiplier;    // Multiplier for 3/5 digits
int            m_hedge_magic;        // Unique Magic Number for Hedge positions

// State trackers
bool           m_trading_halted;     // Halted flag when Equity Stop triggers
double         m_max_net_profit_buy; // Peak profit tracked for BUY basket
double         m_max_net_profit_sell;// Peak profit tracked for SELL basket
datetime       m_last_buy_bar;       // Prevent multiple initial buy entries on same bar
datetime       m_last_sell_bar;      // Prevent multiple initial sell entries on same bar

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
double   NormalizeLot(double lots);
double   CalculateNextLot(ENUM_POSITION_TYPE type, int currentCount);
bool     CheckEquityProtection();
bool     UpdateIndicators();
void     HandleNetBasketTPAndTrailing();
void     HandleSmartHedge();
void     HandleTrendReversal();
void     HandleTrading();
int      CountPositions(ENUM_POSITION_TYPE type);
int      CountHedgePositions(ENUM_POSITION_TYPE type);
double   CalculateBasketProfit(ENUM_POSITION_TYPE type);
double   CalculateHedgeProfit(ENUM_POSITION_TYPE type);
double   GetBasketTotalVolume(ENUM_POSITION_TYPE type);
double   GetBasketAveragePrice(ENUM_POSITION_TYPE type);
void     CloseAllPositions(ENUM_POSITION_TYPE type);
void     CloseHedgePositions(ENUM_POSITION_TYPE type);
double   GetLowestPositionPrice(ENUM_POSITION_TYPE type);
double   GetHighestPositionPrice(ENUM_POSITION_TYPE type);
double   GetLastPositionLot(ENUM_POSITION_TYPE type);
bool     OpenPosition(ENUM_POSITION_TYPE type, double lots);
bool     OpenHedgePosition(ENUM_POSITION_TYPE type, double lots);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   m_trading_halted      = false;
   m_max_net_profit_buy  = 0.0;
   m_max_net_profit_sell = 0.0;
   m_last_buy_bar        = 0;
   m_last_sell_bar       = 0;
   m_hedge_magic         = InpMagicNumber + 999;

   //--- Detect pips multiplier (for 3/5 digits)
   m_pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10 : 1;

   //--- Check Account Margin Mode (Recommend Hedging)
   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Print("WARNING: Grid/Martingale & Hedge strategy requires a HEDGING account! Detected Netting account.");
   }

   //--- Configure CTrade
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   
   //--- Set supported order filling mode automatically
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   //--- Initialize MACD handle
   m_handle_macd = iMACD(_Symbol, _Period, InpFastEMA, InpSlowEMA, InpSignalSMA, PRICE_CLOSE);
   if(m_handle_macd == INVALID_HANDLE)
   {
      Print("Failed to create MACD handle");
      return(INIT_FAILED);
   }
   
   //--- Initialize EMA Trend handle
   if(InpUseTrendFilter)
   {
      m_handle_ema_trend = iMA(_Symbol, InpTrendTF, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(m_handle_ema_trend == INVALID_HANDLE)
      {
         Print("Failed to create EMA Trend handle");
         return(INIT_FAILED);
      }
   }

   //--- Initialize ATR handle
   if(InpUseDynamicGrid)
   {
      m_handle_atr = iATR(_Symbol, _Period, InpATRPeriod);
      if(m_handle_atr == INVALID_HANDLE)
      {
         Print("Failed to create ATR handle");
         return(INIT_FAILED);
      }
   }

   //--- Set arrays as series
   ArraySetAsSeries(m_macd_main, true);
   ArraySetAsSeries(m_macd_signal, true);
   ArraySetAsSeries(m_ema_trend, true);
   ArraySetAsSeries(m_atr_buffer, true);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(m_handle_macd != INVALID_HANDLE)
      IndicatorRelease(m_handle_macd);
      
   if(InpUseTrendFilter && m_handle_ema_trend != INVALID_HANDLE) 
      IndicatorRelease(m_handle_ema_trend);
      
   if(InpUseDynamicGrid && m_handle_atr != INVALID_HANDLE) 
      IndicatorRelease(m_handle_atr);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. If halted by Equity Protection, stop trading
   if(m_trading_halted)
      return;

   // 2. Equity Protector (Drawdown cut)
   if(CheckEquityProtection())
      return;

   // 3. Centralized Net Basket TP & Trailing Profit (Guaranteed positive exit)
   HandleNetBasketTPAndTrailing();

   // 4. Smart Hedge Recovery (Opens hedge if basket count >= InpStartHedgeAtLevel)
   if(InpEnableHedge)
      HandleSmartHedge();

   // 5. Update Indicator Values (Uses closed bar 1 to avoid repainting)
   if(!UpdateIndicators())
      return;

   // 6. Optional Trend Reversal Cut (Disabled by default to protect Grid)
   if(InpUseTrendCut)
      HandleTrendReversal();

   // 7. Main Trading Logic (Initial Entry & Grid Averaging)
   HandleTrading();
}

//+------------------------------------------------------------------+
//| Normalize Lot to Broker Step and Min/Max                         |
//+------------------------------------------------------------------+
double NormalizeLot(double lots)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   int lotDigits = 0;
   if(lotStep > 0.0)
   {
      double temp = lotStep;
      while(temp < 1.0 && lotDigits < 8)
      {
         temp *= 10.0;
         lotDigits++;
      }
      lots = MathRound(lots / lotStep) * lotStep;
   }
   lots = NormalizeDouble(lots, lotDigits);

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return lots;
}

//+------------------------------------------------------------------+
//| Calculate Next Grid Order Lot Size                               |
//+------------------------------------------------------------------+
double CalculateNextLot(ENUM_POSITION_TYPE type, int currentCount)
{
   if(currentCount <= 0)
      return NormalizeLot(InpInitialLot);

   double nextLot = InpInitialLot;

   if(InpLotMode == LOT_MODE_MARTINGALE)
   {
      double lastLot = GetLastPositionLot(type);
      nextLot = (lastLot > 0.0) ? (lastLot * InpLotMultiplier) : InpInitialLot;
   }
   else if(InpLotMode == LOT_MODE_STEP_ADD)
   {
      int tier = (InpStepEveryNLevels > 0) ? (currentCount / InpStepEveryNLevels) : 0;
      nextLot = InpInitialLot + (tier * InpStepLotAdd);
   }

   // Cap with Max Lot Limit
   if(InpMaxLotLimit > 0.0 && nextLot > InpMaxLotLimit)
      nextLot = InpMaxLotLimit;

   return NormalizeLot(nextLot);
}

//+------------------------------------------------------------------+
//| Check Equity Protection                                          |
//+------------------------------------------------------------------+
bool CheckEquityProtection()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0) return false;
   
   double drawdown = (balance - equity) / balance * 100.0;

   if(drawdown >= InpEquityStopPercent)
   {
      PrintFormat("Equity Protection Triggered! Drawdown: %.2f%% (Limit: %.2f%%). Closing all positions and halting EA.", 
                  drawdown, InpEquityStopPercent);
      CloseAllPositions(POSITION_TYPE_BUY);
      CloseAllPositions(POSITION_TYPE_SELL);
      CloseHedgePositions(POSITION_TYPE_BUY);
      CloseHedgePositions(POSITION_TYPE_SELL);
      m_max_net_profit_buy  = 0.0;
      m_max_net_profit_sell = 0.0;
      m_trading_halted      = true; // Prevent reopening trades on depleted account
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update Indicator Values (Shift 1 = closed bar)                   |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Copy shift 1 and shift 2 to check crossover on completed candles
   if(CopyBuffer(m_handle_macd, MAIN_LINE, 1, 2, m_macd_main) < 2 ||
      CopyBuffer(m_handle_macd, SIGNAL_LINE, 1, 2, m_macd_signal) < 2)
   {
      return false;
   }

   if(InpUseTrendFilter)
   {
      if(CopyBuffer(m_handle_ema_trend, 0, 1, 1, m_ema_trend) < 1)
         return false;
   }

   if(InpUseDynamicGrid)
   {
      if(CopyBuffer(m_handle_atr, 0, 1, 1, m_atr_buffer) < 1)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Centralized Net Basket TP & Trailing Profit (Guaranteed Positive)|
//+------------------------------------------------------------------+
void HandleNetBasketTPAndTrailing()
{
   //================================================================
   // 1. BUY CYCLE (BUY Grid + SELL Hedge if any)
   //================================================================
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   int hedgeSellCount = CountHedgePositions(POSITION_TYPE_SELL);

   if(buyCount > 0)
   {
      double buyProfit       = CalculateBasketProfit(POSITION_TYPE_BUY);
      double hedgeSellProfit = CalculateHedgeProfit(POSITION_TYPE_SELL);
      double netProfit       = buyProfit + hedgeSellProfit;

      // CASE A: HEDGED RECOVERY (BUY Grid + SELL Hedge both exist)
      if(hedgeSellCount > 0)
      {
         // CRITICAL RULE: NEVER close unless combined NET PROFIT is strictly positive!
         if(netProfit >= InpNetBasketTPUSD)
         {
            PrintFormat("Hedged BUY Cycle: Net TP Hit! Net Profit: $%.2f (Buy: $%.2f, Hedge: $%.2f) >= Target $%.2f. Closing all.",
                        netProfit, buyProfit, hedgeSellProfit, InpNetBasketTPUSD);
            CloseAllPositions(POSITION_TYPE_BUY);
            CloseHedgePositions(POSITION_TYPE_SELL);
            m_max_net_profit_buy = 0.0;
            return;
         }

         // Optional individual hedge TP if enabled
         if(InpAllowIndividualHedgeTP && InpHedgeTPUSD > 0.0 && hedgeSellProfit >= InpHedgeTPUSD)
         {
            PrintFormat("Smart Hedge: Individual Hedge TP Hit ($%.2f >= $%.2f). Booking hedge profit.",
                        hedgeSellProfit, InpHedgeTPUSD);
            CloseHedgePositions(POSITION_TYPE_SELL);
            return;
         }
      }
      // CASE B: NORMAL UNHEDGED BUY GRID
      else
      {
         if(InpUseBasketTrail)
         {
            // Trailing Profit in USD
            if(netProfit >= InpBasketTrailStartUSD)
            {
               if(netProfit > m_max_net_profit_buy)
               {
                  m_max_net_profit_buy = netProfit;
                  PrintFormat("BUY Basket Trailing: Peak profit raised to $%.2f (Locked min: $%.2f)",
                              m_max_net_profit_buy, m_max_net_profit_buy - InpBasketTrailStepUSD);
               }
            }

            // If trailing is active and profit drops to/below locked cutoff
            if(m_max_net_profit_buy >= InpBasketTrailStartUSD)
            {
               double lockedCutoff = m_max_net_profit_buy - InpBasketTrailStepUSD;
               if(netProfit <= lockedCutoff)
               {
                  PrintFormat("BUY Basket Trailing Exit! Profit: $%.2f <= Locked Cutoff: $%.2f. Closing in guaranteed profit.",
                              netProfit, lockedCutoff);
                  CloseAllPositions(POSITION_TYPE_BUY);
                  m_max_net_profit_buy = 0.0;
                  return;
               }
            }
         }
         else
         {
            // Fixed Target TP in USD
            if(netProfit >= InpBasketTPUSD)
            {
               PrintFormat("BUY Basket TP Hit! Profit: $%.2f >= Target: $%.2f. Closing basket.", netProfit, InpBasketTPUSD);
               CloseAllPositions(POSITION_TYPE_BUY);
               m_max_net_profit_buy = 0.0;
               return;
            }
         }
      }
   }
   else
   {
      m_max_net_profit_buy = 0.0;
      // If BUY basket is empty, close any orphaned SELL hedge
      if(hedgeSellCount > 0)
      {
         CloseHedgePositions(POSITION_TYPE_SELL);
      }
   }

   //================================================================
   // 2. SELL CYCLE (SELL Grid + BUY Hedge if any)
   //================================================================
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   int hedgeBuyCount = CountHedgePositions(POSITION_TYPE_BUY);

   if(sellCount > 0)
   {
      double sellProfit     = CalculateBasketProfit(POSITION_TYPE_SELL);
      double hedgeBuyProfit = CalculateHedgeProfit(POSITION_TYPE_BUY);
      double netProfit      = sellProfit + hedgeBuyProfit;

      // CASE A: HEDGED RECOVERY (SELL Grid + BUY Hedge both exist)
      if(hedgeBuyCount > 0)
      {
         // CRITICAL RULE: NEVER close unless combined NET PROFIT is strictly positive!
         if(netProfit >= InpNetBasketTPUSD)
         {
            PrintFormat("Hedged SELL Cycle: Net TP Hit! Net Profit: $%.2f (Sell: $%.2f, Hedge: $%.2f) >= Target $%.2f. Closing all.",
                        netProfit, sellProfit, hedgeBuyProfit, InpNetBasketTPUSD);
            CloseAllPositions(POSITION_TYPE_SELL);
            CloseHedgePositions(POSITION_TYPE_BUY);
            m_max_net_profit_sell = 0.0;
            return;
         }

         // Optional individual hedge TP if enabled
         if(InpAllowIndividualHedgeTP && InpHedgeTPUSD > 0.0 && hedgeBuyProfit >= InpHedgeTPUSD)
         {
            PrintFormat("Smart Hedge: Individual Hedge TP Hit ($%.2f >= $%.2f). Booking hedge profit.",
                        hedgeBuyProfit, InpHedgeTPUSD);
            CloseHedgePositions(POSITION_TYPE_BUY);
            return;
         }
      }
      // CASE B: NORMAL UNHEDGED SELL GRID
      else
      {
         if(InpUseBasketTrail)
         {
            // Trailing Profit in USD
            if(netProfit >= InpBasketTrailStartUSD)
            {
               if(netProfit > m_max_net_profit_sell)
               {
                  m_max_net_profit_sell = netProfit;
                  PrintFormat("SELL Basket Trailing: Peak profit raised to $%.2f (Locked min: $%.2f)",
                              m_max_net_profit_sell, m_max_net_profit_sell - InpBasketTrailStepUSD);
               }
            }

            // If trailing is active and profit drops to/below locked cutoff
            if(m_max_net_profit_sell >= InpBasketTrailStartUSD)
            {
               double lockedCutoff = m_max_net_profit_sell - InpBasketTrailStepUSD;
               if(netProfit <= lockedCutoff)
               {
                  PrintFormat("SELL Basket Trailing Exit! Profit: $%.2f <= Locked Cutoff: $%.2f. Closing in guaranteed profit.",
                              netProfit, lockedCutoff);
                  CloseAllPositions(POSITION_TYPE_SELL);
                  m_max_net_profit_sell = 0.0;
                  return;
               }
            }
         }
         else
         {
            // Fixed Target TP in USD
            if(netProfit >= InpBasketTPUSD)
            {
               PrintFormat("SELL Basket TP Hit! Profit: $%.2f >= Target: $%.2f. Closing basket.", netProfit, InpBasketTPUSD);
               CloseAllPositions(POSITION_TYPE_SELL);
               m_max_net_profit_sell = 0.0;
               return;
            }
         }
      }
   }
   else
   {
      m_max_net_profit_sell = 0.0;
      // If SELL basket is empty, close any orphaned BUY hedge
      if(hedgeBuyCount > 0)
      {
         CloseHedgePositions(POSITION_TYPE_BUY);
      }
   }
}

//+------------------------------------------------------------------+
//| Handle Smart Hedge Entry                                         |
//+------------------------------------------------------------------+
void HandleSmartHedge()
{
   // 1. BUY BASKET IS TRAPPED (Price drops, open SELL Hedge to offset)
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   int hedgeSellCount = CountHedgePositions(POSITION_TYPE_SELL);

   if(buyCount >= InpStartHedgeAtLevel && hedgeSellCount == 0)
   {
      double trappedVolume = GetBasketTotalVolume(POSITION_TYPE_BUY);
      double hedgeLot = trappedVolume * InpHedgeLotRatio;
      if(InpMaxLotLimit > 0.0 && hedgeLot > InpMaxLotLimit)
         hedgeLot = InpMaxLotLimit;

      PrintFormat("Smart Hedge: BUY basket trapped (%d orders, %.2f lots). Opening SELL Hedge (%.2f lots)",
                  buyCount, trappedVolume, hedgeLot);
      OpenHedgePosition(POSITION_TYPE_SELL, hedgeLot);
   }

   // 2. SELL BASKET IS TRAPPED (Price rises, open BUY Hedge to offset)
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   int hedgeBuyCount = CountHedgePositions(POSITION_TYPE_BUY);

   if(sellCount >= InpStartHedgeAtLevel && hedgeBuyCount == 0)
   {
      double trappedVolume = GetBasketTotalVolume(POSITION_TYPE_SELL);
      double hedgeLot = trappedVolume * InpHedgeLotRatio;
      if(InpMaxLotLimit > 0.0 && hedgeLot > InpMaxLotLimit)
         hedgeLot = InpMaxLotLimit;

      PrintFormat("Smart Hedge: SELL basket trapped (%d orders, %.2f lots). Opening BUY Hedge (%.2f lots)",
                  sellCount, trappedVolume, hedgeLot);
      OpenHedgePosition(POSITION_TYPE_BUY, hedgeLot);
   }
}

//+------------------------------------------------------------------+
//| Handle Trend Reversal Cut (Optional)                             |
//+------------------------------------------------------------------+
void HandleTrendReversal()
{
   if(!InpUseTrendCut) return;

   double macdMain = m_macd_main[0];
   double macdSig  = m_macd_signal[0];

   if(macdMain < macdSig && CountPositions(POSITION_TYPE_BUY) > 0)
   {
      Print("Trend Reversal: Closing all Buy positions");
      CloseAllPositions(POSITION_TYPE_BUY);
      CloseHedgePositions(POSITION_TYPE_SELL);
      m_max_net_profit_buy = 0.0;
   }
   
   if(macdMain > macdSig && CountPositions(POSITION_TYPE_SELL) > 0)
   {
      Print("Trend Reversal: Closing all Sell positions");
      CloseAllPositions(POSITION_TYPE_SELL);
      CloseHedgePositions(POSITION_TYPE_BUY);
      m_max_net_profit_sell = 0.0;
   }
}

//+------------------------------------------------------------------+
//| Main Trading Logic (Initial Entry & Grid Averaging)              |
//+------------------------------------------------------------------+
void HandleTrading()
{
   //--- Max Spread Filter (Points)
   if(InpMaxSpread > 0)
   {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      long maxSpreadPoints = (long)(InpMaxSpread * m_pips_multiplier);
      if(spread > maxSpreadPoints) 
         return;
   }

   //--- Trend Filter (EMA 200 on Higher TF) - ONLY applies to initial entry (Level 1)
   bool allowInitialBuy  = true;
   bool allowInitialSell = true;
   
   if(InpUseTrendFilter)
   {
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double emaVal     = m_ema_trend[0];
      
      if(currentBid < emaVal) allowInitialBuy  = false;
      if(currentBid > emaVal) allowInitialSell = false;
   }

   //--- Check MACD Signal on closed candles (Shift 1 = current, Shift 2 = previous)
   double macdMainCurr = m_macd_main[0];
   double macdSigCurr  = m_macd_signal[0];
   double macdMainPrev = m_macd_main[1];
   double macdSigPrev  = m_macd_signal[1];

   bool buySignal  = false;
   bool sellSignal = false;

   if(InpRequireMACDCross)
   {
      buySignal  = (macdMainCurr > macdSigCurr && macdMainPrev <= macdSigPrev);
      sellSignal = (macdMainCurr < macdSigCurr && macdMainPrev >= macdSigPrev);
   }
   else
   {
      buySignal  = (macdMainCurr > macdSigCurr);
      sellSignal = (macdMainCurr < macdSigCurr);
   }

   //--- Calculate Base Grid Step Distance in price
   double baseStep;
   if(InpUseDynamicGrid)
   {
      double atr         = m_atr_buffer[0];
      double dynamicStep = atr * InpATRMultiplier;
      double minStep     = InpMinGridStepPips * _Point * m_pips_multiplier;
      baseStep           = MathMax(dynamicStep, minStep);
   }
   else
   {
      baseStep = InpGridStepPips * _Point * m_pips_multiplier;
   }

   datetime currentBarTime = iTime(_Symbol, _Period, 0);

   //================================================================
   // BUY LOGIC
   //================================================================
   int buyCount = CountPositions(POSITION_TYPE_BUY);

   if(buyCount == 0)
   {
      // Initial Entry (Level 1): Requires MACD Signal, EMA Filter, and New Bar Guard
      if(buySignal && allowInitialBuy && currentBarTime != m_last_buy_bar)
      {
         if(OpenPosition(POSITION_TYPE_BUY, NormalizeLot(InpInitialLot)))
         {
            m_last_buy_bar = currentBarTime;
         }
      }
   }
   else if(buyCount < InpMaxGridLevels)
   {
      // Dynamic Grid Step Expansion
      double stepPrice = baseStep * MathPow(InpGridStepMultiplier, MathMax(0, buyCount - 1));
      double lowestBuyPrice = GetLowestPositionPrice(POSITION_TYPE_BUY);
      double currentAsk     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(lowestBuyPrice > 0.0 && currentAsk <= (lowestBuyPrice - stepPrice))
      {
         double nextLot = CalculateNextLot(POSITION_TYPE_BUY, buyCount);
         OpenPosition(POSITION_TYPE_BUY, nextLot);
      }
   }

   //================================================================
   // SELL LOGIC
   //================================================================
   int sellCount = CountPositions(POSITION_TYPE_SELL);

   if(sellCount == 0)
   {
      // Initial Entry (Level 1): Requires MACD Signal, EMA Filter, and New Bar Guard
      if(sellSignal && allowInitialSell && currentBarTime != m_last_sell_bar)
      {
         if(OpenPosition(POSITION_TYPE_SELL, NormalizeLot(InpInitialLot)))
         {
            m_last_sell_bar = currentBarTime;
         }
      }
   }
   else if(sellCount < InpMaxGridLevels)
   {
      // Dynamic Grid Step Expansion
      double stepPrice = baseStep * MathPow(InpGridStepMultiplier, MathMax(0, sellCount - 1));
      double highestSellPrice = GetHighestPositionPrice(POSITION_TYPE_SELL);
      double currentBid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(highestSellPrice > 0.0 && currentBid >= (highestSellPrice + stepPrice))
      {
         double nextLot = CalculateNextLot(POSITION_TYPE_SELL, sellCount);
         OpenPosition(POSITION_TYPE_SELL, nextLot);
      }
   }
}

//+------------------------------------------------------------------+
//| Count Open Standard Positions of Type                            |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count Open Hedge Positions of Type                               |
//+------------------------------------------------------------------+
int CountHedgePositions(ENUM_POSITION_TYPE type)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == m_hedge_magic)
         {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate Total Basket Profit of Standard Grid                   |
//+------------------------------------------------------------------+
double CalculateBasketProfit(ENUM_POSITION_TYPE type)
{
   double totalProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT) 
                         + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Calculate Total Profit of Hedge Positions                        |
//+------------------------------------------------------------------+
double CalculateHedgeProfit(ENUM_POSITION_TYPE type)
{
   double totalProfit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == m_hedge_magic)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT) 
                         + PositionGetDouble(POSITION_SWAP);
         }
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Get Total Open Volume of Standard Basket                         |
//+------------------------------------------------------------------+
double GetBasketTotalVolume(ENUM_POSITION_TYPE type)
{
   double totalVol = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            totalVol += PositionGetDouble(POSITION_VOLUME);
         }
      }
   }
   return totalVol;
}

//+------------------------------------------------------------------+
//| Calculate Volume-Weighted Average Open Price of Basket           |
//+------------------------------------------------------------------+
double GetBasketAveragePrice(ENUM_POSITION_TYPE type)
{
   double totalWeightedPrice = 0.0;
   double totalVolume        = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            double vol   = PositionGetDouble(POSITION_VOLUME);
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            totalWeightedPrice += (price * vol);
            totalVolume        += vol;
         }
      }
   }

   return (totalVolume > 0.0) ? (totalWeightedPrice / totalVolume) : 0.0;
}

//+------------------------------------------------------------------+
//| Close All Standard Positions of Type (With Retry)                |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE type)
{
   int attempts = 0;
   while(CountPositions(type) > 0 && attempts < 5)
   {
      attempts++;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_TYPE) == type &&
               PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
               m_trade.PositionClose(ticket);
            }
         }
      }
      if(CountPositions(type) > 0)
         Sleep(100);
   }
}

//+------------------------------------------------------------------+
//| Close All Hedge Positions of Type (With Retry)                   |
//+------------------------------------------------------------------+
void CloseHedgePositions(ENUM_POSITION_TYPE type)
{
   int attempts = 0;
   while(CountHedgePositions(type) > 0 && attempts < 5)
   {
      attempts++;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket))
         {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_TYPE) == type &&
               PositionGetInteger(POSITION_MAGIC) == m_hedge_magic)
            {
               m_trade.PositionClose(ticket);
            }
         }
      }
      if(CountHedgePositions(type) > 0)
         Sleep(100);
   }
}

//+------------------------------------------------------------------+
//| Get Lowest Open Price Among Positions                            |
//+------------------------------------------------------------------+
double GetLowestPositionPrice(ENUM_POSITION_TYPE type)
{
   double minPrice = DBL_MAX;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(price < minPrice)
               minPrice = price;
         }
      }
   }
   return (minPrice == DBL_MAX) ? 0.0 : minPrice;
}

//+------------------------------------------------------------------+
//| Get Highest Open Price Among Positions                           |
//+------------------------------------------------------------------+
double GetHighestPositionPrice(ENUM_POSITION_TYPE type)
{
   double maxPrice = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            double price = PositionGetDouble(POSITION_PRICE_OPEN);
            if(price > maxPrice)
               maxPrice = price;
         }
      }
   }
   return maxPrice;
}

//+------------------------------------------------------------------+
//| Get Last Opened Position Lot Size (Using millisecond timestamp)  |
//+------------------------------------------------------------------+
double GetLastPositionLot(ENUM_POSITION_TYPE type)
{
   double lot = 0.0;
   ulong lastTimeMsc = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ulong posTimeMsc = (ulong)PositionGetInteger(POSITION_TIME_MSC);
            if(posTimeMsc >= lastTimeMsc)
            {
               lastTimeMsc = posTimeMsc;
               lot = PositionGetDouble(POSITION_VOLUME);
            }
         }
      }
   }
   return lot;
}

//+------------------------------------------------------------------+
//| Open Standard Grid Position                                      |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_POSITION_TYPE type, double lots)
{
   lots = NormalizeLot(lots);
   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   m_trade.SetExpertMagicNumber(InpMagicNumber);

   if(type == POSITION_TYPE_BUY)
   {
      if(!m_trade.Buy(lots, _Symbol, price, 0, 0, "MACD Grid Buy"))
      {
         PrintFormat("Buy error: %s (Code: %u)", m_trade.ResultRetcodeDescription(), m_trade.ResultRetcode());
         return false;
      }
   }
   else
   {
      if(!m_trade.Sell(lots, _Symbol, price, 0, 0, "MACD Grid Sell"))
      {
         PrintFormat("Sell error: %s (Code: %u)", m_trade.ResultRetcodeDescription(), m_trade.ResultRetcode());
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Open Smart Hedge Follow Position                                 |
//+------------------------------------------------------------------+
bool OpenHedgePosition(ENUM_POSITION_TYPE type, double lots)
{
   lots = NormalizeLot(lots);
   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);

   m_trade.SetExpertMagicNumber(m_hedge_magic);

   bool success = false;
   if(type == POSITION_TYPE_BUY)
   {
      success = m_trade.Buy(lots, _Symbol, price, 0, 0, "MACD Hedge Buy");
   }
   else
   {
      success = m_trade.Sell(lots, _Symbol, price, 0, 0, "MACD Hedge Sell");
   }

   if(!success)
   {
      PrintFormat("Hedge order error: %s (Code: %u)", m_trade.ResultRetcodeDescription(), m_trade.ResultRetcode());
   }

   // Restore standard magic number
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   return success;
}
