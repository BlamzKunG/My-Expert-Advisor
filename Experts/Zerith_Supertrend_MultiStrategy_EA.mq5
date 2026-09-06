//+------------------------------------------------------------------+
//|                             Zerith_Supertrend_MultiStrategy_EA.mq5 |
//|        Zerith Series - Authentic Quantum Queen X 4.3 Architecture |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / Quantum Queen X 4.3 Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "4.60"
#property description "Zerith Supertrend Multi-Strategy EA (Quantum Queen X 4.3 Authentic Overhaul)"
#property description "12 DeMarker Multi-Timeframe Matrix - 100% Honest Backtest (Zero Day Skip, Zero Hard TP)"
#property strict 

#include <Trade\Trade.mqh>

//--- Enums
enum QQ_LOT_MODE
  {
   QQ_LOT_AUTOMATIC=0,         // Automatic (Risk-based)
   QQ_LOT_FIXED=1,             // Fixed Lots
   QQ_LOT_FIXED_PER_BALANCE=2  // Fixed per Balance Step
  };

enum QQ_RISK_LEVEL
  {
   QQ_RISK_VERY_LOW=0,     // Very Low
   QQ_RISK_LOW=1,          // Low
   QQ_RISK_LOW_MEDIUM=2,   // Low-Medium
   QQ_RISK_MEDIUM=3,       // Medium
   QQ_RISK_MEDIUM_HIGH=4,  // Medium-High
   QQ_RISK_HIGH=5,         // High
   QQ_RISK_VERY_HIGH=6     // Very High
  };

enum QQ_PRESET
  {
   QQ_PRESET_ICVT_HIGH=0,      // IC Markets/VT Markets (RAW) - High Risk
   QQ_PRESET_ICVT_MEDIUM=1,    // IC Markets/VT Markets (RAW) - Medium Risk
   QQ_PRESET_ICVT_LOW=2,       // IC Markets/VT Markets (RAW) - Low Risk
   QQ_PRESET_ROBO_ECN=3,       // RoboForex - ECN
   QQ_PRESET_FUSION_ZERO=4,    // Fusion Markets - Zero
   QQ_PRESET_ALL_STRATEGIES=5, // All 12 Strategies
   QQ_PRESET_CUSTOM=6          // Custom Strategy Selection
  };

enum QQ_DD_MODE
  {
   QQ_DD_OFF=0,               // Off
   QQ_DD_PERCENT_CONTINUE=1,  // [Percent] Close all & Continue
   QQ_DD_PERCENT_REMOVE=2,    // [Percent] Close all & Remove EA
   QQ_DD_PERCENT_ALERT=3,     // [Percent] Terminal Alert Only
   QQ_DD_MONEY_CONTINUE=4,    // [Money] Close all & Continue
   QQ_DD_MONEY_REMOVE=5,      // [Money] Close all & Remove EA
   QQ_DD_MONEY_ALERT=6        // [Money] Terminal Alert Only
  };

enum QQ_DIRECTION_MODE
  {
   QQ_DIRECTION_BUY_ONLY=0,     // Buy Only
   QQ_DIRECTION_SELL_ONLY=1,    // Sell Only
   QQ_DIRECTION_PER_STRATEGY=2, // Both Directions (Per Strategy Bias)
   QQ_DIRECTION_DYNAMIC_ST=3    // Dynamic (Follows Supertrend Direction)
  };

enum QQ_BINARY_OPTION
  {
   QQ_OPTION_ON=0,   // On
   QQ_OPTION_OFF=1   // Off
  };

//--- Input Parameters
input group ">>>> 1. Money Management & Lot Sizing"
input QQ_LOT_MODE       InpLotsCalc             = QQ_LOT_AUTOMATIC;     // Lot Sizing Mode
input QQ_RISK_LEVEL     InpAutoLotsValue        = QQ_RISK_MEDIUM;        // Automatic Lot Risk Level
input double            InpLotsFixed            = 0.01;                  // Fixed Lot Size
input double            InpLotsFixedBalance     = 500.0;                 // Balance Step for Fixed Lot ($)
input int               InpOrdersMaxTotal       = 100;                   // Max Total Positions on Account

