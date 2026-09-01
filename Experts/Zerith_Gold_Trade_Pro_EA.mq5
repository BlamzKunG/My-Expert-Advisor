//+------------------------------------------------------------------+
//|                                   Zerith_Gold_Trade_Pro_EA.mq5   |
//|               Zerith Series - Gold Daily Breakout Pro MT5        |
//|                             https://www.mql5.com                 |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / Wim Schrynemakers Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.32"
#property description "Zerith Gold Trade Pro MT5 - Multi-Strategy Daily Support & Resistance Breakout on Gold"
#property description "Pure Price Action Swing High/Low Breakout with Dynamic Trailing Stop & Drawdown Protection"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_LOT_MODE
  {
   LOT_MODE_FIXED=0,         // Fixed Lot Size
   LOT_MODE_PER_BALANCE=1,   // Lot Per Balance Step (e.g. 0.01 per $600)
   LOT_MODE_RISK_PERCENT=2   // Risk Percent Per Trade (Based on SL)
  };

//--- Sub-Strategy Configuration Struct
struct SStrategyConfig
  {
   string   name;
   bool     enabled;
   ulong    magic;
   int      left_bars;
   int      right_bars;
   int      max_lookback;
   double   offset_points;
   double   tp_points;
   double   sl_points;
   double   trail_start_points;
   double   trail_dist_points;
   double   trail_step_points;
   int      expiry_hours;
  };

//--- Input Parameters
input group ">>>> 1. Money Management & Lot Sizing"
input ENUM_LOT_MODE     InpLotMode              = LOT_MODE_PER_BALANCE; // Lot Sizing Method
input double            InpStartLots            = 0.01;                 // Fixed Lot Size
input double            InpLotPerBalanceStep    = 600.0;                // Balance Step for 0.01 Lot ($)
input double            InpRiskPercent          = 1.5;                  // Risk % Per Trade (if Risk Mode)
input double            InpMaxSpreadPoints      = 500.0;                // Max Allowed Spread (Points, 500 = 50 pips)
input int               InpSlippage             = 10;                   // Max Slippage (Points)

input group ">>>> 2. Multi-Strategy Activation (7 Daily Breakout Modules)"
input bool              InpRunStrat1            = true;                 // Strategy 1 (Fast Momentum Breakout)
input bool              InpRunStrat2            = true;                 // Strategy 2 (Core Daily Breakout)
input bool              InpRunStrat3            = true;                 // Strategy 3 (Medium Swing Breakout)
input bool              InpRunStrat4            = true;                 // Strategy 4 (Major Resistance/Support)
input bool              InpRunStrat5            = true;                 // Strategy 5 (Short-Cycle Breakout)
input bool              InpRunStrat6            = true;                 // Strategy 6 (Volatility Swing Breakout)
input bool              InpRunStrat7            = true;                 // Strategy 7 (Long-Term Structural Breakout)
input ulong             InpBaseMagicNumber      = 880000;               // Base Magic Number (880001 - 880007)
input string            InpTradeCommentPrefix   = "Zerith_GoldPro";     // Trade Comment Prefix
input int               InpPendingExpiryHours   = 24;                   // Default Pending Order Lifetime (Hours, 0=Module Def)

input group ">>>> 3. Drawdown & Capital Protection (DD Protection)"
input bool              InpEnableDDProtection         = true;           // Enable Drawdown & Capital Protection
input double            InpMaxTotalDDPercent          = 15.0;           // Max Total Floating DD % (Relative to Balance)
input double            InpMaxDailyLossPercent        = 5.0;            // Max Daily Loss % (Realized + Floating)
input double            InpMaxDDMoney                 = 0.0;            // Max Floating Loss in Currency (0 = Disabled)
input bool              InpCloseAllOnDDBreach         = true;           // Close All Positions & Orders on DD Breach
input bool              InpPauseTradingAfterDDBreach  = true;           // Pause Trading for Remainder of Day on DD Breach

