//+------------------------------------------------------------------+
//|                                   Quantum_Queen_Supertrend_EA.mq5 |
//|                             Copyright 2026, My-Expert-Advisor    |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, My-Expert-Advisor"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.10"
#property description "Quantum Queen X Multi-Strategy Engine integrated with Supertrend Trend Filter"
#property description "Features Visual / Candle-Close Take Profit, Dynamic Break-Even, Trailing Stop & Drawdown Protection"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_LOT_MODE
  {
   LOT_MODE_FIXED=0,             // Fixed Lot Size
   LOT_MODE_FIXED_PER_BALANCE=1, // Fixed per Balance Unit
   LOT_MODE_AUTO_RISK=2          // Automatic Risk-Based
  };

enum ENUM_QQ_PRESET
  {
   PRESET_ICVT_HIGH=0,      // IC/VT Markets (RAW) - High Risk (9 Strategies)
   PRESET_ICVT_MEDIUM=1,    // IC/VT Markets (RAW) - Medium Risk (8 Strategies)
   PRESET_ICVT_LOW=2,       // IC/VT Markets (RAW) - Low Risk (7 Strategies)
   PRESET_ROBO_ECN=3,       // RoboForex - ECN
   PRESET_FUSION_ZERO=4,    // Fusion Markets - Zero
   PRESET_ALL_STRATEGIES=5, // All 12 Strategies Active
   PRESET_CUSTOM=6          // Custom Strategy Selection
  };

enum ENUM_DIR_MODE
  {
   DIR_PER_STRATEGY=0,      // Original Strategy Bias (S1-4,7-10 Buy / S5,6,11,12 Sell)
   DIR_FOLLOW_SUPERTREND=1, // Dynamic (Strictly Follows Supertrend Direction)
   DIR_BUY_ONLY=2,          // Buy Only
   DIR_SELL_ONLY=3          // Sell Only
  };

enum ENUM_DD_MODE
  {
   DD_OFF=0,                // Drawdown Protection Off
   DD_PERCENT_CLOSE=1,      // [Percent] Close all positions & continue
   DD_PERCENT_STOP_EA=2,    // [Percent] Close all positions & remove EA
   DD_MONEY_CLOSE=3,        // [Money ($)] Close all positions & continue
   DD_MONEY_STOP_EA=4       // [Money ($)] Close all positions & remove EA
  };

//--- Input Parameters
input group ">>>> 1. Supertrend Trend Filter"
input bool              InpUseSupertrend     = true;               // Enable Supertrend Filter
input int               InpST_AtrPeriod      = 10;                 // Supertrend ATR Period
input double            InpST_Multiplier     = 3.0;                // Supertrend Multiplier
input ENUM_TIMEFRAMES   InpST_Timeframe      = PERIOD_CURRENT;     // Supertrend Timeframe
input bool              InpCloseOnSTFlip     = false;              // Close positions on Supertrend flip

input group ">>>> 2. Preset & Strategy Engine"
input ENUM_QQ_PRESET    InpPreset            = PRESET_ICVT_HIGH;   // Strategy Preset
input ENUM_DIR_MODE     InpDirectionMode     = DIR_PER_STRATEGY;   // Trading Direction Mode
input int               InpMinBarsCooldown   = 5;                  // Min Bars Cooldown Between Signals
input ulong             InpMagicNumber       = 778899;             // Magic Number
input int               InpMaxSpread         = 50;                 // Max Allowed Spread (Points)
input int               InpSlippage          = 30;                 // Max Slippage (Points)
input string            InpTradeComment      = "QQ_ST_";           // Order Comment Prefix

input group ">>>> 3. Money Management"
input ENUM_LOT_MODE     InpLotMode           = LOT_MODE_FIXED;     // Lot Sizing Mode
input double            InpFixedLot          = 0.01;               // Fixed Lot Size
input double            InpLotPerBalanceUnit = 1000.0;             // Balance per 0.01 lot (for Fixed per Balance)
input double            InpRiskPercent       = 1.0;                // Risk % per Trade (for Auto Risk)
input int               InpMaxOpenPositions  = 10;                 // Max Total Open Positions

