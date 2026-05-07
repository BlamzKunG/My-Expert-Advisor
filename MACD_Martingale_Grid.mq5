//+------------------------------------------------------------------+
//|                                     MACD_Martingale_Grid.mq5      |
//|                                  Copyright 2026, BlamzKunG        |
//|                                             https://github.com/   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BlamzKunG"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.01"
#property strict

//--- Include
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- Input Parameters
input group "MACD Settings"
input int      InpFastEMA = 12;      // Fast EMA Period
input int      InpSlowEMA = 26;      // Slow EMA Period
input int      InpSignalSMA = 9;     // Signal SMA Period

input group "Grid Settings"
input double   InpInitialLot = 0.01; // Initial Lot Size
input int      InpGridStepPips = 100;// Grid Step in Pips
input double   InpLotMultiplier = 1.5;// Lot Multiplier
input int      InpMaxGridLevels = 10;// Max Grid Levels

input group "Risk Management"
input double   InpBasketTPUSD = 10.0;// Basket Take Profit (USD)
input double   InpEquityStopPercent = 20.0; // Equity Stop Percent
input int      InpMaxSpread = 30;    // Max Spread in Pips (0 to disable)

input group "Advanced Settings"
input int      InpMagicNumber = 123456; // Magic Number
input int      InpTrailingStop = 50;   // Trailing Stop in Pips (0 to disable)

//--- Global Variables
CTrade         m_trade;              // Trading class
CPositionInfo  m_position;           // Position info class
int            m_handle_macd;        // MACD handle
double         m_macd_main[];        // MACD main buffer
double         m_macd_signal[];      // MACD signal buffer
int            m_pips_multiplier;    // Multiplier for 3/5 digits

enum ENUM_TREND_STATE
{
   TREND_NONE,
   TREND_UP,
   TREND_DOWN
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Detect pips multiplier
   m_pips_multiplier = (_Digits == 3 || _Digits == 5) ? 10 : 1;

   //--- Initialize MACD handle
   m_handle_macd = iMACD(_Symbol, _Period, InpFastEMA, InpSlowEMA, InpSignalSMA, PRICE_CLOSE);
   if(m_handle_macd == INVALID_HANDLE)
   {
      Print("Failed to create MACD handle");
      return(INIT_FAILED);
   }
   
   //--- Set arrays as series
   ArraySetAsSeries(m_macd_main, true);
   ArraySetAsSeries(m_macd_signal, true);
   
   //--- Set trade magic number
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(m_handle_macd);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Equity Protector
   if(CheckEquityProtection())
      return;

   // 2. Update MACD Values
   if(!UpdateMACD())
      return;

   ENUM_TREND_STATE currentTrend = GetMACDState();

   // 3. Basket Take Profit
   HandleBasketTP();

   // 4. Trend Reversal Cut (Hard Cut)
   HandleTrendReversal(currentTrend);

   // 5. Initial Entry & Grid Expansion
   HandleTrading(currentTrend);

   // 6. Trailing Stop
   if(InpTrailingStop > 0)
      HandleTrailingStop();
}