input group ">>>> 4. Trailing Stop & Exit Execution"
input bool              InpEnableTrailing             = true;           // Enable Dynamic Trailing Stop
input bool              InpEnableBreakEven            = true;           // Enable Auto Break-Even

//--- Global Objects & Strategy Definitions
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_ord;
CAccountInfo   g_acc;
CSymbolInfo    g_sym;

SStrategyConfig g_strategies[7];

// DD Protection Tracking
datetime       g_last_daily_reset_date    = 0;
datetime       g_last_bar_time            = 0;
bool           g_dd_protection_tripped    = false;
double         g_current_floating_loss    = 0.0;
double         g_current_floating_dd_pct  = 0.0;
double         g_today_realized_loss      = 0.0;
double         g_today_total_loss_pct     = 0.0;

//+------------------------------------------------------------------+
//| Initialize Strategy Configurations                               |
//+------------------------------------------------------------------+
void InitStrategies()
  {
   // Strategy 1 (Fast Momentum Breakout)
   g_strategies[0].name               = "Strat_1_Fast";
   g_strategies[0].enabled            = InpRunStrat1;
   g_strategies[0].magic              = InpBaseMagicNumber + 1;
   g_strategies[0].left_bars          = 4;
   g_strategies[0].right_bars         = 2;
   g_strategies[0].max_lookback       = 160;
   g_strategies[0].offset_points      = 150.0;
   g_strategies[0].tp_points          = 1300.0;
   g_strategies[0].sl_points          = 1700.0;
   g_strategies[0].trail_start_points = 800.0;
   g_strategies[0].trail_dist_points  = 500.0;
   g_strategies[0].trail_step_points  = 50.0;
   g_strategies[0].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;

   // Strategy 2 (Core Daily Breakout)
   g_strategies[1].name               = "Strat_2_Core";
   g_strategies[1].enabled            = InpRunStrat2;
   g_strategies[1].magic              = InpBaseMagicNumber + 2;
   g_strategies[1].left_bars          = 18;
   g_strategies[1].right_bars         = 3;
   g_strategies[1].max_lookback       = 180;
   g_strategies[1].offset_points      = 900.0;
   g_strategies[1].tp_points          = 1200.0;
   g_strategies[1].sl_points          = 1800.0;
   g_strategies[1].trail_start_points = 750.0;
   g_strategies[1].trail_dist_points  = 600.0;
   g_strategies[1].trail_step_points  = 50.0;
   g_strategies[1].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;

   // Strategy 3 (Medium Swing Breakout)
   g_strategies[2].name               = "Strat_3_Medium";
   g_strategies[2].enabled            = InpRunStrat3;
   g_strategies[2].magic              = InpBaseMagicNumber + 3;
   g_strategies[2].left_bars          = 10;
   g_strategies[2].right_bars         = 2;
   g_strategies[2].max_lookback       = 120;
   g_strategies[2].offset_points      = 300.0;
   g_strategies[2].tp_points          = 1400.0;
   g_strategies[2].sl_points          = 1600.0;
   g_strategies[2].trail_start_points = 700.0;
   g_strategies[2].trail_dist_points  = 500.0;
   g_strategies[2].trail_step_points  = 50.0;
   g_strategies[2].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;

   // Strategy 4 (Major Resistance/Support)
   g_strategies[3].name               = "Strat_4_Major";
   g_strategies[3].enabled            = InpRunStrat4;
   g_strategies[3].magic              = InpBaseMagicNumber + 4;
   g_strategies[3].left_bars          = 24;
   g_strategies[3].right_bars         = 4;
   g_strategies[3].max_lookback       = 200;
   g_strategies[3].offset_points      = 1200.0;
   g_strategies[3].tp_points          = 1500.0;
   g_strategies[3].sl_points          = 2000.0;
   g_strategies[3].trail_start_points = 900.0;
   g_strategies[3].trail_dist_points  = 600.0;
   g_strategies[3].trail_step_points  = 50.0;
   g_strategies[3].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;

   // Strategy 5 (Short-Cycle Breakout)
   g_strategies[4].name               = "Strat_5_Short";
   g_strategies[4].enabled            = InpRunStrat5;
   g_strategies[4].magic              = InpBaseMagicNumber + 5;
   g_strategies[4].left_bars          = 6;
   g_strategies[4].right_bars         = 2;
   g_strategies[4].max_lookback       = 100;
   g_strategies[4].offset_points      = 200.0;
   g_strategies[4].tp_points          = 1100.0;
   g_strategies[4].sl_points          = 1500.0;
   g_strategies[4].trail_start_points = 600.0;
   g_strategies[4].trail_dist_points  = 400.0;
   g_strategies[4].trail_step_points  = 50.0;
   g_strategies[4].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;

   // Strategy 6 (Volatility Swing Breakout)
   g_strategies[5].name               = "Strat_6_Vol";
   g_strategies[5].enabled            = InpRunStrat6;
   g_strategies[5].magic              = InpBaseMagicNumber + 6;
   g_strategies[5].left_bars          = 14;
   g_strategies[5].right_bars         = 3;
   g_strategies[5].max_lookback       = 150;
   g_strategies[5].offset_points      = 600.0;
   g_strategies[5].tp_points          = 1300.0;
   g_strategies[5].sl_points          = 1900.0;
   g_strategies[5].trail_start_points = 800.0;
   g_strategies[5].trail_dist_points  = 550.0;
   g_strategies[5].trail_step_points  = 50.0;
   g_strategies[5].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;

   // Strategy 7 (Long-Term Structural Breakout)
   g_strategies[6].name               = "Strat_7_Macro";
   g_strategies[6].enabled            = InpRunStrat7;
   g_strategies[6].magic              = InpBaseMagicNumber + 7;
   g_strategies[6].left_bars          = 30;
   g_strategies[6].right_bars         = 5;
   g_strategies[6].max_lookback       = 250;
   g_strategies[6].offset_points      = 1500.0;
   g_strategies[6].tp_points          = 1800.0;
   g_strategies[6].sl_points          = 2200.0;
   g_strategies[6].trail_start_points = 1000.0;
   g_strategies[6].trail_dist_points  = 700.0;
   g_strategies[6].trail_step_points  = 50.0;
   g_strategies[6].expiry_hours       = (InpPendingExpiryHours > 0) ? InpPendingExpiryHours : 24;
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Selected Mode & Strategy SL          |
//+------------------------------------------------------------------+
double CalculateOrderLot(double sl_points)
  {
   double balance = g_acc.Balance();
   double calculated_lot = InpStartLots;

   switch(InpLotMode)
     {
      case LOT_MODE_FIXED:
         calculated_lot = InpStartLots;
         break;

      case LOT_MODE_PER_BALANCE:
         if(InpLotPerBalanceStep > 0.0)
            calculated_lot = (balance / InpLotPerBalanceStep) * 0.01;
         break;

      case LOT_MODE_RISK_PERCENT:
         if(sl_points > 0.0)
           {
            double risk_money = balance * (InpRiskPercent / 100.0);
            double tick_value = g_sym.TickValue();
            double tick_size  = g_sym.TickSize();
            double point      = g_sym.Point();

            if(tick_size > 0.0 && tick_value > 0.0)
              {
               double loss_per_lot = (sl_points * point / tick_size) * tick_value;
               if(loss_per_lot > 0.0)
                  calculated_lot = risk_money / loss_per_lot;
              }
           }
         break;
     }

   double min_lot = g_sym.LotsMin();
   double max_lot = g_sym.LotsMax();
   double step    = g_sym.LotsStep();
   if(step <= 0.0) step = 0.01;

   calculated_lot = MathMax(min_lot, MathMin(max_lot, calculated_lot));
   return MathFloor(calculated_lot / step) * step;
  }

//+------------------------------------------------------------------+
//| Close All Positions and Delete Pending Orders for Zerith GoldPro |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders(string reason)
  {
   PrintFormat("🚨 [Capital Protection] Executing Emergency Close! Reason: %s", reason);

   // 1. Close Open Positions for all sub-strategies
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() == _Symbol && g_pos.Magic() >= InpBaseMagicNumber && g_pos.Magic() <= InpBaseMagicNumber + 7)
        {
         ulong ticket = g_pos.Ticket();
         g_trade.PositionClose(ticket);
        }
     }

   // 2. Delete Pending Orders for all sub-strategies
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Symbol() == _Symbol && g_ord.Magic() >= InpBaseMagicNumber && g_ord.Magic() <= InpBaseMagicNumber + 7)
        {
         ulong ticket = g_ord.Ticket();
         g_trade.OrderDelete(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Check and Enforce Drawdown & Daily Capital Protection            |
//+------------------------------------------------------------------+
void CheckAndEnforceDrawdownProtection()
  {
   datetime now = TimeCurrent();
   string today_str = TimeToString(now, TIME_DATE);
   datetime today_midnight = StringToTime(today_str + " 00:00");

   // Daily Reset at midnight 00:00
   if(g_last_daily_reset_date != today_midnight)
     {
      g_last_daily_reset_date = today_midnight;
      g_dd_protection_tripped = false;
     }

   double balance = g_acc.Balance();
   if(balance <= 0.0) return;

   // 1. Calculate Current Floating P/L across all 7 strategies
   double floating_pl = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() == _Symbol && g_pos.Magic() >= InpBaseMagicNumber && g_pos.Magic() <= InpBaseMagicNumber + 7)
        {
         floating_pl += g_pos.Profit() + g_pos.Swap();
        }
     }

   g_current_floating_loss   = (floating_pl < 0.0) ? MathAbs(floating_pl) : 0.0;
   g_current_floating_dd_pct = (g_current_floating_loss / balance) * 100.0;

   // 2. Calculate Realized P/L for Today (from 00:00 to now)
   double today_realized_pl = 0.0;
   if(HistorySelect(today_midnight, now))
     {
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
        {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket == 0) continue;
         ulong deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         if(deal_magic < InpBaseMagicNumber || deal_magic > InpBaseMagicNumber + 7) continue;
         if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         today_realized_pl += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
        }
     }

   g_today_realized_loss = (today_realized_pl < 0.0) ? MathAbs(today_realized_pl) : 0.0;
   double total_today_loss = g_today_realized_loss + g_current_floating_loss;
   g_today_total_loss_pct = (total_today_loss / balance) * 100.0;

   if(!InpEnableDDProtection)
      return;

   // 3. Evaluate Breach Conditions
   bool breach_total_dd = (InpMaxTotalDDPercent > 0.0 && g_current_floating_dd_pct >= InpMaxTotalDDPercent);
   bool breach_money_dd = (InpMaxDDMoney > 0.0 && g_current_floating_loss >= InpMaxDDMoney);
   bool breach_daily_dd = (InpMaxDailyLossPercent > 0.0 && g_today_total_loss_pct >= InpMaxDailyLossPercent);

   if(breach_total_dd || breach_money_dd || breach_daily_dd)
     {
      if(!g_dd_protection_tripped)
        {
         string reason = "";
         if(breach_total_dd)
            reason = StringFormat("Total Floating DD reached %.2f%% (Limit: %.2f%%)", g_current_floating_dd_pct, InpMaxTotalDDPercent);
         else if(breach_money_dd)
            reason = StringFormat("Floating Loss reached $%.2f (Limit: $%.2f)", g_current_floating_loss, InpMaxDDMoney);
         else if(breach_daily_dd)
            reason = StringFormat("Daily Total Loss reached %.2f%% (Limit: %.2f%%)", g_today_total_loss_pct, InpMaxDailyLossPercent);

         g_dd_protection_tripped = true;

         if(InpCloseAllOnDDBreach)
            CloseAllPositionsAndOrders(reason);
        }
     }
  }