input group ">>>> 2. Authentic Exit System (No Hard TP to Broker)"
input bool              InpUseHardTP            = false;                 // Send Hard TP to Broker (Default False: 100% Virtual)
input int               InpVirtualTP            = 0;                     // Virtual TP Points (0 = Off, Exit by Trailing/Signal)
input int               InpStopLoss             = 300;                   // Stop Loss Points (300 in authentic 4.3, 0 = Off)
input int               InpBreakEvenStart       = 150;                   // Break-Even Activation (Points Profit, 0 = Off)
input int               InpBreakEvenOffset      = 10;                    // Break-Even Lock Offset (Points above Entry)
input int               InpTrailingStart        = 200;                   // Trailing Stop Activation (Points Profit, 0 = Off)
input int               InpTrailingStep         = 100;                   // Trailing Stop Distance (Points)
input bool              InpCloseOnReversalSig   = true;                  // Close Position on Opposite DeMarker Reversal

input group ">>>> 3. Presets & 12 DeMarker Strategy Matrix"
input QQ_PRESET         InpSets                 = QQ_PRESET_ICVT_HIGH;   // Preset Selection
input QQ_DIRECTION_MODE InpTradingDirectionType = QQ_DIRECTION_PER_STRATEGY; // Trading Direction Mode
input QQ_BINARY_OPTION  InpS01Strategy          = QQ_OPTION_ON;          // Strategy 1 (M6/M15 Buy)
input QQ_BINARY_OPTION  InpS02Strategy          = QQ_OPTION_ON;          // Strategy 2 (M15/M20 Buy)
input QQ_BINARY_OPTION  InpS03Strategy          = QQ_OPTION_ON;          // Strategy 3 (M15/M15 Buy)
input QQ_BINARY_OPTION  InpS04Strategy          = QQ_OPTION_ON;          // Strategy 4 (M15/M20 Buy)
input QQ_BINARY_OPTION  InpS05Strategy          = QQ_OPTION_ON;          // Strategy 5 (M1/M15 Sell)
input QQ_BINARY_OPTION  InpS06Strategy          = QQ_OPTION_ON;          // Strategy 6 (M10/M30 Sell)
input QQ_BINARY_OPTION  InpS07Strategy          = QQ_OPTION_OFF;         // Strategy 7 (M1/M20 Buy)
input QQ_BINARY_OPTION  InpS08Strategy          = QQ_OPTION_ON;          // Strategy 8 (M1/H1 Buy)
input QQ_BINARY_OPTION  InpS09Strategy          = QQ_OPTION_ON;          // Strategy 9 (M12/M15 Buy)
input QQ_BINARY_OPTION  InpS10Strategy          = QQ_OPTION_ON;          // Strategy 10 (M10/M15 Buy)
input QQ_BINARY_OPTION  InpS11Strategy          = QQ_OPTION_OFF;         // Strategy 11 (M10/M30 Sell)
input QQ_BINARY_OPTION  InpS12Strategy          = QQ_OPTION_ON;          // Strategy 12 (M12/M15 Sell)

input group ">>>> 4. Trading Hours & Session Filter (Zero Day Skip)"
input bool              InpUseHourFilter        = true;                  // Use Strategy Specific Trading Hour Windows
input bool              InpTradeOnMonday        = true;                  // Trade on Monday
input bool              InpTradeOnTuesday       = true;                  // Trade on Tuesday
input bool              InpTradeOnWednesday     = true;                  // Trade on Wednesday
input bool              InpTradeOnThursday      = true;                  // Trade on Thursday
input bool              InpTradeOnFriday        = true;                  // Trade on Friday

input group ">>>> 5. Supertrend Trend Filter (Optional)"
input bool              InpUseSupertrend        = false;                 // Enable Supertrend Trend Filter (Default False: Pure QQ)
input int               InpST_AtrPeriod         = 10;                    // Supertrend ATR Period
input double            InpST_Multiplier        = 3.0;                   // Supertrend Multiplier
input ENUM_TIMEFRAMES   InpST_Timeframe         = PERIOD_CURRENT;        // Supertrend Timeframe
input bool              InpCloseOnSTFlip        = false;                 // Close Positions on Supertrend Direction Flip

input group ">>>> 6. Capital Protection & Safety Controls"
input QQ_DD_MODE        InpDDMode               = QQ_DD_OFF;             // Drawdown Control Mode
input double            InpDDValue              = 0.0;                   // Drawdown Threshold (% or Currency)
input long              InpMagicNumber          = 1234;                  // Base Magic Number
input int               InpSpread               = 100;                   // Max Allowed Spread (Points)
input int               InpSlippage             = 100;                   // Max Slippage (Points)
input string            InpTradeCommentRaw      = "Zerith_QQ_";          // Trade Comment Prefix
input QQ_BINARY_OPTION  InpPause                = QQ_OPTION_OFF;         // Start Paused

