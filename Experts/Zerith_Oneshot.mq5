//+------------------------------------------------------------------+
//|                                                Zerith_Oneshot.mq5 |
//|                                  Copyright 2026, Zerith EA Team  |
//|                                         https://zerith-ea.com    |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Zerith EA"
#property link        "https://zerith-ea.com"
#property version     "1.00"
#property description "Zerith OneShot MT5 - Institutional Multi-Strategy DeMarker Momentum EA with First-Instinct Execution"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| System Enumerations                                              |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
  {
   LOT_MODE_AUTOMATIC          = 0, // Automatic (Dynamic Risk Based)
   LOT_MODE_FIXED              = 1, // Fixed Lot Size
   LOT_MODE_FIXED_PER_BALANCE  = 2  // Fixed Lot Per Balance Unit
  };

enum ENUM_RISK_LEVEL
  {
   RISK_LEVEL_VERY_LOW    = 0, // Very Low
   RISK_LEVEL_LOW         = 1, // Low
   RISK_LEVEL_LOW_MEDIUM  = 2, // Low-Medium
   RISK_LEVEL_MEDIUM      = 3, // Medium
   RISK_LEVEL_MEDIUM_HIGH = 4, // Medium-High
   RISK_LEVEL_HIGH        = 5, // High
   RISK_LEVEL_VERY_HIGH   = 6  // Very High
  };

enum ENUM_PRESET_TYPE
  {
   PRESET_ICVT_HIGH    = 0, // IC Markets / VT Markets (RAW) - High Risk
   PRESET_ICVT_MEDIUM  = 1, // IC Markets / VT Markets (RAW) - Medium Risk
   PRESET_ICVT_LOW     = 2, // IC Markets / VT Markets (RAW) - Low Risk
   PRESET_ROBO_ECN     = 3, // RoboForex - ECN
   PRESET_FUSION_ZERO  = 4, // Fusion Markets - Zero
   PRESET_CUSTOM       = 5  // Custom Strategy Selection
  };

enum ENUM_DRAWDOWN_MODE
  {
   DRAWDOWN_OFF                    = 0, // Off
   DRAWDOWN_PERCENT_CLOSE_CONTINUE = 1, // [Percent] Close All & Continue
   DRAWDOWN_PERCENT_CLOSE_REMOVE   = 2, // [Percent] Close All & Remove EA
   DRAWDOWN_PERCENT_ALERT_ONLY     = 3, // [Percent] Terminal Alert Only
   DRAWDOWN_MONEY_CLOSE_CONTINUE   = 4, // [Money] Close All & Continue
   DRAWDOWN_MONEY_CLOSE_REMOVE     = 5, // [Money] Close All & Remove EA
   DRAWDOWN_MONEY_ALERT_ONLY       = 6  // [Money] Terminal Alert Only
  };

enum ENUM_TRADE_DIRECTION
  {
   TRADE_DIRECTION_BUY_ONLY     = 0, // Buy Only
   TRADE_DIRECTION_SELL_ONLY    = 1, // Sell Only
   TRADE_DIRECTION_PER_STRATEGY = 2  // Dynamic Per Strategy (Default)
  };

enum ENUM_HOUR_OF_DAY
  {
   HOUR_00 = 0,  // 00:00
   HOUR_01 = 1,  // 01:00
   HOUR_02 = 2,  // 02:00
   HOUR_03 = 3,  // 03:00
   HOUR_04 = 4,  // 04:00
   HOUR_05 = 5,  // 05:00
   HOUR_06 = 6,  // 06:00
   HOUR_07 = 7,  // 07:00
   HOUR_08 = 8,  // 08:00
   HOUR_09 = 9,  // 09:00
   HOUR_10 = 10, // 10:00
   HOUR_11 = 11, // 11:00
   HOUR_12 = 12, // 12:00
   HOUR_13 = 13, // 13:00
   HOUR_14 = 14, // 14:00
   HOUR_15 = 15, // 15:00
   HOUR_16 = 16, // 16:00
   HOUR_17 = 17, // 17:00
   HOUR_18 = 18, // 18:00
   HOUR_19 = 19, // 19:00
   HOUR_20 = 20, // 20:00
   HOUR_21 = 21, // 21:00
   HOUR_22 = 22, // 22:00
   HOUR_23 = 23  // 23:00
  };

enum ENUM_GRID_SPACING_MODE
  {
   GRID_SPACING_ORIGINAL_FIXED = 0, // 100% Original (Fixed Step Distance)
   GRID_SPACING_EXPANDING_MULT = 1  // Expanding Step (* Distance Multiplier per Level)
  };

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//--- General Information
input string               InpEAName               = "Zerith OneShot MT5 v1.00"; // EA Name
input string               InpEAOverview           = "DeMarker Multi-Strategy Momentum Engine"; // Overview

//--- General & Money Management
input group ">>>> General & Money Management"
input bool                 InpStartPaused          = false;                      // Start EA in Paused Mode
input ENUM_LOT_MODE        InpLotMode              = LOT_MODE_AUTOMATIC;         // Lot Sizing Mode
input ENUM_RISK_LEVEL      InpAutoRiskLevel        = RISK_LEVEL_MEDIUM;          // Auto Lot Risk Level
input double               InpFixedLotSize         = 0.01;                       // Fixed Lot Size
input double               InpFixedLotPerBalance   = 500.0;                      // Balance Step for Fixed Lot ($ per 0.01)
input int                  InpMaxOrdersTotal       = 100;                        // Maximum Total Positions Across Entire Account
input ENUM_DRAWDOWN_MODE   InpDrawdownMode         = DRAWDOWN_OFF;               // Drawdown Protection Mode
input double               InpDrawdownThreshold    = 0.0;                        // Drawdown Threshold (% or Money)
input bool                 InpPushNotifications    = false;                      // MQID Push Notifications
input ulong                InpMagicNumber          = 1234;                       // Magic Number
input int                  InpMaxSpread            = 100;                        // Max Allowed Spread (Points)
input int                  InpMaxSlippage          = 100;                        // Max Allowed Slippage (Points)
input string               InpTradeCommentPrefix   = "ZerithOS";                 // Order Comment Prefix
input ENUM_TRADE_DIRECTION InpTradeDirection       = TRADE_DIRECTION_PER_STRATEGY;// Trade Direction Mode

//--- First-Instinct (One-Shot) Trading Logic
input group ">>>> First-Instinct (One-Shot) Settings"
input bool                 InpOneShotPerSession    = true;                       // One-Shot: 1 Initial Trade Per Session Only (First Instinct)
input bool                 InpFreshCrossOnly       = true;                       // Require Fresh Signal Cross (No Late Entry)

//--- Grid Recovery & Spacing Settings
input group ">>>> Grid Recovery & Spacing Settings"
input bool                   InpEnableGridRecovery   = true;                       // Enable Grid Recovery System
input ENUM_GRID_SPACING_MODE InpGridSpacingMode      = GRID_SPACING_EXPANDING_MULT;// Grid Spacing Mode (Original 100% vs Expanding)
input int                    InpMaxBasketOrders      = 5;                          // Max Orders Allowed per Basket (1 Initial + N Recovery)
input double                 InpGridBaseDistance     = 200.0;                      // Base Grid Step Distance (Points)
input double                 InpGridStepMultiplier   = 1.5;                        // Grid Step Distance Multiplier (for Expanding Mode)
input double                 InpGridLotMultiplier    = 1.2;                        // Recovery Lot Multiplier (1.0 = Fixed Lot, >1.0 = Scaling)
input int                    InpBasketTakeProfit     = 150;                        // Basket Take Profit (Points above Avg Price for 2+ Orders)
input bool                   InpCutLossOnMaxStep     = true;                       // Hard Cut-Loss on (MaxOrders + 1) Step Distance