input group ">>>> 4. Quantum Profit & Risk Management (Visual TP / SL / Trail / BE)"
input bool              InpUseVirtualTP      = true;               // Use Visual / Candle-Close Take Profit (QQ Style)
input ENUM_TIMEFRAMES   InpVirtualTP_TF      = PERIOD_CURRENT;     // Candle-Close Evaluation Timeframe
input bool              InpDrawVisualLines   = true;               // Draw Visual TP Lines on Chart
input int               InpTakeProfit        = 500;                // Take Profit Distance (Points, 0=Disabled)
input int               InpStopLoss          = 300;                // Stop Loss (Points, 0=Disabled)
input int               InpBreakEvenStart    = 150;                // Break-Even Activation (Points profit, 0=Off)
input int               InpBreakEvenOffset   = 10;                 // Break-Even Lock Profit (Points above entry)
input int               InpTrailingStart     = 200;                // Trailing Stop Activation (Points profit, 0=Off)
input int               InpTrailingStep      = 100;                // Trailing Stop Distance (Points)

input group ">>>> 5. Account Drawdown Protection"
input ENUM_DD_MODE      InpDDMode            = DD_OFF;             // Drawdown Protection Mode
input double            InpDDThreshold       = 10.0;               // Drawdown Threshold (% or $)

input group ">>>> 6. Custom Strategy Toggles (If Preset = Custom)"
input bool              InpS01 = true;   // S01: M6(18) + M15(16) [BUY]
input bool              InpS02 = true;   // S02: M15(14) + M20(20) [BUY]
input bool              InpS03 = true;   // S03: M15(26) + M15(24) [BUY]
input bool              InpS04 = true;   // S04: M15(20) + M20(22) [BUY]
input bool              InpS05 = true;   // S05: M1(18) + M15(18) [SELL]
input bool              InpS06 = true;   // S06: M10(30) + M30(28) [SELL]
input bool              InpS07 = false;  // S07: M1(20) + M20(16) [BUY]
input bool              InpS08 = true;   // S08: M1(12) + H1(20) [BUY]
input bool              InpS09 = true;   // S09: M12(18) + M15(12) [BUY]
input bool              InpS10 = true;   // S10: M10(20) + M15(10) [BUY]
input bool              InpS11 = false;  // S11: M10(30) + M30(28) [SELL]
input bool              InpS12 = true;   // S12: M12(10) + M15(20) [SELL]

//--- Global Objects & Variables
#define STRATEGY_COUNT 12
CTrade         g_trade;
CPositionInfo  g_pos;
CAccountInfo   g_acc;
CSymbolInfo    g_sym;

int            g_handle_atr = INVALID_HANDLE;
int            g_demarker_a[STRATEGY_COUNT];
int            g_demarker_b[STRATEGY_COUNT];
datetime       g_last_signal_time = 0;
datetime       g_last_tp_bar_time = 0;
datetime       g_last_bar_time[STRATEGY_COUNT];
int            g_current_st_trend = 0; // 1 = Bullish, -1 = Bearish
double         g_st_line = 0.0;

//--- DeMarker Strategy Metadata Arrays
const double   g_upper_a[STRATEGY_COUNT] = {0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.9, 0.5, 0.9, 0.7, 0.7, 0.7};
const double   g_lower_a[STRATEGY_COUNT] = {0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.1};
const double   g_upper_b[STRATEGY_COUNT] = {0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.9, 0.9, 0.9, 0.7, 0.7};
const double   g_lower_b[STRATEGY_COUNT] = {0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3};