input group ">>>> 7. HUD Dashboard"
input QQ_BINARY_OPTION  InpPanel                = QQ_OPTION_ON;          // Show Dashboard
input string            InpFont                 = "Trebuchet MS";        // Font Family
input int               InpFontSize             = 8;                     // Font Size

//--- Constants & Global Objects
#define QQ_STRATEGY_COUNT 12
static const string QQ_NAME     = "Zerith Quantum Queen (Overhaul 4.3)";
static const string QQ_PANEL_PREFIX = "ZQQ_";

CTrade   g_trade;
bool     g_paused               = false;
bool     g_remove_after_risk    = false;
bool     g_drawdown_triggered   = false;
datetime g_last_panel_update    = 0;
long     g_last_bar_time[QQ_STRATEGY_COUNT];
int      g_demarker_a[QQ_STRATEGY_COUNT];
int      g_demarker_b[QQ_STRATEGY_COUNT];
int      g_handle_atr           = INVALID_HANDLE;
int      g_current_st_trend     = 0; // 1 = Bullish, -1 = Bearish
double   g_st_line              = 0.0;

//+------------------------------------------------------------------+
//| Strategy Tag Identifier                                          |
//+------------------------------------------------------------------+
string StrategyTag(const int slot)
  {
   static string tags[12]=
     {
      "[T1/S01]","[T1/S02]","[T2/S03]","[T2/S04]",
      "[T3/S05]","[T3/S06]","[T4/S07]","[T4/S08]",
      "[T5/S09]","[T5/S10]","[T6/S11]","[T6/S12]"
     };
   if(slot < 0 || slot >= QQ_STRATEGY_COUNT) return "[S?]";
   return tags[slot];
  }

//+------------------------------------------------------------------+
//| Strategy Enablement Verification                                 |
//+------------------------------------------------------------------+
bool StrategyEnabled(const int slot)
  {
   if(InpSets == QQ_PRESET_ALL_STRATEGIES)
      return true;

   if(InpSets == QQ_PRESET_CUSTOM)
     {
      switch(slot)
        {
         case 0:  return (InpS01Strategy == QQ_OPTION_ON);
         case 1:  return (InpS02Strategy == QQ_OPTION_ON);
         case 2:  return (InpS03Strategy == QQ_OPTION_ON);
         case 3:  return (InpS04Strategy == QQ_OPTION_ON);
         case 4:  return (InpS05Strategy == QQ_OPTION_ON);
         case 5:  return (InpS06Strategy == QQ_OPTION_ON);
         case 6:  return (InpS07Strategy == QQ_OPTION_ON);
         case 7:  return (InpS08Strategy == QQ_OPTION_ON);
         case 8:  return (InpS09Strategy == QQ_OPTION_ON);
         case 9:  return (InpS10Strategy == QQ_OPTION_ON);
         case 10: return (InpS11Strategy == QQ_OPTION_ON);
         case 11: return (InpS12Strategy == QQ_OPTION_ON);
        }
     }

   // Preset Matrix matching authentic Quantum Queen 4.3
   if(InpSets == QQ_PRESET_ICVT_HIGH)
      return (slot==0 || slot==1 || slot==2 || slot==4 || slot==5 ||
              slot==7 || slot==8 || slot==9 || slot==11);
              
   if(InpSets == QQ_PRESET_ICVT_MEDIUM)
      return (slot==0 || slot==2 || slot==7 || slot==8 || slot==11);
      
   if(InpSets == QQ_PRESET_ICVT_LOW)
      return (slot==0 || slot==3 || slot==4 || slot==6 || slot==7 ||
              slot==8 || slot==9);
              
   if(InpSets == QQ_PRESET_ROBO_ECN)
      return (slot==0 || slot==2 || slot==3 || slot==4 || slot==5 ||
              slot==7 || slot==8 || slot==9 || slot==11);
              
   if(InpSets == QQ_PRESET_FUSION_ZERO)
      return (slot==0 || slot==2 || slot==3 || slot==4 || slot==7 ||
              slot==8 || slot==11);

   return false;
  }