//--- Presets & Individual Strategies
input group ">>>> Presets & Strategy Toggles"
input ENUM_PRESET_TYPE     InpPreset               = PRESET_ICVT_HIGH;           // Preset Profile
input bool                 InpStrategy01           = true;                       // Strategy 01 (M6/M15 DeMarker)
input bool                 InpStrategy02           = true;                       // Strategy 02 (M15/M20 DeMarker)
input bool                 InpStrategy03           = true;                       // Strategy 03 (M15/M15 DeMarker)
input bool                 InpStrategy04           = true;                       // Strategy 04 (M15/M20 DeMarker)
input bool                 InpStrategy05           = true;                       // Strategy 05 (M1/M15 DeMarker)
input bool                 InpStrategy06           = true;                       // Strategy 06 (M10/M30 DeMarker)
input bool                 InpStrategy07           = false;                      // Strategy 07 (M1/M20 DeMarker)
input bool                 InpStrategy08           = true;                       // Strategy 08 (M1/H1 DeMarker)
input bool                 InpStrategy09           = true;                       // Strategy 09 (M12/M15 DeMarker)
input bool                 InpStrategy10           = true;                       // Strategy 10 (M10/M15 DeMarker)
input bool                 InpStrategy11           = false;                      // Strategy 11 (M10/M30 DeMarker)
input bool                 InpStrategy12           = true;                       // Strategy 12 (M12/M15 DeMarker)

//--- Time & Schedule Filters
input group ">>>> Schedule & Calendar Filters"
input bool                 InpUseNfpFridayFilter   = true;                       // Block Entries on NFP Friday (1st Friday)
input bool                 InpCloseFridayNight     = true;                       // Close Trading on Friday Night
input ENUM_HOUR_OF_DAY     InpFridayNightCloseHour = HOUR_22;                    // Friday Night Close Hour
input bool                 InpUseYearEndPause      = false;                      // Year-End Holiday Pause (Dec 15 - Jan 15)
input bool                 InpTradeMonday          = true;                       // Trade on Monday
input bool                 InpTradeTuesday         = true;                       // Trade on Tuesday
input bool                 InpTradeWednesday       = true;                       // Trade on Wednesday
input bool                 InpTradeThursday        = true;                       // Trade on Thursday
input bool                 InpTradeFriday          = true;                       // Trade on Friday
input bool                 InpTradeSaturday        = true;                       // Trade on Saturday
input bool                 InpTradeSunday          = true;                       // Trade on Sunday

//--- Risk & Position Management
input group ">>>> Risk & Position Management"
input int                  InpStopLoss             = 300;                        // Stop Loss (Points, 0 = Off)
input int                  InpTakeProfit           = 500;                        // Take Profit (Points, 0 = Off)
input int                  InpBreakEvenStart       = 150;                        // Break-Even Activation (Points, 0 = Off)
input int                  InpBreakEvenOffset      = 10;                         // Break-Even Profit Buffer (Points)
input int                  InpTrailingStart        = 200;                        // Trailing Stop Activation (Points, 0 = Off)
input int                  InpTrailingStep         = 100;                        // Trailing Stop Distance (Points)

//--- Dashboard & GUI Display
input group ">>>> Dashboard & Visual Panel"
input bool                 InpShowPanel            = true;                       // Display Chart Dashboard
input string               InpFontName             = "Trebuchet MS";             // Dashboard Font
input int                  InpFontSize             = 8;                          // Font Size
input string               InpPanelComment         = "Zerith OneShot v1.00";     // Custom Panel Note

//+------------------------------------------------------------------+
//| Global Constants & Variables                                     |
//+------------------------------------------------------------------+
#define TOTAL_STRATEGIES 12
#define PANEL_PREFIX     "ZerithOS_"

CTrade   g_trade;
bool     g_is_paused             = false;
bool     g_remove_after_risk     = false;
bool     g_panel_collapsed       = false;
bool     g_drawdown_triggered    = false;
datetime g_last_panel_update     = 0;

// Per-Strategy Execution Tracking
datetime g_last_bar_time[TOTAL_STRATEGIES];
int      g_demarker_a[TOTAL_STRATEGIES];
int      g_demarker_b[TOTAL_STRATEGIES];
bool     g_session_executed[TOTAL_STRATEGIES];
int      g_session_executed_day[TOTAL_STRATEGIES];

//+------------------------------------------------------------------+
//| Strategy Tag Formatter                                           |
//+------------------------------------------------------------------+
string StrategyTag(const int slot)
  {
   static const string tags[TOTAL_STRATEGIES] =
     {
      "[S01/M6-M15]", "[S02/M15-M20]", "[S03/M15-M15]", "[S04/M15-M20]",
      "[S05/M1-M15]", "[S06/M10-M30]", "[S07/M1-M20]",  "[S08/M1-H1]",
      "[S09/M12-M15]","[S10/M10-M15]", "[S11/M10-M30]", "[S12/M12-M15]"
     };
   if(slot < 0 || slot >= TOTAL_STRATEGIES)
      return "[Strategy ?]";
   return tags[slot];
  }

//+------------------------------------------------------------------+
//| Check if Strategy is Enabled in Current Preset                   |
//+------------------------------------------------------------------+
bool StrategyEnabled(const int slot)
  {
   if(InpPreset == PRESET_CUSTOM)
     {
      switch(slot)
        {
         case 0:  return InpStrategy01;
         case 1:  return InpStrategy02;
         case 2:  return InpStrategy03;
         case 3:  return InpStrategy04;
         case 4:  return InpStrategy05;
         case 5:  return InpStrategy06;
         case 6:  return InpStrategy07;
         case 7:  return InpStrategy08;
         case 8:  return InpStrategy09;
         case 9:  return InpStrategy10;
         case 10: return InpStrategy11;
         case 11: return InpStrategy12;
        }
      return false;
     }

   // Presets Matrix
   if(InpPreset == PRESET_ICVT_HIGH)
      return (slot==0 || slot==1 || slot==2 || slot==4 || slot==5 ||
              slot==7 || slot==8 || slot==9 || slot==11);

   if(InpPreset == PRESET_ICVT_MEDIUM)
      return (slot==0 || slot==2 || slot==7 || slot==8 || slot==11);

   if(InpPreset == PRESET_ICVT_LOW)
      return (slot==0 || slot==3 || slot==4 || slot==6 || slot==7 ||
              slot==8 || slot==9);

   if(InpPreset == PRESET_ROBO_ECN)
      return (slot==0 || slot==2 || slot==3 || slot==4 || slot==5 ||
              slot==7 || slot==8 || slot==9 || slot==11);

   if(InpPreset == PRESET_FUSION_ZERO)
      return (slot==0 || slot==2 || slot==3 || slot==4 ||
              slot==7 || slot==8 || slot==11);

   return false;
  }

//+------------------------------------------------------------------+
//| Get Expected Trade Direction for Strategy Slot                   |
//+------------------------------------------------------------------+
int StrategyDirection(const int slot)
  {
   if(InpTradeDirection == TRADE_DIRECTION_BUY_ONLY)
      return 1;
   if(InpTradeDirection == TRADE_DIRECTION_SELL_ONLY)
      return -1;

   // Per-strategy default directions:
   // Strategies 5, 6, 11, 12 (slots 4, 5, 10, 11) trade SELL (-1)
   // Strategies 1, 2, 3, 4, 7, 8, 9, 10 trade BUY (+1)
   if(slot == 4 || slot == 5 || slot == 10 || slot == 11)
      return -1;

   return 1;
  }

//+------------------------------------------------------------------+
//| Get Strategy Magic Number                                        |
//+------------------------------------------------------------------+
ulong StrategyMagic(const int slot)
  {
   return InpMagicNumber;
  }

//+------------------------------------------------------------------+
//| Generate Order Comment with Strategy Tag                         |
//+------------------------------------------------------------------+
string SafeComment(const int slot, const int order_idx = 0)
  {
   string prefix = StringSubstr(InpTradeCommentPrefix, 0, 11);
   if(order_idx == 0)
      return (prefix + StrategyTag(slot));
   return (prefix + StrategyTag(slot) + StringFormat("_R%d", order_idx));
  }

//+------------------------------------------------------------------+
//| Verify Terminal and Account Trading Permissions                  |
//+------------------------------------------------------------------+
bool CheckTradingEnvironmentReady()
  {
   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
     {
      Print("Zerith OneShot: Terminal is disconnected from server.");
      return false;
     }
   if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      Print("Zerith OneShot: Terminal trading is disabled.");
      return false;
     }
   if(!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Print("Zerith OneShot: Automated trading is disabled in terminal.");
      return false;
     }
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      Print("Zerith OneShot: Expert trading is disabled for this account.");
      return false;
     }
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      Print("Zerith OneShot: Account trading permissions not granted.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Normalize Order Lot Volume                                       |
//+------------------------------------------------------------------+
double NormalizeLotVolume(const double requested)
  {
   double minimum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maximum = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = minimum;

   double whole   = (requested < 0.0 ? MathCeil(requested) : MathFloor(requested));
   double scaled  = (requested - whole) * 100.0 + (requested > 0.0 ? 0.5000001 : -0.5000001);
   double rounded_fraction = (scaled < 0.0 ? MathCeil(scaled) : MathFloor(scaled));
   double rounded = whole + rounded_fraction / 100.0;
   if(rounded == 0.0)
      return 0.0;

   double volume = step * (int)(rounded / step);
   if(volume < minimum)
      volume = minimum;
   if(volume > maximum)
      volume = maximum;

   return volume;
  }

//+------------------------------------------------------------------+
//| Normalize Price to Symbol Digits                                 |
//+------------------------------------------------------------------+
double NormalizePrice(const double price)
  {
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits < 0)
      digits = 0;
   if(digits > 11)
      digits = 11;
   double scale = MathPow(10.0, digits);
   if(scale <= 0.0)
      return price;
   return MathFloor(price * scale + 0.5) / scale;
  }