//+------------------------------------------------------------------+
//| Find Daily Swing High Resistance Level for a Sub-Strategy        |
//+------------------------------------------------------------------+
double FindDailySwingHigh(int left_bars, int right_bars, int max_lookback)
  {
   int start_bar = right_bars + 1;
   for(int bar = start_bar; bar <= max_lookback; bar++)
     {
      double candidate_high = iHigh(_Symbol, PERIOD_D1, bar);
      if(candidate_high <= 0.0) continue;

      bool is_swing_high = true;

      // Check left bars
      for(int l = 1; l <= left_bars; l++)
        {
         if(iHigh(_Symbol, PERIOD_D1, bar + l) >= candidate_high)
           {
            is_swing_high = false;
            break;
           }
        }
      if(!is_swing_high) continue;

      // Check right bars
      for(int r = 1; r <= right_bars; r++)
        {
         if(iHigh(_Symbol, PERIOD_D1, bar - r) >= candidate_high)
           {
            is_swing_high = false;
            break;
           }
        }
      if(!is_swing_high) continue;

      // Ensure this swing high is above all intermediate bars up to bar 1
      double highest_intermediate = 0.0;
      for(int k = 1; k < bar; k++)
        {
         double h = iHigh(_Symbol, PERIOD_D1, k);
         if(h > highest_intermediate)
            highest_intermediate = h;
        }

      if(candidate_high >= highest_intermediate && candidate_high > g_sym.Ask())
        {
         return candidate_high;
        }
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Find Daily Swing Low Support Level for a Sub-Strategy            |
//+------------------------------------------------------------------+
double FindDailySwingLow(int left_bars, int right_bars, int max_lookback)
  {
   int start_bar = right_bars + 1;
   for(int bar = start_bar; bar <= max_lookback; bar++)
     {
      double candidate_low = iLow(_Symbol, PERIOD_D1, bar);
      if(candidate_low <= 0.0) continue;

      bool is_swing_low = true;

      // Check left bars
      for(int l = 1; l <= left_bars; l++)
        {
         if(iLow(_Symbol, PERIOD_D1, bar + l) <= candidate_low)
           {
            is_swing_low = false;
            break;
           }
        }
      if(!is_swing_low) continue;

      // Check right bars
      for(int r = 1; r <= right_bars; r++)
        {
         if(iLow(_Symbol, PERIOD_D1, bar - r) <= candidate_low)
           {
            is_swing_low = false;
            break;
           }
        }
      if(!is_swing_low) continue;

      // Ensure this swing low is below all intermediate bars up to bar 1
      double lowest_intermediate = DBL_MAX;
      for(int k = 1; k < bar; k++)
        {
         double l = iLow(_Symbol, PERIOD_D1, k);
         if(l < lowest_intermediate)
            lowest_intermediate = l;
        }

      if(candidate_low <= lowest_intermediate && candidate_low < g_sym.Bid())
        {
         return candidate_low;
        }
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Helper Checkers for Positions and Specific Order Types by Magic  |
//+------------------------------------------------------------------+
bool HasOpenPosition(ulong magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() == _Symbol && g_pos.Magic() == magic)
         return true;
     }
   return false;
  }

bool HasBuyStopOrder(ulong magic, ulong &ticket, double &price)
  {
   ticket = 0;
   price  = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Symbol() == _Symbol && g_ord.Magic() == magic && g_ord.OrderType() == ORDER_TYPE_BUY_STOP)
        {
         ticket = g_ord.Ticket();
         price  = g_ord.PriceOpen();
         return true;
        }
     }
   return false;
  }