//+------------------------------------------------------------------+
//| Strategy Direction Bias                                          |
//+------------------------------------------------------------------+
int StrategyDirection(const int slot)
  {
   if(InpTradingDirectionType == QQ_DIRECTION_BUY_ONLY)  return 1;
   if(InpTradingDirectionType == QQ_DIRECTION_SELL_ONLY) return -1;
   if(InpTradingDirectionType == QQ_DIRECTION_DYNAMIC_ST) return g_current_st_trend;

   // Authentic Strategy Bias: S5, S6, S11, S12 are Sell strategies; rest are Buy
   if(slot == 4 || slot == 5 || slot == 10 || slot == 11)
      return -1;
      
   return 1;
  }

//+------------------------------------------------------------------+
//| Strategy Magic Number Mapping                                    |
//+------------------------------------------------------------------+
long StrategyMagic(const int slot)
  {
   return InpMagicNumber + slot;
  }

//+------------------------------------------------------------------+
//| Trade Comment Generator                                          |
//+------------------------------------------------------------------+
string SafeComment(const int slot)
  {
   string base = StringSubstr(InpTradeCommentRaw, 0, 18);
   return base + StrategyTag(slot);
  }

//+------------------------------------------------------------------+
//| Normalization Functions                                          |
//+------------------------------------------------------------------+
double NormalizeVolume(const double requested)
  {
   double min_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = min_vol;
   if(step <= 0.0) step = 0.01;

   double volume = step * MathFloor(requested / step);
   if(volume < min_vol) volume = min_vol;
   if(volume > max_vol) volume = max_vol;
   return volume;
  }

double NormalizeRecoveredPrice(const double price)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
  }

//+------------------------------------------------------------------+
//| Lot Size Calculation (Authentic 4.3 Matrix)                      |
//+------------------------------------------------------------------+
double CalculateVolume()
  {
   if(InpLotsCalc == QQ_LOT_FIXED)
      return NormalizeVolume(InpLotsFixed);
      
   if(InpLotsCalc == QQ_LOT_FIXED_PER_BALANCE)
     {
      double unit = MathMax(1.0, InpLotsFixedBalance);
      return NormalizeVolume((AccountInfoDouble(ACCOUNT_BALANCE) / unit) * InpLotsFixed);
     }

   static double divisor_high[7]  = {2000.0, 1200.0, 800.0, 600.0, 500.0, 400.0, 300.0};
   static double divisor_other[7] = {2000.0, 1500.0, 1000.0, 800.0, 600.0, 550.0, 400.0};
   
   int level = (int)InpAutoLotsValue;
   if(level < 0 || level > 6) return 0.01;

   double divisor = divisor_high[level];
   if(InpSets >= QQ_PRESET_ICVT_LOW)
      divisor = divisor_other[level];
   if(InpSets == QQ_PRESET_FUSION_ZERO && level == 6)
      divisor = 300.0;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   return NormalizeVolume((bal / divisor) * 0.01);
  }

//+------------------------------------------------------------------+
//| Position Tracking Helpers                                        |
//+------------------------------------------------------------------+
bool IsOurPosition(const ulong ticket, const int slot=-1)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;

   long magic = PositionGetInteger(POSITION_MAGIC);
   if(slot >= 0)
      return (magic == StrategyMagic(slot));
      
   return (magic >= InpMagicNumber && magic < InpMagicNumber + QQ_STRATEGY_COUNT);
  }

int StrategyPositionCount(const int slot)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket, slot))
         count++;
     }
   return count;
  }

int TotalOpenPositionsCount()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
         count++;
     }
   return count;
  }

double TotalStrategyProfit()
  {
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
        {
         profit += PositionGetDouble(POSITION_PROFIT);
         profit += PositionGetDouble(POSITION_SWAP);
        }
     }
   return profit;
  }

//+------------------------------------------------------------------+
//| Close Strategy Positions                                         |
//+------------------------------------------------------------------+
bool CloseStrategy(const int slot, const string reason)
  {
   bool all_closed = true;
   g_trade.SetExpertMagicNumber(StrategyMagic(slot));

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket, slot))
         continue;

      if(!g_trade.PositionClose(ticket))
        {
         all_closed = false;
         PrintFormat("Failed to close ticket %I64u (%s) Err: %d", ticket, reason, GetLastError());
        }
     }
   return all_closed;
  }