//+------------------------------------------------------------------+
//| Calculate Trade Volume Based on Sizing Mode                      |
//+------------------------------------------------------------------+
double CalculateLotVolume(const int order_level = 0)
  {
   double base_lot = 0.01;
   if(InpLotMode == LOT_MODE_FIXED)
     {
      base_lot = InpFixedLotSize;
     }
   else if(InpLotMode == LOT_MODE_FIXED_PER_BALANCE)
     {
      double unit = MathMax(1.0, InpFixedLotPerBalance);
      base_lot = AccountInfoDouble(ACCOUNT_BALANCE) / unit * InpFixedLotSize;
     }
   else
     {
      static const double divisor_high[7]  = {2000.0, 1200.0, 800.0, 600.0, 500.0, 400.0, 300.0};
      static const double divisor_other[7] = {2000.0, 1500.0, 1000.0, 800.0, 600.0, 550.0, 400.0};

      int level = (int)InpAutoRiskLevel;
      if(level < 0 || level > 6)
         return 0.0;

      double divisor = divisor_high[level];
      if(InpPreset >= PRESET_ICVT_LOW)
         divisor = divisor_other[level];

      if(InpPreset == PRESET_FUSION_ZERO && level == 6)
         divisor = 300.0;

      base_lot = AccountInfoDouble(ACCOUNT_BALANCE) / divisor * 0.01;
     }

   if(order_level > 0 && InpGridLotMultiplier > 1.0)
      base_lot = base_lot * MathPow(InpGridLotMultiplier, order_level);

   return NormalizeLotVolume(base_lot);
  }

//+------------------------------------------------------------------+
//| Check if Position Belongs to Zerith OneShot                      |
//+------------------------------------------------------------------+
bool IsOurPosition(const ulong ticket, const int slot = -1)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagicNumber ||
      PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if(slot >= 0)
     {
      string comment = PositionGetString(POSITION_COMMENT);
      return (StringFind(comment, StrategyTag(slot)) >= 0);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Count Open Positions for a Specific Strategy Slot                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Count All Open Positions Belonging to Zerith OneShot             |
//+------------------------------------------------------------------+
int TotalOurPositionsCount()
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

//+------------------------------------------------------------------+
//| Calculate Floating Profit for Strategy Slot                      |
//+------------------------------------------------------------------+
double StrategyProfit(const int slot)
  {
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket, slot))
         continue;
      profit += PositionGetDouble(POSITION_PROFIT);
      profit += PositionGetDouble(POSITION_SWAP);
     }
   return profit;
  }

//+------------------------------------------------------------------+
//| Calculate Total Floating Profit Across All Strategies            |
//+------------------------------------------------------------------+
double TotalStrategyProfit()
  {
   double profit = 0.0;
   for(int slot = 0; slot < TOTAL_STRATEGIES; slot++)
      profit += StrategyProfit(slot);
   return profit;
  }

//+------------------------------------------------------------------+
//| Calculate Total Open Volume Across All Strategies                |
//+------------------------------------------------------------------+
double TotalStrategyVolume()
  {
   double volume = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(IsOurPosition(ticket))
         volume += PositionGetDouble(POSITION_VOLUME);
     }
   return volume;
  }

//+------------------------------------------------------------------+
//| Close All Positions for a Given Strategy Slot                    |
//+------------------------------------------------------------------+
bool CloseStrategy(const int slot, const string reason)
  {
   bool selected = false;
   bool closed   = true;
   g_trade.SetExpertMagicNumber(StrategyMagic(slot));

   ulong tickets[];
   ArrayResize(tickets, 0);

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket, slot))
         continue;
      selected = true;
      int size = ArraySize(tickets);
      ArrayResize(tickets, size + 1);
      tickets[size] = ticket;
     }

   ArraySort(tickets);
   for(int i = 0; i < ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!g_trade.PositionClose(ticket))
        {
         closed = false;
         PrintFormat("Zerith OneShot: %s close failed ticket=%I64u retcode=%u err=%d",
                     reason, ticket, g_trade.ResultRetcode(), GetLastError());
        }
     }

   PrintFormat("Zerith OneShot: Position closure summary [Slot %d] Reason=%s Selected=%s Closed=%s",
               slot, reason, (selected ? "yes" : "no"), (closed ? "yes" : "no"));
   return (selected && closed);
  }

//+------------------------------------------------------------------+
//| Close All Strategies' Positions                                  |
//+------------------------------------------------------------------+
bool CloseAllStrategies(const string reason)
  {
   bool result = true;
   for(int slot = 0; slot < TOTAL_STRATEGIES; slot++)
     {
      if(StrategyPositionCount(slot) > 0 && !CloseStrategy(slot, reason))
         result = false;
     }
   return result;
  }

//+------------------------------------------------------------------+
//| Send Push / Terminal Notification                                |
//+------------------------------------------------------------------+
void NotifyRisk(const string message)
  {
   Print(message);
   if(InpPushNotifications && !SendNotification(message))
      PrintFormat("Zerith OneShot: Failed to send push notification (%d)", GetLastError());
  }

//+------------------------------------------------------------------+
//| Apply Drawdown Protection Rules                                  |
//+------------------------------------------------------------------+
void ApplyDrawdownControl()
  {
   if(InpDrawdownMode == DRAWDOWN_OFF || InpDrawdownThreshold <= 0.0)
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

   bool percent_mode = ((int)InpDrawdownMode >= 1 && (int)InpDrawdownMode <= 3);
   double measured   = -floating;
   string unit       = AccountInfoString(ACCOUNT_CURRENCY);

   if(percent_mode)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance <= 0.0)
         return;
      measured = (-floating / balance) * 100.0;
      unit     = "%";
     }

   if(measured < InpDrawdownThreshold)
     {
      g_drawdown_triggered = false;
      return;
     }

   string text = StringFormat("Zerith OneShot Drawdown threshold breached: %.2f%s (floating P/L %.2f %s)",
                              InpDrawdownThreshold, unit, floating, AccountInfoString(ACCOUNT_CURRENCY));
   bool first_trigger = !g_drawdown_triggered;
   if(first_trigger)
     {
      Print("Zerith OneShot: Drawdown threshold breached! Executing configured risk actions.");
      NotifyRisk(text);
     }
   g_drawdown_triggered = true;

   if(InpDrawdownMode == DRAWDOWN_PERCENT_ALERT_ONLY || InpDrawdownMode == DRAWDOWN_MONEY_ALERT_ONLY)
     {
      if(first_trigger && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
         Alert(text);
      return;
     }

   CloseAllStrategies("DrawdownBreach");

   if(InpDrawdownMode == DRAWDOWN_PERCENT_CLOSE_REMOVE || InpDrawdownMode == DRAWDOWN_MONEY_CLOSE_REMOVE)
      g_remove_after_risk = true;
  }

//+------------------------------------------------------------------+
//| Check if Current Spread is Within Limits                         |
//+------------------------------------------------------------------+
bool CheckSpreadAllowsEntry()
  {
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   return ((double)InpMaxSpread >= (ask - bid) / point);
  }

//+------------------------------------------------------------------+
//| Check if Margin Permits New Position                             |
//+------------------------------------------------------------------+
bool CheckMarginAllowsEntry(const int direction, const double volume)
  {
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free_margin <= 0.0)
      return false;

   double price = SymbolInfoDouble(_Symbol, (direction > 0 ? SYMBOL_ASK : SYMBOL_BID));
   double required_margin = 0.0;
   ENUM_ORDER_TYPE order_type = (direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);

   if(!OrderCalcMargin(order_type, _Symbol, volume, price, required_margin))
      return false;

   return (required_margin <= free_margin);
  }