//+------------------------------------------------------------------+
//| Strategy Active Evaluator                                        |
//+------------------------------------------------------------------+
bool IsStrategyEnabled(const int slot)
  {
   if(InpPreset == PRESET_CUSTOM)
     {
      switch(slot)
        {
         case 0:  return InpS01;
         case 1:  return InpS02;
         case 2:  return InpS03;
         case 3:  return InpS04;
         case 4:  return InpS05;
         case 5:  return InpS06;
         case 6:  return InpS07;
         case 7:  return InpS08;
         case 8:  return InpS09;
         case 9:  return InpS10;
         case 10: return InpS11;
         case 11: return InpS12;
        }
     }
   else if(InpPreset == PRESET_ICVT_HIGH)
      return (slot==0 || slot==1 || slot==2 || slot==4 || slot==5 || slot==7 || slot==8 || slot==9 || slot==11);
   else if(InpPreset == PRESET_ICVT_MEDIUM)
      return (slot==0 || slot==1 || slot==2 || slot==4 || slot==5 || slot==7 || slot==8 || slot==11);
   else if(InpPreset == PRESET_ICVT_LOW)
      return (slot==0 || slot==1 || slot==2 || slot==4 || slot==7 || slot==8 || slot==11);
   else if(InpPreset == PRESET_ROBO_ECN)
      return (slot==0 || slot==1 || slot==2 || slot==4 || slot==5 || slot==7 || slot==8 || slot==9 || slot==11);
   else if(InpPreset == PRESET_FUSION_ZERO)
      return (slot==0 || slot==2 || slot==3 || slot==4 || slot==7 || slot==8 || slot==11);
   else if(InpPreset == PRESET_ALL_STRATEGIES)
      return true;

   return false;
  }

//+------------------------------------------------------------------+
//| Direction Bias per Strategy                                      |
//+------------------------------------------------------------------+
int StrategyDirectionBias(const int slot)
  {
   if(InpDirectionMode == DIR_BUY_ONLY)
      return 1;
   if(InpDirectionMode == DIR_SELL_ONLY)
      return -1;
   if(InpDirectionMode == DIR_FOLLOW_SUPERTREND)
      return g_current_st_trend;

   // Default Per-Strategy Bias:
   if(slot == 4 || slot == 5 || slot == 10 || slot == 11)
      return -1; // SELL
   return 1;     // BUY
  }

//+------------------------------------------------------------------+
//| Helper: Normalize double volume                                  |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
  {
   double min_lot = g_sym.LotsMin();
   double max_lot = g_sym.LotsMax();
   double step    = g_sym.LotsStep();
   if(step <= 0.0) step = 0.01;

   lot = MathMax(min_lot, MathMin(max_lot, lot));
   return MathFloor(lot / step) * step;
  }

//+------------------------------------------------------------------+
//| Calculate Trade Volume                                           |
//+------------------------------------------------------------------+
double CalculateOrderVolume()
  {
   if(InpLotMode == LOT_MODE_FIXED)
      return NormalizeLot(InpFixedLot);

   if(InpLotMode == LOT_MODE_FIXED_PER_BALANCE)
     {
      double balance = g_acc.Balance();
      double unit    = MathMax(100.0, InpLotPerBalanceUnit);
      double lots    = (balance / unit) * 0.01;
      return NormalizeLot(lots);
     }

   if(InpLotMode == LOT_MODE_AUTO_RISK)
     {
      double balance     = g_acc.Balance();
      double risk_amount = balance * (InpRiskPercent / 100.0);
      double sl_points   = (InpStopLoss > 0) ? InpStopLoss : 300;
      double tick_value  = g_sym.TickValue();
      double tick_size   = g_sym.TickSize();
      double point       = g_sym.Point();

      if(sl_points > 0 && tick_size > 0 && point > 0)
        {
         double loss_per_lot = (sl_points * point / tick_size) * tick_value;
         if(loss_per_lot > 0)
            return NormalizeLot(risk_amount / loss_per_lot);
        }
     }

   return NormalizeLot(InpFixedLot);
  }