bool HasSellStopOrder(ulong magic, ulong &ticket, double &price)
  {
   ticket = 0;
   price  = 0.0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Symbol() == _Symbol && g_ord.Magic() == magic && g_ord.OrderType() == ORDER_TYPE_SELL_STOP)
        {
         ticket = g_ord.Ticket();
         price  = g_ord.PriceOpen();
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Cancel Pending Orders for Strategy if Position is already Active |
//+------------------------------------------------------------------+
void HandleOCOAndCleanup(ulong magic)
  {
   if(HasOpenPosition(magic))
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!g_ord.SelectByIndex(i)) continue;
         if(g_ord.Symbol() == _Symbol && g_ord.Magic() == magic)
           {
            ulong t = g_ord.Ticket();
            g_trade.OrderDelete(t);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage Break-Even and Dynamic Trailing Stop for Open Positions   |
//+------------------------------------------------------------------+
void ManageTrailingStops()
  {
   if(!InpEnableTrailing && !InpEnableBreakEven)
      return;

   double point  = g_sym.Point();
   int    digits = g_sym.Digits();

   for(int s = 0; s < 7; s++)
     {
      if(!g_strategies[s].enabled) continue;

      ulong magic       = g_strategies[s].magic;
      double trail_start = g_strategies[s].trail_start_points * point;
      double trail_dist  = g_strategies[s].trail_dist_points * point;
      double trail_step  = g_strategies[s].trail_step_points * point;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol() != _Symbol || g_pos.Magic() != magic) continue;

         ulong ticket       = g_pos.Ticket();
         double open_price  = g_pos.PriceOpen();
         double current_sl  = g_pos.StopLoss();
         double current_tp  = g_pos.TakeProfit();
         ENUM_POSITION_TYPE type = g_pos.PositionType();

         if(type == POSITION_TYPE_BUY)
           {
            double current_profit_pts = (g_sym.Bid() - open_price);

            // 1. Break-Even
            if(InpEnableBreakEven && current_profit_pts >= trail_start && (current_sl < open_price || current_sl == 0.0))
              {
               double new_sl = NormalizeDouble(open_price + 10.0 * point, digits);
               g_trade.PositionModify(ticket, new_sl, current_tp);
               PrintFormat("🔒 [%s] BUY #%I64u Moved to Break-Even at %.2f", g_strategies[s].name, ticket, new_sl);
              }

            // 2. Trailing Stop
            if(InpEnableTrailing && current_profit_pts >= trail_start)
              {
               double proposed_sl = NormalizeDouble(g_sym.Bid() - trail_dist, digits);
               if(proposed_sl > current_sl + trail_step && proposed_sl > open_price)
                 {
                  g_trade.PositionModify(ticket, proposed_sl, current_tp);
                  PrintFormat("📈 [%s] BUY #%I64u Trailing Stop adjusted to %.2f", g_strategies[s].name, ticket, proposed_sl);
                 }
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double current_profit_pts = (open_price - g_sym.Ask());

            // 1. Break-Even
            if(InpEnableBreakEven && current_profit_pts >= trail_start && (current_sl > open_price || current_sl == 0.0))
              {
               double new_sl = NormalizeDouble(open_price - 10.0 * point, digits);
               g_trade.PositionModify(ticket, new_sl, current_tp);
               PrintFormat("🔒 [%s] SELL #%I64u Moved to Break-Even at %.2f", g_strategies[s].name, ticket, new_sl);
              }

            // 2. Trailing Stop
            if(InpEnableTrailing && current_profit_pts >= trail_start)
              {
               double proposed_sl = NormalizeDouble(g_sym.Ask() + trail_dist, digits);
               if((current_sl == 0.0 || proposed_sl < current_sl - trail_step) && proposed_sl < open_price)
                 {
                  g_trade.PositionModify(ticket, proposed_sl, current_tp);
                  PrintFormat("📈 [%s] SELL #%I64u Trailing Stop adjusted to %.2f", g_strategies[s].name, ticket, proposed_sl);
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute Daily Breakout Signal Logic for All 7 Sub-Strategies     |
//+------------------------------------------------------------------+
void ExecuteDailyBreakoutStrategies()
  {
   if(g_dd_protection_tripped && InpPauseTradingAfterDDBreach)
      return;

   // Account pending order limit safety guard
   long max_orders_allowed = AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if(max_orders_allowed > 0 && (OrdersTotal() + PositionsTotal()) >= (max_orders_allowed - 4))
     {
      PrintFormat("⚠️ [Order Guard] Account Orders Limit approached (%d / %I64d). Skipping new pending orders.",
                  OrdersTotal() + PositionsTotal(), max_orders_allowed);
      return;
     }

   double point  = g_sym.Point();
   int    digits = g_sym.Digits();

   // Spread Check
   double spread = (g_sym.Ask() - g_sym.Bid()) / point;
   if(spread > InpMaxSpreadPoints)
      return;

   for(int s = 0; s < 7; s++)
     {
      if(!g_strategies[s].enabled) continue;

      ulong magic = g_strategies[s].magic;

      // If this strategy already has an active open position, perform OCO cleanup and skip
      if(HasOpenPosition(magic))
        {
         HandleOCOAndCleanup(magic);
         continue;
        }

      double volume = CalculateOrderLot(g_strategies[s].sl_points);
      if(volume <= 0.0) continue;

      datetime expiry_time = TimeCurrent() + g_strategies[s].expiry_hours * 3600;

      // 1. Process Buy Stop
      ulong  existing_buy_ticket = 0;
      double existing_buy_price  = 0.0;
      bool   has_buy_stop = HasBuyStopOrder(magic, existing_buy_ticket, existing_buy_price);

      double swing_high = FindDailySwingHigh(g_strategies[s].left_bars, g_strategies[s].right_bars, g_strategies[s].max_lookback);
      if(swing_high > 0.0)
        {
         double buy_stop_price = NormalizeDouble(swing_high + g_strategies[s].offset_points * point, digits);
         if(buy_stop_price > g_sym.Ask())
           {
            // If existing order price changed significantly or no order exists, update it
            if(!has_buy_stop)
              {
               double buy_tp = (g_strategies[s].tp_points > 0.0) ? NormalizeDouble(buy_stop_price + g_strategies[s].tp_points * point, digits) : 0.0;
               double buy_sl = (g_strategies[s].sl_points > 0.0) ? NormalizeDouble(buy_stop_price - g_strategies[s].sl_points * point, digits) : 0.0;
               string comment = StringFormat("%s_%s [BS]", InpTradeCommentPrefix, g_strategies[s].name);

               if(g_trade.BuyStop(volume, buy_stop_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_SPECIFIED, expiry_time, comment))
                 {
                  PrintFormat("👑 [Zerith GoldPro] Placed BUY STOP (%s) at %.2f (Daily High: %.2f) Lot: %.2f TP: %.2f SL: %.2f",
                              g_strategies[s].name, buy_stop_price, swing_high, volume, buy_tp, buy_sl);
                 }
              }
            else if(MathAbs(existing_buy_price - buy_stop_price) > 50.0 * point)
              {
               // Level moved -> replace order
               g_trade.OrderDelete(existing_buy_ticket);
              }
           }
        }
      else if(has_buy_stop)
        {
         // Swing High invalid -> clean stale order
         g_trade.OrderDelete(existing_buy_ticket);
        }

      // 2. Process Sell Stop
      ulong  existing_sell_ticket = 0;
      double existing_sell_price  = 0.0;
      bool   has_sell_stop = HasSellStopOrder(magic, existing_sell_ticket, existing_sell_price);

      double swing_low = FindDailySwingLow(g_strategies[s].left_bars, g_strategies[s].right_bars, g_strategies[s].max_lookback);
      if(swing_low > 0.0)
        {
         double sell_stop_price = NormalizeDouble(swing_low - g_strategies[s].offset_points * point, digits);
         if(sell_stop_price < g_sym.Bid())
           {
            if(!has_sell_stop)
              {
               double sell_tp = (g_strategies[s].tp_points > 0.0) ? NormalizeDouble(sell_stop_price - g_strategies[s].tp_points * point, digits) : 0.0;
               double sell_sl = (g_strategies[s].sl_points > 0.0) ? NormalizeDouble(sell_stop_price + g_strategies[s].sl_points * point, digits) : 0.0;
               string comment = StringFormat("%s_%s [SS]", InpTradeCommentPrefix, g_strategies[s].name);

               if(g_trade.SellStop(volume, sell_stop_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_SPECIFIED, expiry_time, comment))
                 {
                  PrintFormat("👑 [Zerith GoldPro] Placed SELL STOP (%s) at %.2f (Daily Low: %.2f) Lot: %.2f TP: %.2f SL: %.2f",
                              g_strategies[s].name, sell_stop_price, swing_low, volume, sell_tp, sell_sl);
                 }
              }
            else if(MathAbs(existing_sell_price - sell_stop_price) > 50.0 * point)
              {
               // Level moved -> replace order
               g_trade.OrderDelete(existing_sell_ticket);
              }
           }
        }
      else if(has_sell_stop)
        {
         // Swing Low invalid -> clean stale order
         g_trade.OrderDelete(existing_sell_ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Chart Information Dashboard                                      |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   int open_positions = 0;
   int pending_orders = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() == _Symbol && g_pos.Magic() >= InpBaseMagicNumber && g_pos.Magic() <= InpBaseMagicNumber + 7)
         open_positions++;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Symbol() == _Symbol && g_ord.Magic() >= InpBaseMagicNumber && g_ord.Magic() <= InpBaseMagicNumber + 7)
         pending_orders++;
     }

   int active_modules = 0;
   for(int s = 0; s < 7; s++)
     {
      if(g_strategies[s].enabled) active_modules++;
     }

   string dd_status = "OFF";
   if(InpEnableDDProtection)
     {
      dd_status = g_dd_protection_tripped ? "TRIPPED (TRADING PAUSED)" : "ACTIVE (NORMAL)";
     }

   string text = StringFormat("--- ZERITH GOLD TRADE PRO EA (MT5) ---\n"
                              "Trading Status: %s\n"
                              "Active Modules: %d / 7 Daily Breakout Modules\n"
                              "Lot Sizing Mode: %s (Base Lot: %.2f)\n"
                              "Active Positions: %d | Pending Orders: %d\n"
                              "Trailing Stop: %s | Break-Even: %s\n"
                              "------------------------------------------\n"
                              "DD Protection: %s\n"
                              "Current Floating DD: $%.2f (%.2f%% / Max %.1f%%)\n"
                              "Today Total Loss: %.2f%% (Max Daily %.1f%%)\n"
                              "Account Equity: $%.2f | Balance: $%.2f",
                              (g_dd_protection_tripped ? "PAUSED (DD LIMIT BREACH)" : "ACTIVE & SCANNING"),
                              active_modules,
                              EnumToString(InpLotMode), CalculateOrderLot(1500.0),
                              open_positions, pending_orders,
                              (InpEnableTrailing ? "ENABLED" : "OFF"), (InpEnableBreakEven ? "ENABLED" : "OFF"),
                              dd_status,
                              g_current_floating_loss, g_current_floating_dd_pct, InpMaxTotalDDPercent,
                              g_today_total_loss_pct, InpMaxDailyLossPercent,
                              g_acc.Equity(), g_acc.Balance());
   Comment(text);
  }

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_sym.Name(_Symbol))
     {
      Print("Symbol initialization failed!");
      return INIT_FAILED;
     }

   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   InitStrategies();

   g_last_daily_reset_date = 0;
   g_last_bar_time         = 0;
   g_dd_protection_tripped = false;

   Print("Zerith Gold Trade Pro EA MT5 v1.32 successfully initialized.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_sym.RefreshRates();

   // 1. Enforce Drawdown & Capital Protection
   CheckAndEnforceDrawdownProtection();

   // 2. Manage Trailing Stop & Break-Even on Open Positions (Every tick)
   ManageTrailingStops();

   // 3. Scan & Place Daily Swing High/Low Breakout Orders (Evaluated on new bar or state change)
   datetime current_bar_time = iTime(_Symbol, PERIOD_M1, 0);
   if(g_last_bar_time != current_bar_time)
     {
      g_last_bar_time = current_bar_time;
      ExecuteDailyBreakoutStrategies();
     }

   // 4. Render Chart Dashboard
   DrawDashboard();
  }
//+------------------------------------------------------------------+