//+------------------------------------------------------------------+
//| Break-Even and Trailing Stop Engine                              |
//+------------------------------------------------------------------+
void ApplyBreakEvenAndTrailing(const int slot)
  {
   if(InpBreakEvenStart <= 0 && InpTrailingStart <= 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket, slot))
         continue;

      long   type        = PositionGetInteger(POSITION_TYPE);
      double open_price  = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl  = PositionGetDouble(POSITION_SL);
      double current_tp  = PositionGetDouble(POSITION_TP);

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
         return;

      double new_sl = current_sl;

      if(type == POSITION_TYPE_BUY)
        {
         double profit_pts = (tick.bid - open_price) / _Point;

         // Break-Even Adjustment
         if(InpBreakEvenStart > 0 && profit_pts >= InpBreakEvenStart)
           {
            double be_level = NormalizePrice(open_price + InpBreakEvenOffset * _Point);
            if(new_sl < be_level)
               new_sl = be_level;
           }

         // Trailing Stop Adjustment
         if(InpTrailingStart > 0 && InpTrailingStep > 0 && profit_pts >= InpTrailingStart)
           {
            double trail_level = NormalizePrice(tick.bid - InpTrailingStep * _Point);
            if(trail_level > new_sl)
               new_sl = trail_level;
           }
        }
      else if(type == POSITION_TYPE_SELL)
        {
         double profit_pts = (open_price - tick.ask) / _Point;

         // Break-Even Adjustment
         if(InpBreakEvenStart > 0 && profit_pts >= InpBreakEvenStart)
           {
            double be_level = NormalizePrice(open_price - InpBreakEvenOffset * _Point);
            if(current_sl <= 0.0 || new_sl > be_level)
               new_sl = be_level;
           }

         // Trailing Stop Adjustment
         if(InpTrailingStart > 0 && InpTrailingStep > 0 && profit_pts >= InpTrailingStart)
           {
            double trail_level = NormalizePrice(tick.ask + InpTrailingStep * _Point);
            if(current_sl <= 0.0 || trail_level < new_sl)
               new_sl = trail_level;
           }
        }

      // Execute modification if Stop Loss changed
      if(new_sl != current_sl && new_sl > 0.0)
        {
         g_trade.SetExpertMagicNumber(StrategyMagic(slot));
         if(!g_trade.PositionModify(ticket, new_sl, current_tp))
            PrintFormat("Zerith OneShot: BE/Trail modify failed [Slot %d] Ticket=%I64u Retcode=%u Err=%d",
                        slot, ticket, g_trade.ResultRetcode(), GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate Basket Statistics for a Specific Strategy Slot         |
//+------------------------------------------------------------------+
int GetStrategyBasketStats(const int slot, double &avg_price, double &total_vol, double &latest_price, long &pos_type)
  {
   int count = 0;
   avg_price = 0.0;
   total_vol = 0.0;
   latest_price = 0.0;
   pos_type = -1;
   datetime latest_open_time = 0;
   double cost_sum = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(!IsOurPosition(ticket, slot))
         continue;

      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      long   type  = PositionGetInteger(POSITION_TYPE);
      datetime op_time = (datetime)PositionGetInteger(POSITION_TIME);

      cost_sum += price * vol;
      total_vol += vol;
      pos_type = type;
      count++;

      if(op_time >= latest_open_time)
        {
         latest_open_time = op_time;
         latest_price = price;
        }
     }

   if(total_vol > 0.0)
      avg_price = NormalizePrice(cost_sum / total_vol);

   return count;
  }

//+------------------------------------------------------------------+
//| Calculate Step Distance for Next Recovery Order (Points)         |
//+------------------------------------------------------------------+
double CalculateStepDistance(const int current_count)
  {
   if(InpGridSpacingMode == GRID_SPACING_ORIGINAL_FIXED || current_count <= 1)
      return InpGridBaseDistance;

   // Expanding Mode: Step Distance Multiplier per Level (*ระยะ เมื่อจำนวนไม้เพิ่มขึ้น)
   // Level 2 (current_count == 1): InpGridBaseDistance * (mult^0) = Base
   // Level 3 (current_count == 2): InpGridBaseDistance * (mult^1)
   // Level 4 (current_count == 3): InpGridBaseDistance * (mult^2)
   double mult = MathMax(1.0, InpGridStepMultiplier);
   return InpGridBaseDistance * MathPow(mult, current_count - 1);
  }

//+------------------------------------------------------------------+
//| Manage Position State for Strategy Slot (Grid Recovery Engine)   |
//+------------------------------------------------------------------+
void ManageStrategy(const int slot)
  {
   if(!StrategyEnabled(slot))
      return;

   double avg_price = 0.0, total_vol = 0.0, latest_price = 0.0;
   long   pos_type  = -1;
   int    count     = GetStrategyBasketStats(slot, avg_price, total_vol, latest_price, pos_type);
   if(count <= 0)
      return;

   double point = _Point;
   if(point <= 0.0) point = 0.01;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // =============================================================
   // 1. Take Profit Management (Basket TP vs Single Order)
   // =============================================================
   // Basket Take Profit for 2 or more open positions
   if(count >= 2 && InpBasketTakeProfit > 0)
     {
      double basket_tp = (pos_type == POSITION_TYPE_BUY) ?
                         NormalizePrice(avg_price + InpBasketTakeProfit * point) :
                         NormalizePrice(avg_price - InpBasketTakeProfit * point);

      bool basket_tp_hit = (pos_type == POSITION_TYPE_BUY && bid >= basket_tp) ||
                           (pos_type == POSITION_TYPE_SELL && ask <= basket_tp);

      if(basket_tp_hit)
        {
         PrintFormat("🎯 [Basket TP Hit] Strategy %d closed %d positions at target %.2f (Avg: %.2f)",
                     slot + 1, count, basket_tp, avg_price);
         CloseStrategy(slot, "Basket Take Profit");
         return;
        }
     }
   else if(count == 1)
     {
      // Single Initial One-Shot order management (Break-Even & Trailing Stop)
      ApplyBreakEvenAndTrailing(slot);
     }

   // =============================================================
   // 2. Grid Recovery Engine (Original 100% vs Expanding Multiplier)
   // =============================================================
   if(!InpEnableGridRecovery || g_is_paused)
      return;

   // Calculate step distance for next recovery order
   double step_pts  = CalculateStepDistance(count);
   double step_dist = step_pts * point;

   if(pos_type == POSITION_TYPE_BUY)
     {
      double next_trigger_price = latest_price - step_dist;

      if(bid <= next_trigger_price)
        {
         // Case A: Within allowed basket size -> Open Recovery Order
         if(count < InpMaxBasketOrders)
           {
            if(TotalOurPositionsCount() >= InpMaxOrdersTotal)
               return;

            double rec_vol = CalculateLotVolume(count);
            if(rec_vol <= 0.0)
               return;

            if(!CheckSpreadAllowsEntry() || !CheckMarginAllowsEntry(1, rec_vol))
               return;

            g_trade.SetExpertMagicNumber(StrategyMagic(slot));
            g_trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxSlippage));

            double sl_price = (InpStopLoss > 0) ? NormalizePrice(ask - InpStopLoss * point) : 0.0;
            double tp_price = (InpTakeProfit > 0) ? NormalizePrice(ask + InpTakeProfit * point) : 0.0;

            if(g_trade.Buy(rec_vol, _Symbol, 0.0, sl_price, tp_price, SafeComment(slot, count)))
              {
               PrintFormat("🛡️ [Grid Recovery BUY] Order #%d for Strategy %d opened at %.2f (Step: %.1f pts | Mode: %s)",
                           count + 1, slot + 1, ask, step_pts,
                           (InpGridSpacingMode == GRID_SPACING_ORIGINAL_FIXED ? "100% Original Fixed" : "Expanding Multiplier"));
              }
           }
         // Case B: Reached InpMaxBasketOrders -> Hard Cut-Loss on (MaxOrders + 1) step
         else if(count >= InpMaxBasketOrders && InpCutLossOnMaxStep)
           {
            PrintFormat("🚨 [Grid Cut-Loss] Strategy %d reached MaxBasketOrders (%d) + 1 step distance (%.2f <= %.2f) -> Closing basket!",
                        slot + 1, InpMaxBasketOrders, bid, next_trigger_price);
            CloseStrategy(slot, "Grid Max Step Cut-Loss");
            return;
           }
        }
     }
   else if(pos_type == POSITION_TYPE_SELL)
     {
      double next_trigger_price = latest_price + step_dist;

      if(ask >= next_trigger_price)
        {
         // Case A: Within allowed basket size -> Open Recovery Order
         if(count < InpMaxBasketOrders)
           {
            if(TotalOurPositionsCount() >= InpMaxOrdersTotal)
               return;

            double rec_vol = CalculateLotVolume(count);
            if(rec_vol <= 0.0)
               return;

            if(!CheckSpreadAllowsEntry() || !CheckMarginAllowsEntry(-1, rec_vol))
               return;

            g_trade.SetExpertMagicNumber(StrategyMagic(slot));
            g_trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxSlippage));

            double sl_price = (InpStopLoss > 0) ? NormalizePrice(bid + InpStopLoss * point) : 0.0;
            double tp_price = (InpTakeProfit > 0) ? NormalizePrice(bid - InpTakeProfit * point) : 0.0;

            if(g_trade.Sell(rec_vol, _Symbol, 0.0, sl_price, tp_price, SafeComment(slot, count)))
              {
               PrintFormat("🛡️ [Grid Recovery SELL] Order #%d for Strategy %d opened at %.2f (Step: %.1f pts | Mode: %s)",
                           count + 1, slot + 1, bid, step_pts,
                           (InpGridSpacingMode == GRID_SPACING_ORIGINAL_FIXED ? "100% Original Fixed" : "Expanding Multiplier"));
              }
           }
         // Case B: Reached InpMaxBasketOrders -> Hard Cut-Loss on (MaxOrders + 1) step
         else if(count >= InpMaxBasketOrders && InpCutLossOnMaxStep)
           {
            PrintFormat("🚨 [Grid Cut-Loss] Strategy %d reached MaxBasketOrders (%d) + 1 step distance (%.2f >= %.2f) -> Closing basket!",
                        slot + 1, InpMaxBasketOrders, ask, next_trigger_price);
            CloseStrategy(slot, "Grid Max Step Cut-Loss");
            return;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Trading Calendar and Time Schedule Filter                        |
//+------------------------------------------------------------------+
bool ScheduleAllowsTrading()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   bool day_allowed = false;
   switch(now.day_of_week)
     {
      case 0: day_allowed = InpTradeSunday;    break;
      case 1: day_allowed = InpTradeMonday;    break;
      case 2: day_allowed = InpTradeTuesday;   break;
      case 3: day_allowed = InpTradeWednesday; break;
      case 4: day_allowed = InpTradeThursday;  break;
      case 5: day_allowed = InpTradeFriday;    break;
      case 6: day_allowed = InpTradeSaturday;  break;
     }
   if(!day_allowed)
      return false;

   // NFP Friday Filter (First Friday of Month)
   if(InpUseNfpFridayFilter && now.day_of_week == 5 && now.day < 8)
      return false;

   // Friday Night Close Window
   if(InpCloseFridayNight && now.day_of_week == 5 && now.hour >= (int)InpFridayNightCloseHour)
      return false;

   // Holiday Season Pause (Dec 15 - Jan 15)
   int mmdd = now.mon * 100 + now.day;
   if(InpUseYearEndPause && (mmdd <= 115 || mmdd >= 1215))
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| Get Primary Execution Timeframe for Strategy Slot                |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES PrimaryTimeframe(const int slot)
  {
   static const ENUM_TIMEFRAMES values[TOTAL_STRATEGIES] =
     {
      PERIOD_M6,  PERIOD_M15, PERIOD_M15, PERIOD_M15,
      PERIOD_M5,  PERIOD_M10, PERIOD_M5,  PERIOD_M5,
      PERIOD_M12, PERIOD_M10, PERIOD_M10, PERIOD_M12
     };
   if(slot < 0 || slot >= TOTAL_STRATEGIES)
      return PERIOD_CURRENT;
   return values[slot];
  }

//+------------------------------------------------------------------+
//| Check if Current Hour is Allowed for Strategy Slot               |
//+------------------------------------------------------------------+
bool StrategyHourAllowed(const int slot, const int hour)
  {
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
   return false;
  }

//+------------------------------------------------------------------+
//| New Bar Detection per Strategy Primary Timeframe                 |
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
//| Get Strategy Signal with First-Instinct Fresh Cross Logic       |
//+------------------------------------------------------------------+
int GetStrategySignal(const int slot)
  {
   if(slot < 0 || slot >= TOTAL_STRATEGIES ||
      g_demarker_a[slot] == INVALID_HANDLE ||
      g_demarker_b[slot] == INVALID_HANDLE)
      return 0;

   double a[], b[];
   ArraySetAsSeries(a, true);
   ArraySetAsSeries(b, true);
   if(CopyBuffer(g_demarker_a[slot], 0, 0, 3, a) < 2)
      return 0;
   if(CopyBuffer(g_demarker_b[slot], 0, 0, 3, b) < 2)
      return 0;
   ArraySetAsSeries(a, true);
   ArraySetAsSeries(b, true);

   static const double upper_a[TOTAL_STRATEGIES] = {0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.9, 0.5, 0.9, 0.7, 0.7, 0.7};
   static const double lower_a[TOTAL_STRATEGIES] = {0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.1};
   static const double upper_b[TOTAL_STRATEGIES] = {0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.9, 0.9, 0.9, 0.7, 0.7};
   static const double lower_b[TOTAL_STRATEGIES] = {0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3};

   bool buy_signal  = false;
   bool sell_signal = false;

   if(InpFreshCrossOnly)
     {
      bool cross_a = (ArraySize(a) >= 3 && a[2] <= upper_a[slot] && a[1] > upper_a[slot]) ||
                     (a[1] <= upper_a[slot] && a[0] > upper_a[slot]);
      bool conf_b  = (b[0] > upper_b[slot] || b[1] > upper_b[slot]);
      buy_signal   = cross_a && conf_b;

      bool cross_sell_a = (ArraySize(a) >= 3 && a[2] >= lower_a[slot] && a[1] < lower_a[slot]) ||
                          (a[1] >= lower_a[slot] && a[0] < lower_a[slot]);
      bool conf_sell_b  = (b[0] < lower_b[slot] || b[1] < lower_b[slot]);
      sell_signal       = cross_sell_a && conf_sell_b;
     }
   else
     {
      // Legacy threshold confirmation
      buy_signal  = (a[0] > upper_a[slot] && b[0] > upper_b[slot]);
      sell_signal = (a[0] < lower_a[slot] && b[0] < lower_b[slot]);
     }

   if(buy_signal)
      return 1;
   if(sell_signal)
      return -1;

   return 0;
  }

//+------------------------------------------------------------------+
//| Execute Strategy Processing & One-Shot Management                |
//+------------------------------------------------------------------+
void ProcessStrategy(const int slot)
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   // Session Window Check:
   // When outside allowed hour window, reset one-shot execution flag for next session
   if(!StrategyHourAllowed(slot, now.hour))
     {
      g_session_executed[slot] = false;
      return;
     }

   // Reset lock if calendar day has changed since last trade
   if(g_session_executed_day[slot] != now.day_of_year)
     {
      g_session_executed[slot] = false;
     }

   if(!StrategyEnabled(slot))
      return;
   if(!ScheduleAllowsTrading() || g_is_paused)
      return;

   // First-Instinct (One-Shot): Block repeat entries within same session
   if(InpOneShotPerSession && g_session_executed[slot])
      return;

   if(!IsNewEligibleBar(slot))
      return;

   int signal = GetStrategySignal(slot);
   if(signal == 0)
      return;

   int expected_direction = StrategyDirection(slot);
   if((signal > 0 && expected_direction < 0) || (signal < 0 && expected_direction > 0))
      return;

   if(StrategyPositionCount(slot) > 0)
      return;

   if(TotalOurPositionsCount() >= InpMaxOrdersTotal)
      return;

   double volume = CalculateLotVolume(0);
   if(volume <= 0.0)
      return;

   if(!CheckSpreadAllowsEntry() || !CheckMarginAllowsEntry(signal, volume))
      return;

   g_trade.SetExpertMagicNumber(StrategyMagic(slot));
   g_trade.SetDeviationInPoints((ulong)MathMax(0, InpMaxSlippage));

   double sl_price = 0.0;
   double tp_price = 0.0;
   bool   opened   = false;

   if(signal > 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(InpStopLoss > 0)
         sl_price = NormalizePrice(ask - InpStopLoss * _Point);
      if(InpTakeProfit > 0)
         tp_price = NormalizePrice(ask + InpTakeProfit * _Point);
      opened = g_trade.Buy(volume, _Symbol, 0.0, sl_price, tp_price, SafeComment(slot, 0));
     }
   else
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(InpStopLoss > 0)
         sl_price = NormalizePrice(bid + InpStopLoss * _Point);
      if(InpTakeProfit > 0)
         tp_price = NormalizePrice(bid - InpTakeProfit * _Point);
      opened = g_trade.Sell(volume, _Symbol, 0.0, sl_price, tp_price, SafeComment(slot, 0));
     }

   if(opened)
     {
      g_session_executed[slot]     = true;
      g_session_executed_day[slot] = now.day_of_year;
      PrintFormat("Zerith OneShot: First-Instinct order opened [Strategy %d] Signal=%s Vol=%.2f Ticket=%I64u",
                  slot + 1, (signal > 0 ? "BUY" : "SELL"), volume, g_trade.ResultOrder());
     }
   else
     {
      PrintFormat("Zerith OneShot: Order failed [Strategy %d] Signal=%d Retcode=%u Error=%d",
                  slot + 1, signal, g_trade.ResultRetcode(), GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| UI Formatting Helper Functions                                   |
//+------------------------------------------------------------------+
string LotModeText()
  {
   if(InpLotMode == LOT_MODE_FIXED)
      return "Fixed Lot Size";
   if(InpLotMode == LOT_MODE_FIXED_PER_BALANCE)
      return "Fixed Per Balance Unit";
   return "Automatic (Dynamic Risk)";
  }

string RiskLevelText()
  {
   static const string names[7] =
     {
      "Very Low", "Low", "Low-Medium", "Medium", "Medium-High", "High", "Very High"
     };
   int index = (int)InpAutoRiskLevel;
   if(index < 0 || index > 6)
      return "---";
   return names[index];
  }

string PresetText()
  {
   switch(InpPreset)
     {
      case PRESET_ICVT_HIGH:   return "IC / VT Markets (RAW) - High Risk";
      case PRESET_ICVT_MEDIUM: return "IC / VT Markets (RAW) - Medium Risk";
      case PRESET_ICVT_LOW:    return "IC / VT Markets (RAW) - Low Risk";
      case PRESET_ROBO_ECN:    return "RoboForex - ECN";
      case PRESET_FUSION_ZERO: return "Fusion Markets - Zero";
      case PRESET_CUSTOM:      return "Custom Profile";
     }
   return "Custom";
  }

string DrawdownModeText()
  {
   switch(InpDrawdownMode)
     {
      case DRAWDOWN_OFF:                    return "Off";
      case DRAWDOWN_PERCENT_CLOSE_CONTINUE: return "[Percent] Close All & Continue";
      case DRAWDOWN_PERCENT_CLOSE_REMOVE:   return "[Percent] Close All & Remove EA";
      case DRAWDOWN_PERCENT_ALERT_ONLY:     return "[Percent] Terminal Alert Only";
      case DRAWDOWN_MONEY_CLOSE_CONTINUE:   return "[Money] Close All & Continue";
      case DRAWDOWN_MONEY_CLOSE_REMOVE:     return "[Money] Close All & Remove EA";
      case DRAWDOWN_MONEY_ALERT_ONLY:       return "[Money] Terminal Alert Only";
     }
   return "Off";
  }

string StrategySessionString(const int slot)
  {
   switch(slot)
     {
      case 0:  return "22:00-23:59";
      case 1:  return "03:00-03:59";
      case 2:  return "22:00-22:59";
      case 3:  return "19:00-19:59";
      case 4:  return "00:00-00:59";
      case 5:  return "23:00-23:59";
      case 6:  return "08:00-10:59";
      case 7:  return "06:00-11:59";
      case 8:  return "10:00-13:59";
      case 9:  return "22:00-22:59";
      case 10: return "04:00-08:59";
      case 11: return "08:00-09:59";
     }
   return "N/A";
  }

string StrategyTimeframeString(const int slot)
  {
   switch(slot)
     {
      case 0:  return "M6/M15";
      case 1:  return "M15/M20";
      case 2:  return "M15/M15";
      case 3:  return "M15/M20";
      case 4:  return "M1/M15";
      case 5:  return "M10/M30";
      case 6:  return "M1/M20";
      case 7:  return "M1/H1";
      case 8:  return "M12/M15";
      case 9:  return "M10/M15";
      case 10: return "M10/M30";
      case 11: return "M12/M15";
     }
   return "N/A";
  }

//+------------------------------------------------------------------+
//| Dashboard UI Engine                                              |
//+------------------------------------------------------------------+
void ConfigurePanelObject(const string name)
  {
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

bool CreatePanelRectangle(const string name, const int x, const int y,
                          const int width, const int height,
                          const color bg_color, const color border_color)
  {
   if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0) && ObjectFind(0, name) < 0)
      return false;
   ConfigurePanelObject(name);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border_color);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border_color);
   return true;
  }