//+------------------------------------------------------------------+
//| Initialize Indicator Handles                                     |
//+------------------------------------------------------------------+
bool InitHandles()
  {
   // 1. Supertrend ATR Handle
   g_handle_atr = iATR(_Symbol, InpST_Timeframe, InpST_AtrPeriod);
   if(g_handle_atr == INVALID_HANDLE)
     {
      Print("Error creating Supertrend ATR handle!");
      return false;
     }

   // 2. Quantum Queen 12 DeMarker Dual Handles
   g_demarker_a[0]  = iDeMarker(_Symbol, PERIOD_M6,  18);
   g_demarker_b[0]  = iDeMarker(_Symbol, PERIOD_M15, 16);
   g_demarker_a[1]  = iDeMarker(_Symbol, PERIOD_M15, 14);
   g_demarker_b[1]  = iDeMarker(_Symbol, PERIOD_M20, 20);
   g_demarker_a[2]  = iDeMarker(_Symbol, PERIOD_M15, 26);
   g_demarker_b[2]  = iDeMarker(_Symbol, PERIOD_M15, 24);
   g_demarker_a[3]  = iDeMarker(_Symbol, PERIOD_M15, 20);
   g_demarker_b[3]  = iDeMarker(_Symbol, PERIOD_M20, 22);
   g_demarker_a[4]  = iDeMarker(_Symbol, PERIOD_M1,  18);
   g_demarker_b[4]  = iDeMarker(_Symbol, PERIOD_M15, 18);
   g_demarker_a[5]  = iDeMarker(_Symbol, PERIOD_M10, 30);
   g_demarker_b[5]  = iDeMarker(_Symbol, PERIOD_M30, 28);
   g_demarker_a[6]  = iDeMarker(_Symbol, PERIOD_M1,  20);
   g_demarker_b[6]  = iDeMarker(_Symbol, PERIOD_M20, 16);
   g_demarker_a[7]  = iDeMarker(_Symbol, PERIOD_M1,  12);
   g_demarker_b[7]  = iDeMarker(_Symbol, PERIOD_H1,  20);
   g_demarker_a[8]  = iDeMarker(_Symbol, PERIOD_M12, 18);
   g_demarker_b[8]  = iDeMarker(_Symbol, PERIOD_M15, 12);
   g_demarker_a[9]  = iDeMarker(_Symbol, PERIOD_M10, 20);
   g_demarker_b[9]  = iDeMarker(_Symbol, PERIOD_M15, 10);
   g_demarker_a[10] = iDeMarker(_Symbol, PERIOD_M10, 30);
   g_demarker_b[10] = iDeMarker(_Symbol, PERIOD_M30, 28);
   g_demarker_a[11] = iDeMarker(_Symbol, PERIOD_M12, 10);
   g_demarker_b[11] = iDeMarker(_Symbol, PERIOD_M15, 20);

   for(int i = 0; i < STRATEGY_COUNT; i++)
     {
      if(g_demarker_a[i] == INVALID_HANDLE || g_demarker_b[i] == INVALID_HANDLE)
        {
         PrintFormat("Error creating DeMarker handle for Strategy %d!", i + 1);
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Update Supertrend Trend Direction                                |
//+------------------------------------------------------------------+
void UpdateSupertrend()
  {
   if(!InpUseSupertrend)
     {
      g_current_st_trend = 1;
      return;
     }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpST_Timeframe, 0, 50, rates) < 50)
      return;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_handle_atr, 0, 0, 50, atr) < 50)
      return;

   double upper_band = 0.0, lower_band = 0.0;
   int trend = 1;
   double prev_st = 0.0;

   // Calculate trailing Supertrend over historical bars
   for(int i = 40; i >= 0; i--)
     {
      double median = (rates[i].high + rates[i].low) / 2.0;
      double basic_upper = median + InpST_Multiplier * atr[i];
      double basic_lower = median - InpST_Multiplier * atr[i];

      if(i == 40)
        {
         upper_band = basic_upper;
         lower_band = basic_lower;
         trend = (rates[i].close > upper_band) ? 1 : -1;
         prev_st = (trend == 1) ? lower_band : upper_band;
         continue;
        }

      if(basic_lower > lower_band || rates[i + 1].close < lower_band)
         lower_band = basic_lower;

      if(basic_upper < upper_band || rates[i + 1].close > upper_band)
         upper_band = basic_upper;

      if(trend == 1 && rates[i].close < lower_band)
         trend = -1;
      else if(trend == -1 && rates[i].close > upper_band)
         trend = 1;

      prev_st = (trend == 1) ? lower_band : upper_band;
     }

   // Supertrend flip event
   if(InpCloseOnSTFlip && g_current_st_trend != 0 && g_current_st_trend != trend)
     {
      PrintFormat("Supertrend flipped from %s to %s -> Closing opposing positions",
                  (g_current_st_trend == 1 ? "BULL" : "BEAR"), (trend == 1 ? "BULL" : "BEAR"));
      ClosePositionsByDirection(g_current_st_trend);
     }

   g_current_st_trend = trend;
   g_st_line = prev_st;
  }