bool CloseAllStrategies(const string reason)
  {
   bool result = true;
   for(int slot = 0; slot < QQ_STRATEGY_COUNT; slot++)
     {
      if(StrategyPositionCount(slot) > 0 && !CloseStrategy(slot, reason))
         result = false;
     }
   return result;
  }

//+------------------------------------------------------------------+
//| Honest Schedule Filter: Zero Day Skip (No NFP/Year-End Avoidance)|
//+------------------------------------------------------------------+
bool ScheduleAllowsTrading()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // Standard Weekday Filter (No artificial day/holiday skipping)
   if(now.day_of_week == 1 && !InpTradeOnMonday)    return false;
   if(now.day_of_week == 2 && !InpTradeOnTuesday)   return false;
   if(now.day_of_week == 3 && !InpTradeOnWednesday) return false;
   if(now.day_of_week == 4 && !InpTradeOnThursday)  return false;
   if(now.day_of_week == 5 && !InpTradeOnFriday)    return false;
   if(now.day_of_week == 0 || now.day_of_week == 6) return false; // Weekend closed

   return true;
  }

//+------------------------------------------------------------------+
//| Strategy Primary Timeframe                                       |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES PrimaryTimeframe(const int slot)
  {
   static ENUM_TIMEFRAMES values[12]=
     {
      PERIOD_M6,  PERIOD_M15, PERIOD_M15, PERIOD_M15,
      PERIOD_M5,  PERIOD_M10, PERIOD_M5,  PERIOD_M5,
      PERIOD_M12, PERIOD_M10, PERIOD_M10, PERIOD_M12
     };
   if(slot < 0 || slot >= QQ_STRATEGY_COUNT)
      return PERIOD_CURRENT;
   return values[slot];
  }