bool CreatePanelLabel(const string name, const string text, const int x, const int y,
                      const color clr = clrWhite, const string font_name = "",
                      const int font_size = -1)
  {
   if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0) && ObjectFind(0, name) < 0)
      return false;
   ConfigurePanelObject(name);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, (font_size < 0 ? InpFontSize : font_size));
   ObjectSetString(0, name, OBJPROP_FONT, (font_name == "" ? InpFontName : font_name));
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   return true;
  }

bool CreatePanelButton(const string name, const string text, const int x, const int y,
                       const int width, const int height,
                       const color bg_color = C'38,44,58', const color border_color = C'65,75,98')
  {
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0) && ObjectFind(0, name) < 0)
      return false;
   ConfigurePanelObject(name);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_color);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, border_color);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
   ObjectSetString(0, name, OBJPROP_FONT, InpFontName);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   return true;
  }

void SetPanelLine(const int index, const string text, const color clr = C'225,230,240')
  {
   const int x   = (index < 24 ? 16 : 332);
   const int row = (index < 24 ? index : index - 24);
   string name   = PANEL_PREFIX + "Line_" + IntegerToString(index);
   CreatePanelLabel(name, text, x, 99 + row * 16, clr);
  }

void DeletePanel()
  {
   ObjectsDeleteAll(0, PANEL_PREFIX);
  }