//+------------------------------------------------------------------+
//| Evaluate DeMarker Direction for Strategy Slot                    |
//+------------------------------------------------------------------+
int EvaluateDeMarkerSignal(const int slot)
  {
   if(slot < 0 || slot >= STRATEGY_COUNT)
      return 0;

   double a[1], b[1];
   if(CopyBuffer(g_demarker_a[slot], 0, 0, 1, a) != 1)
      return 0;
   if(CopyBuffer(g_demarker_b[slot], 0, 0, 1, b) != 1)
      return 0;

   int da = (a[0] > g_upper_a[slot]) ? 1 : ((a[0] < g_lower_a[slot]) ? -1 : 0);
   int db = (b[0] > g_upper_b[slot]) ? 1 : ((b[0] < g_lower_b[slot]) ? -1 : 0);

   if(da != 0 && da == db)
      return da;

   return 0;
  }

//+------------------------------------------------------------------+
//| Quantum Visual / Candle-Close Take Profit Evaluation             |
//| (Closes ONLY when completed candle CLOSES beyond Virtual TP)     |
//+------------------------------------------------------------------+
void CheckQuantumVisualTakeProfit()
  {
   if(!InpUseVirtualTP || InpTakeProfit <= 0)
      return;

   // Evaluate on completed candle close
   datetime current_tp_bar = iTime(_Symbol, InpVirtualTP_TF, 0);
   if(current_tp_bar == g_last_tp_bar_time)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpVirtualTP_TF, 1, 1, rates) < 1)
      return;

   double last_close = rates[0].close;
   double point      = g_sym.Point();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() != InpMagicNumber || g_pos.Symbol() != _Symbol) continue;

      ulong  ticket     = g_pos.Ticket();
      long   type       = g_pos.PositionType();
      double open_price = g_pos.PriceOpen();

      if(type == POSITION_TYPE_BUY)
        {
         double virtual_tp = open_price + InpTakeProfit * point;
         // BUY TP Trigger: Completed bar closed AT OR ABOVE Virtual TP level
         if(last_close >= virtual_tp)
           {
            PrintFormat("🎯 [Visual TP Triggered] BUY #%I64u Closed on Candle Close! Bar Close: %.2f >= TP Target: %.2f (Profit: +%.2f pts)",
                        ticket, last_close, virtual_tp, (last_close - open_price) / point);
            g_trade.PositionClose(ticket);
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double virtual_tp = open_price - InpTakeProfit * point;
         // SELL TP Trigger: Completed bar closed AT OR BELOW Virtual TP level
         if(last_close <= virtual_tp)
           {
            PrintFormat("🎯 [Visual TP Triggered] SELL #%I64u Closed on Candle Close! Bar Close: %.2f <= TP Target: %.2f (Profit: +%.2f pts)",
                        ticket, last_close, virtual_tp, (open_price - last_close) / point);
            g_trade.PositionClose(ticket);
           }
        }
     }

   g_last_tp_bar_time = current_tp_bar;
  }