//+------------------------------------------------------------------+
//| Strategy Operating Hours                                         |
//+------------------------------------------------------------------+
bool StrategyHourAllowed(const int slot, const int hour)
  {
   if(!InpUseHourFilter) return true;

   switch(slot)
     {
      case 0:  return (hour == 22 || hour == 23);
      case 1:  return (hour == 3);
      case 2:  return (hour == 22);
      case 3:  return (hour == 19);
      case 4:  return (hour == 0);
      case 5:  return (hour == 23);
      case 6:  return (hour >= 8 && hour <= 10);
      case 7:  return (hour >= 6 && hour <= 11);
      case 8:  return (hour >= 10 && hour <= 13);
      case 9:  return (hour == 22);
      case 10: return (hour >= 4 && hour <= 8);
      case 11: return (hour == 8 || hour == 9);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Check Eligible New Bar                                           |
//+------------------------------------------------------------------+
bool IsNewEligibleBar(const int slot)
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   if(!StrategyHourAllowed(slot, now.hour))
      return false;

   datetime bar = iTime(_Symbol, PrimaryTimeframe(slot), 0);
   if(bar <= 0 || bar == g_last_bar_time[slot])
      return false;

   g_last_bar_time[slot] = bar;
   return true;
  }

//+------------------------------------------------------------------+
//| DeMarker Signal Evaluator                                        |
//+------------------------------------------------------------------+
int DeMarkerDirection(const double value, const double upper, const double lower)
  {
   if(value > upper) return 1;
   if(value < lower) return -1;
   return 0;
  }

int RecoveredSignalProvider(const int slot)
  {
   if(slot < 0 || slot >= QQ_STRATEGY_COUNT) return 0;
   if(g_demarker_a[slot] == INVALID_HANDLE || g_demarker_b[slot] == INVALID_HANDLE)
      return 0;

   double a[2], b[2];
   if(CopyBuffer(g_demarker_a[slot], 0, 0, 2, a) != 2) return 0;
   if(CopyBuffer(g_demarker_b[slot], 0, 0, 2, b) != 2) return 0;

   static double upper_a[12] = {0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.9, 0.5, 0.9, 0.7, 0.7, 0.7};
   static double lower_a[12] = {0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.1};
   static double upper_b[12] = {0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.9, 0.9, 0.9, 0.7, 0.7};
   static double lower_b[12] = {0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3};

   int da = DeMarkerDirection(a[0], upper_a[slot], lower_a[slot]);
   int db = DeMarkerDirection(b[0], upper_b[slot], lower_b[slot]);

   return (da != 0 && da == db ? da : 0);
  }

//+------------------------------------------------------------------+
//| Supertrend Engine (Optional Filter)                              |
//+------------------------------------------------------------------+
void UpdateSupertrend()
  {
   if(!InpUseSupertrend)
     {
      g_current_st_trend = 1;
      return;
     }

   if(g_handle_atr == INVALID_HANDLE)
      g_handle_atr = iATR(_Symbol, InpST_Timeframe, InpST_AtrPeriod);

   double atr_buf[2];
   if(CopyBuffer(g_handle_atr, 0, 1, 2, atr_buf) < 2) return;

   double h = iHigh(_Symbol, InpST_Timeframe, 1);
   double l = iLow(_Symbol, InpST_Timeframe, 1);
   double c = iClose(_Symbol, InpST_Timeframe, 1);
   double hl2 = (h + l) / 2.0;

   static double prev_upper = 0.0, prev_lower = 0.0;
   static int    prev_trend = 1;

   double basic_upper = hl2 + (InpST_Multiplier * atr_buf[1]);
   double basic_lower = hl2 - (InpST_Multiplier * atr_buf[1]);

   double final_upper = (basic_upper < prev_upper || iClose(_Symbol, InpST_Timeframe, 2) > prev_upper) ? basic_upper : prev_upper;
   double final_lower = (basic_lower > prev_lower || iClose(_Symbol, InpST_Timeframe, 2) < prev_lower) ? basic_lower : prev_lower;

   int trend = prev_trend;
   if(trend == 1 && c < final_lower)
      trend = -1;
   else if(trend == -1 && c > final_upper)
      trend = 1;

   if(InpCloseOnSTFlip && trend != prev_trend && prev_trend != 0)
     {
      CloseAllStrategies("Supertrend Trend Flip");
     }

   prev_upper = final_upper;
   prev_lower = final_lower;
   prev_trend = trend;
   g_current_st_trend = trend;
   g_st_line = (trend == 1) ? final_lower : final_upper;
  }

//+------------------------------------------------------------------+
//| Dynamic Position Management: Virtual TP, Trailing, & Break-Even  |
//+------------------------------------------------------------------+
void ManageStrategy(const int slot)
  {
   if(!StrategyEnabled(slot) || StrategyPositionCount(slot) <= 0)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return;

   // Check Reversal Exit
   if(InpCloseOnReversalSig)
     {
      int current_sig = RecoveredSignalProvider(slot);
      if(current_sig != 0)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(!IsOurPosition(ticket, slot)) continue;
            long type = PositionGetInteger(POSITION_TYPE);
            if((type == POSITION_TYPE_BUY && current_sig < 0) ||
               (type == POSITION_TYPE_SELL && current_sig > 0))
              {
               g_trade.SetExpertMagicNumber(StrategyMagic(slot));
               g_trade.PositionClose(ticket);
               PrintFormat("⚡ [Reversal Exit] Closed Strategy %d on opposite DeMarker signal", slot + 1);
              }
           }
        }
     }

   // Dynamic Virtual TP, Break-Even & Trailing Engine (Internal, Zero Hard TP)
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket, slot)) continue;

      long   type       = PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
        {
         double profit_pts = (tick.bid - open_price) / point;

         // 1. Virtual TP Exit (Hidden from Broker)
         if(!InpUseHardTP && InpVirtualTP > 0 && profit_pts >= InpVirtualTP)
           {
            g_trade.SetExpertMagicNumber(StrategyMagic(slot));
            g_trade.PositionClose(ticket);
            PrintFormat("🎯 [Virtual TP Hit] Strategy %d closed at +%.1f pts profit", slot + 1, profit_pts);
            continue;
           }

         // 2. Break-Even
         double new_sl = current_sl;
         if(InpBreakEvenStart > 0 && profit_pts >= InpBreakEvenStart)
           {
            double be_level = NormalizeRecoveredPrice(open_price + InpBreakEvenOffset * point);
            if(new_sl < be_level) new_sl = be_level;
           }

         // 3. Dynamic Trailing Stop
         if(InpTrailingStart > 0 && InpTrailingStep > 0 && profit_pts >= InpTrailingStart)
           {
            double trail_level = NormalizeRecoveredPrice(tick.bid - InpTrailingStep * point);
            if(trail_level > new_sl) new_sl = trail_level;
           }

         if(new_sl != current_sl && new_sl > 0.0)
           {
            g_trade.SetExpertMagicNumber(StrategyMagic(slot));
            g_trade.PositionModify(ticket, new_sl, current_tp);
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profit_pts = (open_price - tick.ask) / point;

         // 1. Virtual TP Exit (Hidden from Broker)
         if(!InpUseHardTP && InpVirtualTP > 0 && profit_pts >= InpVirtualTP)
           {
            g_trade.SetExpertMagicNumber(StrategyMagic(slot));
            g_trade.PositionClose(ticket);
            PrintFormat("🎯 [Virtual TP Hit] Strategy %d closed at +%.1f pts profit", slot + 1, profit_pts);
            continue;
           }

         // 2. Break-Even
         double new_sl = current_sl;
         if(InpBreakEvenStart > 0 && profit_pts >= InpBreakEvenStart)
           {
            double be_level = NormalizeRecoveredPrice(open_price - InpBreakEvenOffset * point);
            if(current_sl <= 0.0 || new_sl > be_level) new_sl = be_level;
           }

         // 3. Dynamic Trailing Stop
         if(InpTrailingStart > 0 && InpTrailingStep > 0 && profit_pts >= InpTrailingStart)
           {
            double trail_level = NormalizeRecoveredPrice(tick.ask + InpTrailingStep * point);
            if(current_sl <= 0.0 || trail_level < new_sl) new_sl = trail_level;
           }

         if(new_sl != current_sl && new_sl > 0.0)
           {
            g_trade.SetExpertMagicNumber(StrategyMagic(slot));
            g_trade.PositionModify(ticket, new_sl, current_tp);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Strategy Trade Dispatcher                                        |
//+------------------------------------------------------------------+
void ProcessStrategy(const int slot)
  {
   if(!StrategyEnabled(slot) || g_paused) return;
   if(!ScheduleAllowsTrading()) return;
   if(!IsNewEligibleBar(slot)) return;

   int signal = RecoveredSignalProvider(slot);
   if(signal == 0) return;

   int expected = StrategyDirection(slot);
   if((signal > 0 && expected < 0) || (signal < 0 && expected > 0))
      return;

   // Supertrend Filter Validation
   if(InpUseSupertrend)
     {
      if(signal == 1 && g_current_st_trend != 1)   return;
      if(signal == -1 && g_current_st_trend != -1) return;
     }

   if(StrategyPositionCount(slot) > 0) return;
   if(TotalOpenPositionsCount() >= InpOrdersMaxTotal) return;

   double volume = CalculateVolume();
   if(volume <= 0.0) return;

   // Spread Check
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0 || ((ask - bid) / point) > (double)InpSpread) return;

   // Margin Check
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double req_margin = 0.0;
   ENUM_ORDER_TYPE otype = (signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcMargin(otype, _Symbol, volume, (signal > 0 ? ask : bid), req_margin) || req_margin > free_margin)
      return;

   g_trade.SetExpertMagicNumber(StrategyMagic(slot));
   g_trade.SetDeviationInPoints((ulong)MathMax(0, InpSlippage));

   // Hard TP / SL Configuration (Default is 0: Pure Virtual/Hidden Execution)
   double sl_price = 0.0;
   double tp_price = 0.0;
   
   if(InpStopLoss > 0)
      sl_price = NormalizeRecoveredPrice(signal > 0 ? (ask - InpStopLoss * point) : (bid + InpStopLoss * point));

   if(InpUseHardTP && InpVirtualTP > 0)
      tp_price = NormalizeRecoveredPrice(signal > 0 ? (ask + InpVirtualTP * point) : (bid - InpVirtualTP * point));

   bool opened = false;
   if(signal > 0)
      opened = g_trade.Buy(volume, _Symbol, ask, sl_price, tp_price, SafeComment(slot));
   else
      opened = g_trade.Sell(volume, _Symbol, bid, sl_price, tp_price, SafeComment(slot));

   if(opened)
     {
      PrintFormat("🚀 [Zerith Quantum Queen] %s %s opened! Lot: %.2f (Slot %d) Virtual Exit: ACTIVE",
                  (signal > 0 ? "BUY" : "SELL"), _Symbol, volume, slot + 1);
     }
  }

//+------------------------------------------------------------------+
//| Drawdown & Emergency Control                                     |
//+------------------------------------------------------------------+
void ApplyDrawdownControl()
  {
   if(InpDDMode == QQ_DD_OFF || InpDDValue <= 0.0)
     {
      g_drawdown_triggered = false;
      return;
     }

   double floating = TotalStrategyProfit();
   if(floating >= 0.0)
     {
      g_drawdown_triggered = false;
      return;
     }

   bool percent_mode = ((int)InpDDMode >= 1 && (int)InpDDMode <= 3);
   double measured = -floating;
   if(percent_mode)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(bal <= 0.0) return;
      measured = (-floating / bal) * 100.0;
     }

   if(measured < InpDDValue)
     {
      g_drawdown_triggered = false;
      return;
     }

   g_drawdown_triggered = true;
   PrintFormat("🚨 [Capital Protection] Drawdown threshold reached: %.2f (Floating: %.2f)", InpDDValue, floating);

   if(InpDDMode == QQ_DD_PERCENT_ALERT || InpDDMode == QQ_DD_MONEY_ALERT)
      return;

   CloseAllStrategies("Drawdown Capital Protection Breach");

   if(InpDDMode == QQ_DD_PERCENT_REMOVE || InpDDMode == QQ_DD_MONEY_REMOVE)
      g_remove_after_risk = true;
  }

//+------------------------------------------------------------------+
//| UI HUD Dashboard                                                 |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   if(InpPanel != QQ_OPTION_ON) return;

   string text = "--- ZERITH QUANTUM QUEEN MT5 (v4.60 OVERHAUL) ---\n";
   text += "Status: " + (g_paused ? "PAUSED" : "RUNNING") + "\n";
   text += "DeMarker Modules: 12 Multi-Timeframe Matrix (Honest Backtest)\n";
   text += "Backtest Cheats: REMOVED (Zero Day Skip, Clean Continuous Data)\n";
   text += "Exit Engine: 100% Virtual / Hidden (No Hard TP sent to Broker)\n";
   text += "Trailing / Break-Even: " + (InpTrailingStart > 0 ? "ACTIVE" : "OFF") + "\n";
   text += "Open Positions: " + IntegerToString(TotalOpenPositionsCount()) + " / " + IntegerToString(InpOrdersMaxTotal) + "\n";
   text += "Floating P/L: $" + DoubleToString(TotalStrategyProfit(), 2) + "\n";
   text += "Account Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   text += "Account Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";

   Comment(text);
  }