void CreatePanel()
  {
   color bg_main    = C'18,20,26'; // Deep Graphite Slate
   color border_col = C'45,50,65'; // Slate Border
   color bg_client  = C'24,27,35'; // Content Background
   color bg_header  = C'30,35,48'; // Title Bar

   CreatePanelRectangle(PANEL_PREFIX + "Back", 6, 21, 643, 468, bg_main, bg_main);
   CreatePanelRectangle(PANEL_PREFIX + "Border", 5, 20, 645, 470, bg_main, border_col);
   CreatePanelRectangle(PANEL_PREFIX + "ClientBack", 9, 44, 637, 442, bg_client, bg_client);

   string caption = PANEL_PREFIX + "Caption";
   if(ObjectCreate(0, caption, OBJ_EDIT, 0, 0, 0) || ObjectFind(0, caption) >= 0)
     {
      ConfigurePanelObject(caption);
      ObjectSetInteger(0, caption, OBJPROP_XDISTANCE, 7);
      ObjectSetInteger(0, caption, OBJPROP_YDISTANCE, 22);
      ObjectSetInteger(0, caption, OBJPROP_XSIZE, 641);
      ObjectSetInteger(0, caption, OBJPROP_YSIZE, 22);
      ObjectSetInteger(0, caption, OBJPROP_COLOR, C'0,195,255');
      ObjectSetInteger(0, caption, OBJPROP_BGCOLOR, bg_header);
      ObjectSetInteger(0, caption, OBJPROP_BORDER_COLOR, bg_header);
      ObjectSetInteger(0, caption, OBJPROP_FONTSIZE, InpFontSize + 1);
      ObjectSetInteger(0, caption, OBJPROP_READONLY, true);
      ObjectSetString(0, caption, OBJPROP_FONT, InpFontName);
      ObjectSetString(0, caption, OBJPROP_TEXT, "ZERITH ONESHOT MT5 v1.00 [" + _Symbol + "] - FIRST-INSTINCT ENGINE");
     }

   CreatePanelLabel(PANEL_PREFIX + "Close", "x", 632, 25, C'200,200,210', InpFontName, InpFontSize + 2);
   CreatePanelLabel(PANEL_PREFIX + "MinMax", "-", 615, 25, C'200,200,210', InpFontName, InpFontSize + 2);

   CreatePanelButton(PANEL_PREFIX + "BtnPause", (g_is_paused ? "RESUME EA" : "PAUSE EA"), 14, 50, 309, 20);
   CreatePanelButton(PANEL_PREFIX + "BtnCloseAll", "CLOSE ALL TRADES", 330, 50, 311, 20, C'70,30,35', C'110,45,55');
   CreatePanelButton(PANEL_PREFIX + "BtnInfo", "SYSTEM INFORMATION & STRATEGY GUIDE", 14, 73, 627, 20);

   for(int i = 0; i < 48; i++)
      SetPanelLine(i, " ");

   UpdatePanel();
  }