//+------------------------------------------------------------------+
//| Multi-Stage Position Management (Break-Even & Trailing Stop)     |
//+------------------------------------------------------------------+
void ApplyQuantumPositionManagement()
  {
   if(InpBreakEvenStart <= 0 && InpTrailingStart <= 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i))
         continue;

      if(g_pos.Magic() != InpMagicNumber || g_pos.Symbol() != _Symbol)
         continue;

      ulong  ticket     = g_pos.Ticket();
      long   type       = g_pos.PositionType();
      double open_price = g_pos.PriceOpen();
      double current_sl = g_pos.StopLoss();
      double current_tp = g_pos.TakeProfit();
      double point      = g_sym.Point();

      if(point <= 0.0) continue;

      double new_sl = current_sl;

      if(type == POSITION_TYPE_BUY)
        {
         double profit_pts = (g_sym.Bid() - open_price) / point;

         // 1. Stage 1: Break-Even Lock
         if(InpBreakEvenStart > 0 && profit_pts >= InpBreakEvenStart)
           {
            double be_level = NormalizeDouble(open_price + InpBreakEvenOffset * point, g_sym.Digits());
            if(new_sl < be_level || new_sl == 0.0)
               new_sl = be_level;
           }

         // 2. Stage 2: Dynamic Trailing Stop
         if(InpTrailingStart > 0 && InpTrailingStep > 0 && profit_pts >= InpTrailingStart)
           {
            double trail_level = NormalizeDouble(g_sym.Bid() - InpTrailingStep * point, g_sym.Digits());
            if(trail_level > new_sl)
               new_sl = trail_level;
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profit_pts = (open_price - g_sym.Ask()) / point;

         // 1. Stage 1: Break-Even Lock
         if(InpBreakEvenStart > 0 && profit_pts >= InpBreakEvenStart)
           {
            double be_level = NormalizeDouble(open_price - InpBreakEvenOffset * point, g_sym.Digits());
            if(current_sl == 0.0 || new_sl > be_level)
               new_sl = be_level;
           }

         // 2. Stage 2: Dynamic Trailing Stop
         if(InpTrailingStart > 0 && InpTrailingStep > 0 && profit_pts >= InpTrailingStart)
           {
            double trail_level = NormalizeDouble(g_sym.Ask() + InpTrailingStep * point, g_sym.Digits());
            if(current_sl == 0.0 || trail_level < new_sl)
               new_sl = trail_level;
           }
        }

      // Modify SL if improved
      if(new_sl != current_sl && new_sl > 0.0)
        {
         g_trade.SetExpertMagicNumber(InpMagicNumber);
         if(!g_trade.PositionModify(ticket, new_sl, current_tp))
            PrintFormat("Quantum BE/Trail Modify Failed! Ticket #%I64u Error: %d", ticket, GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage Visual TP Lines on Chart                                  |
//+------------------------------------------------------------------+
void UpdateVisualLines()
  {
   if(!InpDrawVisualLines || !InpUseVirtualTP)
      return;

   // Clean up orphan lines
   for(int i = ObjectsTotal(0, 0, OBJ_HLINE) - 1; i >= 0; i--)
     {
      string obj_name = ObjectName(0, i, 0, OBJ_HLINE);
      if(StringFind(obj_name, "QQ_VTP_") == 0)
        {
         ulong ticket = (ulong)StringToInteger(StringSubstr(obj_name, 7));
         if(!PositionSelectByTicket(ticket))
            ObjectDelete(0, obj_name);
        }
     }

   // Render active Visual TP lines
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() != InpMagicNumber || g_pos.Symbol() != _Symbol) continue;

      ulong ticket = g_pos.Ticket();
      string obj_name = "QQ_VTP_" + (string)ticket;
      double open_price = g_pos.PriceOpen();
      double vtp = 0.0;

      if(g_pos.PositionType() == POSITION_TYPE_BUY)
         vtp = open_price + InpTakeProfit * g_sym.Point();
      else
         vtp = open_price - InpTakeProfit * g_sym.Point();

      if(ObjectFind(0, obj_name) < 0)
        {
         ObjectCreate(0, obj_name, OBJ_HLINE, 0, 0, vtp);
         ObjectSetInteger(0, obj_name, OBJPROP_COLOR, (g_pos.PositionType() == POSITION_TYPE_BUY ? clrMediumSeaGreen : clrCrimson));
         ObjectSetInteger(0, obj_name, OBJPROP_STYLE, STYLE_DASHDOT);
         ObjectSetInteger(0, obj_name, OBJPROP_WIDTH, 1);
         ObjectSetString(0, obj_name, OBJPROP_TEXT, StringFormat("Visual TP #%I64u (Close Beyond)", ticket));
        }
     }
  }

//+------------------------------------------------------------------+
//| Drawdown Protection Manager                                      |
//+------------------------------------------------------------------+
void CheckDrawdownControl()
  {
   if(InpDDMode == DD_OFF || InpDDThreshold <= 0.0)
      return;

   double floating_profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
         floating_profit += (g_pos.Profit() + g_pos.Swap());
     }

   if(floating_profit >= 0.0)
      return;

   double dd_val = 0.0;
   if(InpDDMode == DD_PERCENT_CLOSE || InpDDMode == DD_PERCENT_STOP_EA)
     {
      double balance = g_acc.Balance();
      if(balance > 0.0)
         dd_val = (-floating_profit / balance) * 100.0;
     }
   else
      dd_val = -floating_profit;

   if(dd_val >= InpDDThreshold)
     {
      PrintFormat("Drawdown limit breached! Value: %.2f (Threshold: %.2f). Closing positions...", dd_val, InpDDThreshold);
      CloseAllPositions();
      if(InpDDMode == DD_PERCENT_STOP_EA || InpDDMode == DD_MONEY_STOP_EA)
        {
         Print("EA removed due to Drawdown Protection trigger.");
         ExpertRemove();
        }
     }
  }