//+------------------------------------------------------------------+
//| DeMarker Handle Initializer                                      |
//+------------------------------------------------------------------+
bool CreateSignalHandles()
  {
   for(int i = 0; i < QQ_STRATEGY_COUNT; i++)
     {
      g_demarker_a[i] = INVALID_HANDLE;
      g_demarker_b[i] = INVALID_HANDLE;
     }

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

   for(int i = 0; i < QQ_STRATEGY_COUNT; i++)
     {
      if(g_demarker_a[i] == INVALID_HANDLE || g_demarker_b[i] == INVALID_HANDLE)
         return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayInitialize(g_last_bar_time, 0);
   g_paused = (InpPause == QQ_OPTION_ON);
   g_trade.SetAsyncMode(false);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!CreateSignalHandles())
     {
      PrintFormat("Zerith Quantum Queen: Failed to create DeMarker indicator handles (%d)", GetLastError());
      return INIT_FAILED;
     }

   if(InpUseSupertrend)
      UpdateSupertrend();

   Print("Zerith Quantum Queen EA v4.60 (Overhaul 4.3 Authentic) initialized successfully.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int i = 0; i < QQ_STRATEGY_COUNT; i++)
     {
      if(g_demarker_a[i] != INVALID_HANDLE) IndicatorRelease(g_demarker_a[i]);
      if(g_demarker_b[i] != INVALID_HANDLE) IndicatorRelease(g_demarker_b[i]);
     }

   if(g_handle_atr != INVALID_HANDLE)
      IndicatorRelease(g_handle_atr);

   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ApplyDrawdownControl();

   if(InpUseSupertrend)
      UpdateSupertrend();

   for(int slot = 0; slot < QQ_STRATEGY_COUNT; slot++)
      ProcessStrategy(slot);

   for(int slot = 0; slot < QQ_STRATEGY_COUNT; slot++)
      ManageStrategy(slot);

   DrawDashboard();

   if(g_remove_after_risk)
     {
      g_remove_after_risk = false;
      ExpertRemove();
     }
  }
//+------------------------------------------------------------------+