void UpdatePanel()
  {
   if(ObjectFind(0, PANEL_PREFIX + "Line_0") < 0)
      return;

   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   double total_pl = TotalStrategyProfit();
   color  pl_color = (total_pl >= 0.0 ? C'75,225,125' : C'255,95,95');

   string grid_info = (!InpEnableGridRecovery ? "Disabled" :
                       (InpGridSpacingMode == GRID_SPACING_ORIGINAL_FIXED ? "100% Fixed (" + DoubleToString(InpGridBaseDistance, 0) + "pts)" :
                        "Expanding x" + DoubleToString(InpGridStepMultiplier, 1)));
   SetPanelLine(0, "Execution: One-Shot (1st Instinct: " + (InpOneShotPerSession ? "1/Session" : "Unlimited") + ")",
                (InpOneShotPerSession ? C'255,185,50' : C'160,165,175'));
   SetPanelLine(1, "Recovery Grid: " + grid_info + " | Max: " + IntegerToString(InpMaxBasketOrders),
                (InpEnableGridRecovery ? C'0,195,255' : C'160,165,175'));
   SetPanelLine(2, "Lot Sizing Mode: " + LotModeText());
   SetPanelLine(3, "Auto Risk Level: " + (InpLotMode == LOT_MODE_AUTOMATIC ? RiskLevelText() : "---"));
   SetPanelLine(4, "Fixed Lot: " + (InpLotMode == LOT_MODE_FIXED ? DoubleToString(InpFixedLotSize, 2) : "---") +
                   " | Per Balance: " + (InpLotMode == LOT_MODE_FIXED_PER_BALANCE ? DoubleToString(InpFixedLotPerBalance, 2) : "---"));
   SetPanelLine(5, "Drawdown Protection: " + DrawdownModeText());
   SetPanelLine(6, "Drawdown Threshold: " + (InpDrawdownMode == DRAWDOWN_OFF ? "---" : DoubleToString(InpDrawdownThreshold, 2)));
   SetPanelLine(7, "Magic: " + (string)InpMagicNumber + " | Slippage: " + (string)InpMaxSlippage + " pts | Spread: " + (string)InpMaxSpread + " pts");
   SetPanelLine(8, "Order Comment: " + InpTradeCommentPrefix);
   SetPanelLine(9, "MQID Notifications: " + (InpPushNotifications ? "Enabled" : "Disabled"));
   SetPanelLine(10, "Preset Profile: " + PresetText(), C'0,195,255');
   SetPanelLine(11, "---------------- ACCOUNT PERFORMANCE ----------------", C'100,110,130');
   SetPanelLine(12, StringFormat("Total Floating P/L: %.2f %s", total_pl, currency), pl_color);
   SetPanelLine(13, StringFormat("Balance: %.2f %s", AccountInfoDouble(ACCOUNT_BALANCE), currency));
   SetPanelLine(14, StringFormat("Equity: %.2f %s", AccountInfoDouble(ACCOUNT_EQUITY), currency));
   SetPanelLine(15, StringFormat("Margin Level: %.0f %%", AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)));
   SetPanelLine(16, StringFormat("Margin Call: %.0f %% | Stop-out: %.0f %%",
                                 AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL),
                                 AccountInfoDouble(ACCOUNT_MARGIN_SO_SO)));
   SetPanelLine(17, StringFormat("Open Positions: %d | Volume: %.2f lots",
                                 TotalOurPositionsCount(), TotalStrategyVolume()));
   SetPanelLine(18, "---------------- ACCOUNT DETAILS --------------------", C'100,110,130');
   SetPanelLine(19, "Trader: " + AccountInfoString(ACCOUNT_NAME));
   SetPanelLine(20, "Broker: " + AccountInfoString(ACCOUNT_COMPANY));
   SetPanelLine(21, "Server: " + AccountInfoString(ACCOUNT_SERVER) + " | Login: " + (string)AccountInfoInteger(ACCOUNT_LOGIN));
   SetPanelLine(22, StringFormat("Leverage: %d:1 | Currency: %s", (int)AccountInfoInteger(ACCOUNT_LEVERAGE), currency));
   SetPanelLine(23, "Time: " + TimeToString(TimeCurrent(), TIME_SECONDS) + " | Status: " + (g_is_paused ? "PAUSED" : "ACTIVE"),
                (g_is_paused ? C'255,95,95' : C'75,225,125'));

   // Column 2: 12 Strategy Status & Session Watchers
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   for(int slot = 0; slot < TOTAL_STRATEGIES; slot++)
     {
      int line         = 24 + slot * 2;
      bool enabled     = StrategyEnabled(slot);
      int count        = StrategyPositionCount(slot);
      bool inside_hour = StrategyHourAllowed(slot, now.hour);

      string header = StringFormat("[S%02d] %s | %s | %s",
                                   slot + 1,
                                   StrategyTimeframeString(slot),
                                   StrategySessionString(slot),
                                   (enabled ? "ON" : "OFF"));

      color header_clr = (!enabled ? C'110,115,125' : (count > 0 ? C'0,210,255' : C'220,225,235'));
      SetPanelLine(line, header, header_clr);

      string status_text;
      color status_clr;

      if(!enabled)
        {
         status_text = "   Strategy Inactive in Profile";
         status_clr  = C'100,105,115';
        }
      else if(count > 0)
        {
         double profit = StrategyProfit(slot);
         if(count > 1)
            status_text = StringFormat("   Grid Active (%d pos) | P/L: %.2f %s", count, profit, currency);
         else
            status_text = StringFormat("   In Trade (1 pos) | P/L: %.2f %s", profit, currency);
         status_clr  = (profit >= 0.0 ? C'75,225,125' : C'255,95,95');
        }
      else if(!inside_hour)
        {
         status_text = "   Session Inactive (Outside Hours)";
         status_clr  = C'130,135,145';
        }
      else if(InpOneShotPerSession && g_session_executed[slot])
        {
         status_text = "   One-Shot Locked (Session Executed)";
         status_clr  = C'255,185,50'; // Amber
        }
      else
        {
         status_text = (InpFreshCrossOnly ? "   Watching for Fresh Signal Cross..." : "   Watching for Threshold Signal...");
         status_clr  = C'170,180,195';
        }

      SetPanelLine(line + 1, status_text, status_clr);
     }

   // Update Pause Button Appearance
   ObjectSetString(0, PANEL_PREFIX + "BtnPause", OBJPROP_TEXT, (g_is_paused ? "RESUME EA" : "PAUSE EA"));
   ObjectSetInteger(0, PANEL_PREFIX + "BtnPause", OBJPROP_BGCOLOR, (g_is_paused ? C'140,40,40' : C'38,44,58'));
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Indicator Handle Initialization                                  |
//+------------------------------------------------------------------+
bool CreateSignalHandles()
  {
   for(int i = 0; i < TOTAL_STRATEGIES; i++)
     {
      g_demarker_a[i] = INVALID_HANDLE;
      g_demarker_b[i] = INVALID_HANDLE;
     }

   // Strategy 01: M6, 18 | M15, 16
   g_demarker_a[0] = iDeMarker(_Symbol, PERIOD_M6, 18);
   g_demarker_b[0] = iDeMarker(_Symbol, PERIOD_M15, 16);

   // Strategy 02: M15, 14 | M20, 20
   g_demarker_a[1] = iDeMarker(_Symbol, PERIOD_M15, 14);
   g_demarker_b[1] = iDeMarker(_Symbol, PERIOD_M20, 20);

   // Strategy 03: M15, 26 | M15, 24
   g_demarker_a[2] = iDeMarker(_Symbol, PERIOD_M15, 26);
   g_demarker_b[2] = iDeMarker(_Symbol, PERIOD_M15, 24);

   // Strategy 04: M15, 20 | M20, 22
   g_demarker_a[3] = iDeMarker(_Symbol, PERIOD_M15, 20);
   g_demarker_b[3] = iDeMarker(_Symbol, PERIOD_M20, 22);

   // Strategy 05: M1, 18 | M15, 18
   g_demarker_a[4] = iDeMarker(_Symbol, PERIOD_M1, 18);
   g_demarker_b[4] = iDeMarker(_Symbol, PERIOD_M15, 18);

   // Strategy 06: M10, 30 | M30, 28
   g_demarker_a[5] = iDeMarker(_Symbol, PERIOD_M10, 30);
   g_demarker_b[5] = iDeMarker(_Symbol, PERIOD_M30, 28);

   // Strategy 07: M1, 20 | M20, 16
   g_demarker_a[6] = iDeMarker(_Symbol, PERIOD_M1, 20);
   g_demarker_b[6] = iDeMarker(_Symbol, PERIOD_M20, 16);

   // Strategy 08: M1, 12 | H1, 20
   g_demarker_a[7] = iDeMarker(_Symbol, PERIOD_M1, 12);
   g_demarker_b[7] = iDeMarker(_Symbol, PERIOD_H1, 20);

   // Strategy 09: M12, 18 | M15, 12
   g_demarker_a[8] = iDeMarker(_Symbol, PERIOD_M12, 18);
   g_demarker_b[8] = iDeMarker(_Symbol, PERIOD_M15, 12);

   // Strategy 10: M10, 20 | M15, 10
   g_demarker_a[9] = iDeMarker(_Symbol, PERIOD_M10, 20);
   g_demarker_b[9] = iDeMarker(_Symbol, PERIOD_M15, 10);

   // Strategy 11: M10, 30 | M30, 28
   g_demarker_a[10] = iDeMarker(_Symbol, PERIOD_M10, 30);
   g_demarker_b[10] = iDeMarker(_Symbol, PERIOD_M30, 28);

   // Strategy 12: M12, 10 | M15, 20
   g_demarker_a[11] = iDeMarker(_Symbol, PERIOD_M12, 10);
   g_demarker_b[11] = iDeMarker(_Symbol, PERIOD_M15, 20);

   for(int i = 0; i < TOTAL_STRATEGIES; i++)
     {
      if(g_demarker_a[i] == INVALID_HANDLE || g_demarker_b[i] == INVALID_HANDLE)
        {
         PrintFormat("Zerith OneShot: Failed to create DeMarker indicator handle for strategy %d (Error %d)",
                     i + 1, GetLastError());
         return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayInitialize(g_last_bar_time, 0);
   ArrayInitialize(g_session_executed, false);
   ArrayInitialize(g_session_executed_day, 0);

   g_is_paused = InpStartPaused;
   g_trade.SetAsyncMode(false);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!CreateSignalHandles())
     {
      Print("Zerith OneShot: Fatal error - unable to create indicator handles.");
      return INIT_FAILED;
     }

   PrintFormat("Zerith OneShot MT5 v1.00 initialized on %s.", _Symbol);
   PrintFormat("One-Shot Execution: %s | Fresh Cross Only: %s",
               (InpOneShotPerSession ? "ENABLED" : "DISABLED"),
               (InpFreshCrossOnly ? "ENABLED" : "DISABLED"));

   if(InpShowPanel)
      CreatePanel();

   if(!EventSetTimer(1))
      Print("Zerith OneShot: Warning - panel timer failed to start.");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   for(int i = 0; i < TOTAL_STRATEGIES; i++)
     {
      if(g_demarker_a[i] != INVALID_HANDLE)
        {
         IndicatorRelease(g_demarker_a[i]);
         g_demarker_a[i] = INVALID_HANDLE;
        }
      if(g_demarker_b[i] != INVALID_HANDLE)
        {
         IndicatorRelease(g_demarker_b[i]);
         g_demarker_b[i] = INVALID_HANDLE;
        }
     }

   DeletePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!CheckTradingEnvironmentReady())
      return;

   ApplyDrawdownControl();

   // Process strategy entries
   for(int slot = 0; slot < TOTAL_STRATEGIES; slot++)
      ProcessStrategy(slot);

   // Manage open positions (Break-even & Trailing stop)
   for(int slot = 0; slot < TOTAL_STRATEGIES; slot++)
      ManageStrategy(slot);

   if(g_remove_after_risk)
     {
      g_remove_after_risk = false;
      Print("Zerith OneShot: Drawdown breach action - removing EA from chart.");
      ExpertRemove();
     }
  }