//+------------------------------------------------------------------+
//| Close Positions Helpers                                          |
//+------------------------------------------------------------------+
void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
         g_trade.PositionClose(g_pos.Ticket());
     }
  }

void ClosePositionsByDirection(const int dir)
  {
   ENUM_POSITION_TYPE target_type = (dir > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol && g_pos.PositionType() == target_type)
         g_trade.PositionClose(g_pos.Ticket());
     }
  }

int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Chart Information Panel                                          |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   string text = StringFormat("--- QUANTUM QUEEN X + SUPERTREND EA ---\n"
                              "Supertrend: %s (%.2f)\n"
                              "Open Positions: %d / %d\n"
                              "Account Equity: $%.2f | Balance: $%.2f\n"
                              "Preset: %s\n"
                              "Direction Mode: %s\n"
                              "Visual TP Mode: %s (Candle-Close Beyond TP)\n"
                              "Trailing Stop: %s (%d pts) | BE: %s (%d pts)",
                              (g_current_st_trend == 1 ? "BULLISH (UP)" : "BEARISH (DOWN)"), g_st_line,
                              CountOpenPositions(), InpMaxOpenPositions,
                              g_acc.Equity(), g_acc.Balance(),
                              EnumToString(InpPreset),
                              EnumToString(InpDirectionMode),
                              (InpUseVirtualTP ? "ENABLED" : "HARD BROKER TP"),
                              (InpTrailingStart > 0 ? "ON" : "OFF"), InpTrailingStep,
                              (InpBreakEvenStart > 0 ? "ON" : "OFF"), InpBreakEvenStart);

   Comment(text);
  }

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_sym.Name(_Symbol))
     {
      Print("Failed to initialize symbol info!");
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!InitHandles())
      return INIT_FAILED;

   ArrayInitialize(g_last_bar_time, 0);
   g_last_tp_bar_time = 0;
   Print("Quantum Queen X + Supertrend EA successfully initialized.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handle_atr != INVALID_HANDLE)
      IndicatorRelease(g_handle_atr);

   for(int i = 0; i < STRATEGY_COUNT; i++)
     {
      if(g_demarker_a[i] != INVALID_HANDLE)
         IndicatorRelease(g_demarker_a[i]);
      if(g_demarker_b[i] != INVALID_HANDLE)
         IndicatorRelease(g_demarker_b[i]);
     }

   ObjectsDeleteAll(0, "QQ_VTP_");
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_sym.RefreshRates();

   // 1. Check Drawdown Protection
   CheckDrawdownControl();

   // 2. Update Supertrend Direction
   UpdateSupertrend();

   // 3. Evaluate Quantum Visual / Candle-Close Take Profit
   CheckQuantumVisualTakeProfit();

   // 4. Apply Multi-Stage Position Management (Break-Even & Trailing Stop)
   ApplyQuantumPositionManagement();

   // 5. Update Visual TP Lines on Chart
   UpdateVisualLines();

   // 6. Update Dashboard
   DrawDashboard();

   // 7. Check Spread
   double spread = (g_sym.Ask() - g_sym.Bid()) / g_sym.Point();
   if(spread > InpMaxSpread)
      return;

   // 8. Check Max Positions
   if(CountOpenPositions() >= InpMaxOpenPositions)
      return;

   // 9. Check Cooldown between entries
   datetime current_bar = iTime(_Symbol, _Period, 0);
   if(InpMinBarsCooldown > 0 && g_last_signal_time > 0)
     {
      int elapsed_bars = (int)((current_bar - g_last_signal_time) / PeriodSeconds(_Period));
      if(elapsed_bars < InpMinBarsCooldown)
         return;
     }

   // 10. Process 12 Quantum Queen Strategies
   for(int slot = 0; slot < STRATEGY_COUNT; slot++)
     {
      if(!IsStrategyEnabled(slot))
         continue;

      int sig = EvaluateDeMarkerSignal(slot);
      if(sig == 0)
         continue;

      int expected_dir = StrategyDirectionBias(slot);
      if(sig != expected_dir)
         continue;

      // Supertrend Trend Filter Verification
      if(InpUseSupertrend)
        {
         if(sig == 1 && g_current_st_trend != 1)
            continue; // Block Buy if Supertrend is not Bullish
         if(sig == -1 && g_current_st_trend != -1)
            continue; // Block Sell if Supertrend is not Bearish
        }

      // Calculate Order Parameters
      double volume = CalculateOrderVolume();
      if(volume <= 0.0)
         continue;

      double sl_price = 0.0;
      double tp_price = 0.0;
      double point    = g_sym.Point();
      int    digits   = g_sym.Digits();

      // If Visual TP is enabled, do NOT set hard broker TP
      if(!InpUseVirtualTP && InpTakeProfit > 0)
        {
         if(sig == 1) tp_price = NormalizeDouble(g_sym.Ask() + InpTakeProfit * point, digits);
         if(sig == -1) tp_price = NormalizeDouble(g_sym.Bid() - InpTakeProfit * point, digits);
        }

      string comment = StringFormat("%sS%d", InpTradeComment, slot + 1);

      if(sig == 1) // BUY Entry
        {
         double ask = g_sym.Ask();
         if(InpStopLoss > 0) sl_price = NormalizeDouble(ask - InpStopLoss * point, digits);

         if(g_trade.Buy(volume, _Symbol, ask, sl_price, tp_price, comment))
           {
            PrintFormat("Quantum Queen BUY executed! [Strategy %d] Lot: %.2f (Visual TP Target: %.2f) SL: %.2f",
                        slot + 1, volume, ask + InpTakeProfit * point, sl_price);
            g_last_signal_time = current_bar;
            break;
           }
        }
      else if(sig == -1) // SELL Entry
        {
         double bid = g_sym.Bid();
         if(InpStopLoss > 0) sl_price = NormalizeDouble(bid + InpStopLoss * point, digits);

         if(g_trade.Sell(volume, _Symbol, bid, sl_price, tp_price, comment))
           {
            PrintFormat("Quantum Queen SELL executed! [Strategy %d] Lot: %.2f (Visual TP Target: %.2f) SL: %.2f",
                        slot + 1, volume, bid - InpTakeProfit * point, sl_price);
            g_last_signal_time = current_bar;
            break;
           }
        }
     }
  }
//+------------------------------------------------------------------+