//+------------------------------------------------------------------+
//| Check Equity Protection                                          |
//+------------------------------------------------------------------+
bool CheckEquityProtection()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0) return false;
   
   double drawdown = (balance - equity) / balance * 100.0;

   if(drawdown >= InpEquityStopPercent)
   {
      Print("Equity Protection Triggered! Drawdown: ", DoubleToString(drawdown, 2), "%");
      CloseAllPositions(POSITION_TYPE_BUY);
      CloseAllPositions(POSITION_TYPE_SELL);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Update MACD Values                                               |
//+------------------------------------------------------------------+
bool UpdateMACD()
{
   if(CopyBuffer(m_handle_macd, MAIN_LINE, 0, 2, m_macd_main) < 2 ||
      CopyBuffer(m_handle_macd, SIGNAL_LINE, 0, 2, m_macd_signal) < 2)
   {
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Get Current MACD Trend State                                     |
//+------------------------------------------------------------------+
ENUM_TREND_STATE GetMACDState()
{
   double main = m_macd_main[0];
   double signal = m_macd_signal[0];

   if(main > 0 && main > signal)
      return TREND_UP;
   if(main < 0 && main < signal)
      return TREND_DOWN;

   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Handle Basket Take Profit                                        |
//+------------------------------------------------------------------+
void HandleBasketTP()
{
   if(CalculateBasketProfit(POSITION_TYPE_BUY) >= InpBasketTPUSD)
   {
      Print("Buy Basket TP Reached");
      CloseAllPositions(POSITION_TYPE_BUY);
   }

   if(CalculateBasketProfit(POSITION_TYPE_SELL) >= InpBasketTPUSD)
   {
      Print("Sell Basket TP Reached");
      CloseAllPositions(POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Handle Trend Reversal Cut                                        |
//+------------------------------------------------------------------+
void HandleTrendReversal(ENUM_TREND_STATE trend)
{
   if(trend == TREND_DOWN && CountPositions(POSITION_TYPE_BUY) > 0)
   {
      Print("Trend Reversal: Closing all Buy positions");
      CloseAllPositions(POSITION_TYPE_BUY);
   }
   
   if(trend == TREND_UP && CountPositions(POSITION_TYPE_SELL) > 0)
   {
      Print("Trend Reversal: Closing all Sell positions");
      CloseAllPositions(POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Main Trading Logic (Entry & Grid)                                |
//+------------------------------------------------------------------+
void HandleTrading(ENUM_TREND_STATE trend)
{
   //--- Max Spread Filter
   if(InpMaxSpread > 0)
   {
      double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpread) return;
   }

   //--- BUY LOGIC
   int buyCount = CountPositions(POSITION_TYPE_BUY);
   if(trend == TREND_UP)
   {
      if(buyCount == 0)
      {
         OpenPosition(POSITION_TYPE_BUY, InpInitialLot);
      }
      else if(buyCount < InpMaxGridLevels)
      {
         double lastPrice = GetLastPositionPrice(POSITION_TYPE_BUY);
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double step = InpGridStepPips * _Point * m_pips_multiplier;

         if(currentPrice <= lastPrice - step)
         {
            double nextLot = GetLastPositionLot(POSITION_TYPE_BUY) * InpLotMultiplier;
            OpenPosition(POSITION_TYPE_BUY, nextLot);
         }
      }
   }

   //--- SELL LOGIC
   int sellCount = CountPositions(POSITION_TYPE_SELL);
   if(trend == TREND_DOWN)
   {
      if(sellCount == 0)
      {
         OpenPosition(POSITION_TYPE_SELL, InpInitialLot);
      }
      else if(sellCount < InpMaxGridLevels)
      {
         double lastPrice = GetLastPositionPrice(POSITION_TYPE_SELL);
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double step = InpGridStepPips * _Point * m_pips_multiplier;

         if(currentPrice >= lastPrice + step)
         {
            double nextLot = GetLastPositionLot(POSITION_TYPE_SELL) * InpLotMultiplier;
            OpenPosition(POSITION_TYPE_SELL, nextLot);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Handle Trailing Stop for All Positions                           |
//+------------------------------------------------------------------+
void HandleTrailingStop()
{
   double trailingStopVal = InpTrailingStop * _Point * m_pips_multiplier;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double currentSL = PositionGetDouble(POSITION_SL);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

            if(type == POSITION_TYPE_BUY)
            {
               double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               if(bid - openPrice > trailingStopVal)
               {
                  double newSL = bid - trailingStopVal;
                  if(newSL > currentSL || currentSL == 0)
                  {
                     m_trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                  }
               }
            }
            else if(type == POSITION_TYPE_SELL)
            {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
               if(openPrice - ask > trailingStopVal)
               {
                  double newSL = ask + trailingStopVal;
                  if(newSL < currentSL || currentSL == 0)
                  {
                     m_trade.PositionModify(ticket, NormalizeDouble(newSL, _Digits), PositionGetDouble(POSITION_TP));
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count Open Positions of Type                                     |
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
//| Calculate Total Profit for Position Type                         |
//+------------------------------------------------------------------+
double CalculateBasketProfit(ENUM_POSITION_TYPE type)
{
   double totalProfit = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            totalProfit += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP) + PositionGetDouble(POSITION_COMMISSION);
         }
      }
   }
   return totalProfit;
}

//+------------------------------------------------------------------+
//| Close All Positions of Type                                      |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE type)
{
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
}

//+------------------------------------------------------------------+
//| Get Last Opened Position Price                                   |
//+------------------------------------------------------------------+
double GetLastPositionPrice(ENUM_POSITION_TYPE type)
{
   double price = 0;
   datetime lastTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(posTime > lastTime)
            {
               lastTime = posTime;
               price = PositionGetDouble(POSITION_PRICE_OPEN);
            }
         }
      }
   }
   return price;
}

//+------------------------------------------------------------------+
//| Get Last Opened Position Lot Size                                |
//+------------------------------------------------------------------+
double GetLastPositionLot(ENUM_POSITION_TYPE type)
{
   double lot = 0;
   datetime lastTime = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
            PositionGetInteger(POSITION_TYPE) == type &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
            if(posTime > lastTime)
            {
               lastTime = posTime;
               lot = PositionGetDouble(POSITION_VOLUME);
            }
         }
      }
   }
   return lot;
}

//+------------------------------------------------------------------+
//| Open New Position                                                |
//+------------------------------------------------------------------+
bool OpenPosition(ENUM_POSITION_TYPE type, double lots)
{
   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   //--- Normalize lots
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   if(type == POSITION_TYPE_BUY)
   {
      if(!m_trade.Buy(lots, _Symbol, price, 0, 0, "MACD Grid Buy"))
      {
         Print("Buy error: ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }
   else
   {
      if(!m_trade.Sell(lots, _Symbol, price, 0, 0, "MACD Grid Sell"))
      {
         Print("Sell error: ", m_trade.ResultRetcodeDescription());
         return false;
      }
   }
   return true;
}