//+------------------------------------------------------------------+
//| Timer Function for Panel Updates                                 |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();
   if(InpShowPanel && (now - g_last_panel_update >= 1))
     {
      g_last_panel_update = now;
      UpdatePanel();
     }
  }

//+------------------------------------------------------------------+
//| Chart Event Handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   // Pause / Resume Toggle Button
   if(sparam == PANEL_PREFIX + "BtnPause")
     {
      g_is_paused = !g_is_paused;
      PrintFormat("Zerith OneShot: Execution %s by user.", (g_is_paused ? "PAUSED" : "RESUMED"));
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      UpdatePanel();
      return;
     }

   // Close All Trades Button
   if(sparam == PANEL_PREFIX + "BtnCloseAll")
     {
      if(MessageBox("Are you sure you want to close ALL Zerith OneShot positions?",
                    "Zerith OneShot Confirmation", MB_YESNO | MB_ICONQUESTION) == IDYES)
        {
         CloseAllStrategies("UserManualCloseAll");
         UpdatePanel();
        }
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      return;
     }

   // Information Dialog Button
   if(sparam == PANEL_PREFIX + "BtnInfo")
     {
      MessageBox("Zerith OneShot MT5 v1.00\n\n"
                 "Multi-Strategy DeMarker Momentum Engine with First-Instinct Execution.\n"
                 "Features 12 independent session strategies, strict 1-trade-per-session locking,\n"
                 "fresh cross momentum validation, and institutional risk management.\n\n"
                 "Copyright 2026, Zerith EA",
                 "About Zerith OneShot", MB_OK | MB_ICONINFORMATION);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      return;
     }

   // Panel Close Button (Removes EA)
   if(sparam == PANEL_PREFIX + "Close")
     {
      if(MessageBox("Remove Zerith OneShot from the chart?",
                    "Zerith OneShot", MB_YESNO | MB_ICONQUESTION) == IDYES)
        {
         ExpertRemove();
        }
      return;
     }

   // Minimize / Expand Panel Button
   if(sparam == PANEL_PREFIX + "MinMax")
     {
      g_panel_collapsed = !g_panel_collapsed;
      long visible_timeframe = (g_panel_collapsed ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);

      for(int i = 0; i < 48; i++)
         ObjectSetInteger(0, PANEL_PREFIX + "Line_" + IntegerToString(i), OBJPROP_TIMEFRAMES, visible_timeframe);

      ObjectSetInteger(0, PANEL_PREFIX + "ClientBack", OBJPROP_TIMEFRAMES, visible_timeframe);
      ObjectSetInteger(0, PANEL_PREFIX + "BtnPause",    OBJPROP_TIMEFRAMES, visible_timeframe);
      ObjectSetInteger(0, PANEL_PREFIX + "BtnCloseAll", OBJPROP_TIMEFRAMES, visible_timeframe);
      ObjectSetInteger(0, PANEL_PREFIX + "BtnInfo",     OBJPROP_TIMEFRAMES, visible_timeframe);

      if(g_panel_collapsed)
        {
         ObjectSetInteger(0, PANEL_PREFIX + "Back",   OBJPROP_YSIZE, 26);
         ObjectSetInteger(0, PANEL_PREFIX + "Border", OBJPROP_YSIZE, 28);
        }
      else
        {
         ObjectSetInteger(0, PANEL_PREFIX + "Back",   OBJPROP_YSIZE, 468);
         ObjectSetInteger(0, PANEL_PREFIX + "Border", OBJPROP_YSIZE, 470);
        }

      ObjectSetString(0, sparam, OBJPROP_TEXT, (g_panel_collapsed ? "+" : "-"));
      ChartRedraw();
      return;
     }
  }
//+------------------------------------------------------------------+
