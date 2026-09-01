//+------------------------------------------------------------------+
//|                                     Zerith_Gold_Trade_Pro_EA.mq5 |
//|                 Zerith Series / Wim Schrynemakers Architecture   |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / Wim Schrynemakers Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.34"
#property description "Zerith Gold Trade Pro MT5 - Faithful Port of Gold Trade Pro v1.31"
#property description "7-Strategy Daily Support & Resistance Breakout with Virtual Expiration & Trailing Stop"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_LOT_MODE { LOT_MODE_FIXED=0, LOT_MODE_PER_BALANCE=1, LOT_MODE_RISK_PERCENT=2 };

//--- Inputs
input group ">>>> 1. Money Management & Lot Sizing"
input ENUM_LOT_MODE     InpLotMode              = LOT_MODE_PER_BALANCE; // Lot Sizing Method
input double            InpStartLots            = 0.01;                 // Fixed Lot Size / Base Lot
input double            InpLotPerBalanceStep    = 600.0;                // Balance Step for 0.01 Lot ($)
input double            InpRiskPercent          = 2.0;                  // Risk % Per Trade (if Risk Mode)
input double            InpMaxSpreadPoints      = 500.0;                // Max Allowed Spread (Points, 500 = 50 pips)
input int               InpSlippage             = 10;                   // Max Slippage (Points)

input group ">>>> 2. Multi-Strategy Activation (7 Daily Breakout Modules)"
input bool              InpRunStratA            = true;                 // Strategy A (Run Strategy 1)
input bool              InpRunStratC            = true;                 // Strategy C (Run Strategy 2)
input bool              InpRunStratD            = true;                 // Strategy D (Run Strategy 3)
input bool              InpRunStratE            = true;                 // Strategy E (Run Strategy 4)
input bool              InpRunStratF            = true;                 // Strategy F (Run Strategy 5)
input bool              InpRunStratG            = true;                 // Strategy G (Run Strategy 6)
input bool              InpRunStratH            = true;                 // Strategy H (Run Strategy 7)
input ulong             InpBaseMagicNumber      = 1000;                 // Base Magic Number (Original Default: 1000)
input string            InpTradeCommentPrefix   = "Gold Trade Pro";     // Trade Comment Prefix

input group ">>>> 3. Drawdown & Capital Protection (DD Protection)"
input bool              InpEnableDDProtection         = true;           // Enable Drawdown & Capital Protection
input double            InpMaxTotalDDPercent          = 15.0;           // Max Total Floating DD % (Relative to Balance)
input double            InpMaxDailyLossPercent        = 5.0;            // Max Daily Loss % (Realized + Floating)
input double            InpMaxDDMoney                 = 0.0;            // Max Floating Loss in Currency (0 = Disabled)
input bool              InpCloseAllOnDDBreach         = true;           // Close All Positions & Orders on DD Breach
input bool              InpPauseTradingAfterDDBreach  = true;           // Pause Trading for Remainder of Day on DD Breach

input group ">>>> 4. Trailing Stop Execution"
input bool              InpEnableTrailing             = true;           // Enable Trailing Stop Engine

//--- Global Objects & State
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_order;
CAccountInfo   g_account;
CSymbolInfo    g_sym;

double         g_start_day_balance = 0.0;
int            g_current_day       = -1;
bool           g_trading_paused    = false;

struct SStrategyConfig
  {
   string   name;              // Strategy label
   bool     enabled;           // From input
   ulong    magic;             // BaseMagic + offset
   int      left_bars;         // Fractal left bars
   int      right_bars;        // Fractal right bars 
   int      max_lookback;      // Max bars to scan
   double   detect_offset;     // Min distance swing must be from price (in points)
   double   buy_entry_offset;  // BuyStop offset from swing high (negative = below)
   double   sell_entry_offset; // SellStop offset formula: swing_low - this*point
   double   dup_tolerance;     // Tolerance for duplicate order detection (in points)
   double   sl_points;         // Stop Loss distance from entry
   double   tp_points;         // Take Profit distance from entry
   double   trail_start;       // Trailing activation AND distance from price for new SL
   double   trail_step;        // Min price movement from reference for trail activation
   double   trail_cap;         // Max SL level relative to entry (cap)
   int      expiry_hours;      // Virtual expiration hours
  };

SStrategyConfig g_strats[7];

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_sym.Name(_Symbol)) return(INIT_FAILED);
   g_sym.Refresh();
   
   g_trade.SetExpertMagicNumber(InpBaseMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // Strategy A (Magic 1001)
   g_strats[0].name              = "A";
   g_strats[0].enabled           = InpRunStratA;
   g_strats[0].magic             = InpBaseMagicNumber + 1;
   g_strats[0].left_bars         = 4;
   g_strats[0].right_bars        = 2;
   g_strats[0].max_lookback      = 160;
   g_strats[0].detect_offset     = 150.0;
   g_strats[0].buy_entry_offset  = -140.0;
   g_strats[0].sell_entry_offset = -290.0;
   g_strats[0].dup_tolerance     = 680.0;
   g_strats[0].expiry_hours      = 408;
   g_strats[0].sl_points         = 1300.0;
   g_strats[0].tp_points         = 1700.0;
   g_strats[0].trail_start       = 800.0;
   g_strats[0].trail_step        = 500.0;
   g_strats[0].trail_cap         = 200.0;

   // Strategy C (Magic 1003)
   g_strats[1].name              = "C";
   g_strats[1].enabled           = InpRunStratC;
   g_strats[1].magic             = InpBaseMagicNumber + 3;
   g_strats[1].left_bars         = 18;
   g_strats[1].right_bars        = 3;
   g_strats[1].max_lookback      = 180;
   g_strats[1].detect_offset     = 900.0;
   g_strats[1].buy_entry_offset  = -130.0;
   g_strats[1].sell_entry_offset = -30.0;
   g_strats[1].dup_tolerance     = 980.0;
   g_strats[1].expiry_hours      = 408;
   g_strats[1].sl_points         = 1200.0;
   g_strats[1].tp_points         = 1800.0;
   g_strats[1].trail_start       = 750.0;
   g_strats[1].trail_step        = 600.0;
   g_strats[1].trail_cap         = 200.0;

   // Strategy D (Magic 1004)
   g_strats[2].name              = "D";
   g_strats[2].enabled           = InpRunStratD;
   g_strats[2].magic             = InpBaseMagicNumber + 4;
   g_strats[2].left_bars         = 4;
   g_strats[2].right_bars        = 2;
   g_strats[2].max_lookback      = 240;
   g_strats[2].detect_offset     = 900.0;
   g_strats[2].buy_entry_offset  = -250.0;
   g_strats[2].sell_entry_offset = -130.0;
   g_strats[2].dup_tolerance     = 680.0;
   g_strats[2].expiry_hours      = 48;
   g_strats[2].sl_points         = 1300.0;
   g_strats[2].tp_points         = 1700.0;
   g_strats[2].trail_start       = 800.0;
   g_strats[2].trail_step        = 500.0;
   g_strats[2].trail_cap         = 200.0;

   // Strategy E (Magic 1005)
   g_strats[3].name              = "E";
   g_strats[3].enabled           = InpRunStratE;
   g_strats[3].magic             = InpBaseMagicNumber + 5;
   g_strats[3].left_bars         = 15;
   g_strats[3].right_bars        = 3;
   g_strats[3].max_lookback      = 230;
   g_strats[3].detect_offset     = 550.0;
   g_strats[3].buy_entry_offset  = -170.0;
   g_strats[3].sell_entry_offset = -70.0;
   g_strats[3].dup_tolerance     = 480.0;
   g_strats[3].expiry_hours      = 480;
   g_strats[3].sl_points         = 600.0;
   g_strats[3].tp_points         = 1700.0;
   g_strats[3].trail_start       = 500.0;
   g_strats[3].trail_step        = 300.0;
   g_strats[3].trail_cap         = 200.0;

   // Strategy F (Magic 1006)
   g_strats[4].name              = "F";
   g_strats[4].enabled           = InpRunStratF;
   g_strats[4].magic             = InpBaseMagicNumber + 6;
   g_strats[4].left_bars         = 12;
   g_strats[4].right_bars        = 2;
   g_strats[4].max_lookback      = 50;
   g_strats[4].detect_offset     = 700.0;
   g_strats[4].buy_entry_offset  = -210.0;
   g_strats[4].sell_entry_offset = -60.0;
   g_strats[4].dup_tolerance     = 30.0;
   g_strats[4].expiry_hours      = 384;
   g_strats[4].sl_points         = 1000.0;
   g_strats[4].tp_points         = 1900.0;
   g_strats[4].trail_start       = 600.0;
   g_strats[4].trail_step        = 500.0;
   g_strats[4].trail_cap         = 1000.0;

   // Strategy G (Magic 1007)
   g_strats[5].name              = "G";
   g_strats[5].enabled           = InpRunStratG;
   g_strats[5].magic             = InpBaseMagicNumber + 7;
   g_strats[5].left_bars         = 17;
   g_strats[5].right_bars        = 2;
   g_strats[5].max_lookback      = 110;
   g_strats[5].detect_offset     = 150.0;
   g_strats[5].buy_entry_offset  = -40.0;
   g_strats[5].sell_entry_offset = -140.0;
   g_strats[5].dup_tolerance     = 280.0;
   g_strats[5].expiry_hours      = 240;
   g_strats[5].sl_points         = 1200.0;
   g_strats[5].tp_points         = 1600.0;
   g_strats[5].trail_start       = 600.0;
   g_strats[5].trail_step        = 200.0;
   g_strats[5].trail_cap         = 4400.0;

   // Strategy H (Magic 1008)
   g_strats[6].name              = "H";
   g_strats[6].enabled           = InpRunStratH;
   g_strats[6].magic             = InpBaseMagicNumber + 8;
   g_strats[6].left_bars         = 7;
   g_strats[6].right_bars        = 2;
   g_strats[6].max_lookback      = 20;
   g_strats[6].detect_offset     = 250.0;
   g_strats[6].buy_entry_offset  = -130.0;
   g_strats[6].sell_entry_offset = -120.0;
   g_strats[6].dup_tolerance     = 980.0;
   g_strats[6].expiry_hours      = 432;
   g_strats[6].sl_points         = 600.0;
   g_strats[6].tp_points         = 4900.0;
   g_strats[6].trail_start       = 600.0;
   g_strats[6].trail_step        = 350.0;
   g_strats[6].trail_cap         = 2000.0;

   MqlDateTime dt;
   TimeCurrent(dt);
   g_current_day = dt.day_of_year;
   g_start_day_balance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("Zerith Gold Trade Pro EA MT5 v1.34 initialized with exact MQ4 v1.31 parameters.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
//| Daily Swing High Detection (ccbsw_10)                            |
//+------------------------------------------------------------------+
double FindDailySwingHigh(int left_bars, int right_bars, int max_lookback, double detect_offset)
  {
   double point = g_sym.Point();
   for(int bar = right_bars + 1; bar <= max_lookback; bar++)
     {
      double candidate = iHigh(_Symbol, PERIOD_D1, bar);
      if(candidate <= 0.0) continue;

      bool fail = false;
      
      // Right bars check
      for(int j = bar - 1; j >= bar - right_bars; j--)
        {
         if(iHigh(_Symbol, PERIOD_D1, j) > candidate) { fail = true; break; }
        }
      if(fail) continue;
      
      // Left bars check
      for(int j = bar + 1; j <= bar + left_bars; j++)
        {
         if(iHigh(_Symbol, PERIOD_D1, j) > candidate) { fail = true; break; }
        }
      if(fail) continue;
      
      // Distance check from current Ask
      if(candidate <= g_sym.Ask() + detect_offset * point) continue;
      
      // Intermediate check: ensure candidate is highest up to today
      double highest_intermediate = 0.0;
      for(int k = 1; k < bar; k++)
        {
         double h = iHigh(_Symbol, PERIOD_D1, k);
         if(h > highest_intermediate) highest_intermediate = h;
        }
      if(candidate < highest_intermediate) continue;
      
      return candidate;
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Daily Swing Low Detection (ccbsw_11)                             |
//+------------------------------------------------------------------+
double FindDailySwingLow(int left_bars, int right_bars, int max_lookback, double detect_offset)
  {
   double point = g_sym.Point();
   for(int bar = right_bars + 1; bar <= max_lookback; bar++)
     {
      double candidate = iLow(_Symbol, PERIOD_D1, bar);
      if(candidate <= 0.0) continue;

      bool fail = false;
      
      // Right bars check
      for(int j = bar - 1; j >= bar - right_bars; j--)
        {
         if(iLow(_Symbol, PERIOD_D1, j) < candidate) { fail = true; break; }
        }
      if(fail) continue;
      
      // Left bars check
      for(int j = bar + 1; j <= bar + left_bars; j++)
        {
         if(iLow(_Symbol, PERIOD_D1, j) < candidate) { fail = true; break; }
        }
      if(fail) continue;
      
      // Distance check from current Bid
      if(candidate >= g_sym.Bid() - detect_offset * point) continue;
      
      // Intermediate check: ensure candidate is lowest up to today
      double lowest_intermediate = DBL_MAX;
      for(int k = 1; k < bar; k++)
        {
         double l = iLow(_Symbol, PERIOD_D1, k);
         if(l < lowest_intermediate) lowest_intermediate = l;
        }
      if(candidate > lowest_intermediate) continue;
      
      return candidate;
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| Lot Sizing Calculation                                           |
//+------------------------------------------------------------------+
double CalculateLots(double sl_points)
  {
   double lot = InpStartLots;
   double min_lot = g_sym.LotsMin();
   double max_lot = g_sym.LotsMax();
   double step = g_sym.LotsStep();
   if(step <= 0.0) step = 0.01;
   
   if(InpLotMode == LOT_MODE_FIXED)
     {
      lot = InpStartLots;
     }
   else if(InpLotMode == LOT_MODE_PER_BALANCE)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      if(InpLotPerBalanceStep > 0.0)
        {
         lot = (bal / InpLotPerBalanceStep) * InpStartLots;
        }
     }
   else if(InpLotMode == LOT_MODE_RISK_PERCENT)
     {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_money = bal * (InpRiskPercent / 100.0);
      double tick_value = g_sym.TickValue();
      double tick_size = g_sym.TickSize();
      if(sl_points > 0.0 && tick_value > 0.0 && tick_size > 0.0)
        {
         double point_value = tick_value / (tick_size / g_sym.Point());
         if(point_value > 0.0)
            lot = risk_money / (sl_points * point_value);
        }
     }
   
   lot = MathMax(min_lot, MathMin(max_lot, lot));
   return MathFloor(lot / step) * step;
  }

//+------------------------------------------------------------------+
//| Emergency Close All on DD Breach                                 |
//+------------------------------------------------------------------+
void CloseAll()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i))
        {
         if(g_pos.Symbol() == _Symbol && g_pos.Magic() >= InpBaseMagicNumber && g_pos.Magic() <= InpBaseMagicNumber + 10)
           {
            g_trade.SetExpertMagicNumber(g_pos.Magic());
            g_trade.PositionClose(g_pos.Ticket());
           }
        }
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(g_order.SelectByIndex(i))
        {
         if(g_order.Symbol() == _Symbol && g_order.Magic() >= InpBaseMagicNumber && g_order.Magic() <= InpBaseMagicNumber + 10)
           {
            g_trade.SetExpertMagicNumber(g_order.Magic());
            g_trade.OrderDelete(g_order.Ticket());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Drawdown & Daily Capital Protection Engine                       |
//+------------------------------------------------------------------+
bool CheckDrawdown()
  {
   if(!InpEnableDDProtection) return false;
   
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != g_current_day)
     {
      g_current_day = dt.day_of_year;
      g_start_day_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_trading_paused = false;
     }
   
   if(g_trading_paused) return true;
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(bal <= 0.0) return false;
   
   double total_dd_perc = ((bal - eq) / bal) * 100.0;
   double daily_loss_perc = (g_start_day_balance > 0.0) ? (((g_start_day_balance - eq) / g_start_day_balance) * 100.0) : 0.0;
   double total_dd_money = bal - eq;
   
   bool breached = false;
   if(InpMaxTotalDDPercent > 0.0 && total_dd_perc >= InpMaxTotalDDPercent) breached = true;
   if(InpMaxDailyLossPercent > 0.0 && daily_loss_perc >= InpMaxDailyLossPercent) breached = true;
   if(InpMaxDDMoney > 0.0 && total_dd_money >= InpMaxDDMoney) breached = true;
   
   if(breached)
     {
      if(InpCloseAllOnDDBreach) CloseAll();
      if(InpPauseTradingAfterDDBreach) g_trading_paused = true;
      return true;
     }
   
   return false;
  }

//+------------------------------------------------------------------+
//| Manage Virtual Expiration (Original Virtual_expiration logic)    |
//+------------------------------------------------------------------+
void ManageVirtualExpiration()
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(g_order.SelectByIndex(i))
        {
         if(g_order.Symbol() == _Symbol)
           {
            ulong magic = g_order.Magic();
            for(int s = 0; s < 7; s++)
              {
               if(g_strats[s].enabled && magic == g_strats[s].magic)
                 {
                  datetime open_time = g_order.TimeSetup();
                  if(TimeCurrent() > open_time + g_strats[s].expiry_hours * 3600)
                    {
                     g_trade.SetExpertMagicNumber(magic);
                     g_trade.OrderDelete(g_order.Ticket());
                    }
                  break;
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage Trailing Stops (Original ccbsw_16 Architecture)           |
//+------------------------------------------------------------------+
void ManageTrailingStops()
  {
   if(!InpEnableTrailing) return;
   
   double point = g_sym.Point();
   int digits   = g_sym.Digits();
   long freeze  = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != _Symbol) continue;
      
      ulong magic = g_pos.Magic();
      for(int s = 0; s < 7; s++)
        {
         if(!g_strats[s].enabled || magic != g_strats[s].magic) continue;
         
         double sl          = g_pos.StopLoss();
         double tp          = g_pos.TakeProfit();
         double op          = g_pos.PriceOpen();
         double trail_start = g_strats[s].trail_start;
         double trail_step  = g_strats[s].trail_step;
         double trail_cap   = g_strats[s].trail_cap;
         
         g_trade.SetExpertMagicNumber(magic);
         
         if(g_pos.PositionType() == POSITION_TYPE_BUY && trail_start > 0.0)
           {
            double bid = g_sym.Bid();
            if(bid > sl + (trail_start + 0.1) * point &&
               bid > op + trail_step * point &&
               (tp == 0.0 || bid < tp - freeze * point) &&
               (sl < op + trail_cap * point))
              {
               double new_sl = NormalizeDouble(bid - trail_start * point, digits);
               if(new_sl > sl + point)
                 {
                  g_trade.PositionModify(g_pos.Ticket(), new_sl, tp);
                 }
              }
           }
         else if(g_pos.PositionType() == POSITION_TYPE_SELL && trail_start > 0.0)
           {
            double ask = g_sym.Ask();
            if((sl == 0.0 || ask < sl - (trail_start + 0.1) * point) &&
               ask < op - trail_step * point &&
               (tp == 0.0 || ask > tp + freeze * point) &&
               (sl == 0.0 || sl > op - trail_cap * point))
              {
               double new_sl = NormalizeDouble(ask + trail_start * point, digits);
               if(sl == 0.0 || new_sl < sl - point)
                 {
                  g_trade.PositionModify(g_pos.Ticket(), new_sl, tp);
                 }
              }
           }
         break;
        }
     }
  }

//+------------------------------------------------------------------+
//| Execute Daily Breakout Strategies (A to H)                       |
//+------------------------------------------------------------------+
void ExecuteStrategies()
  {
   if(g_trading_paused) return;
   if(g_sym.Spread() > InpMaxSpreadPoints) return;
   
   long limit = AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   double point = g_sym.Point();
   int digits = g_sym.Digits();
   
   for(int s = 0; s < 7; s++)
     {
      if(!g_strats[s].enabled) continue;
      
      bool has_buy_pos = false, has_sell_pos = false;
      bool has_buy_stop = false, has_sell_stop = false;
      double existing_buy_price = 0.0, existing_sell_price = 0.0;
      ulong b_ticket = 0, s_ticket = 0;
      
      for(int i = 0; i < PositionsTotal(); i++)
        {
         if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == g_strats[s].magic)
           {
            if(g_pos.PositionType() == POSITION_TYPE_BUY) has_buy_pos = true;
            if(g_pos.PositionType() == POSITION_TYPE_SELL) has_sell_pos = true;
           }
        }
      for(int i = 0; i < OrdersTotal(); i++)
        {
         if(g_order.SelectByIndex(i) && g_order.Symbol() == _Symbol && g_order.Magic() == g_strats[s].magic)
           {
            if(g_order.OrderType() == ORDER_TYPE_BUY_STOP)
              {
               has_buy_stop = true;
               existing_buy_price = g_order.PriceOpen();
               b_ticket = g_order.Ticket();
              }
            if(g_order.OrderType() == ORDER_TYPE_SELL_STOP)
              {
               has_sell_stop = true;
               existing_sell_price = g_order.PriceOpen();
               s_ticket = g_order.Ticket();
              }
           }
        }
      
      g_trade.SetExpertMagicNumber(g_strats[s].magic);
      double lot = CalculateLots(g_strats[s].sl_points);
      if(lot <= 0.0) continue;
      
      string comment = StringFormat("%s_%s", InpTradeCommentPrefix, g_strats[s].name);
      
      // 1. Buy Entry
      if(!has_buy_pos)
        {
         double swing_high = FindDailySwingHigh(g_strats[s].left_bars, g_strats[s].right_bars, g_strats[s].max_lookback, g_strats[s].detect_offset);
         if(swing_high > 0.0)
           {
            double entry = NormalizeDouble(swing_high + g_strats[s].buy_entry_offset * point, digits);
            bool skip = false;
            if(has_buy_stop)
              {
               if(MathAbs(existing_buy_price - entry) < g_strats[s].dup_tolerance * point) skip = true;
               else if(entry > existing_buy_price) skip = true; // keep lower/better entry
              }
            if(!skip && (limit == 0 || (OrdersTotal() + PositionsTotal()) < limit) && entry > g_sym.Ask())
              {
               double sl = (g_strats[s].sl_points > 0.0) ? NormalizeDouble(entry - g_strats[s].sl_points * point, digits) : 0.0;
               double tp = (g_strats[s].tp_points > 0.0) ? NormalizeDouble(entry + g_strats[s].tp_points * point, digits) : 0.0;
               
               if(has_buy_stop) g_trade.OrderDelete(b_ticket);
               g_trade.BuyStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
              }
           }
        }
      
      // 2. Sell Entry
      if(!has_sell_pos)
        {
         double swing_low = FindDailySwingLow(g_strats[s].left_bars, g_strats[s].right_bars, g_strats[s].max_lookback, g_strats[s].detect_offset);
         if(swing_low > 0.0)
           {
            double entry = NormalizeDouble(swing_low - g_strats[s].sell_entry_offset * point, digits);
            bool skip = false;
            if(has_sell_stop)
              {
               if(MathAbs(existing_sell_price - entry) < g_strats[s].dup_tolerance * point) skip = true;
               else if(entry < existing_sell_price) skip = true; // keep higher/better entry
              }
            if(!skip && (limit == 0 || (OrdersTotal() + PositionsTotal()) < limit) && entry < g_sym.Bid())
              {
               double sl = (g_strats[s].sl_points > 0.0) ? NormalizeDouble(entry + g_strats[s].sl_points * point, digits) : 0.0;
               double tp = (g_strats[s].tp_points > 0.0) ? NormalizeDouble(entry - g_strats[s].tp_points * point, digits) : 0.0;
               
               if(has_sell_stop) g_trade.OrderDelete(s_ticket);
               g_trade.SellStop(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Chart Information Dashboard                                      |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   int active_modules = 0;
   for(int i = 0; i < 7; i++) if(g_strats[i].enabled) active_modules++;
   
   string text = "--- ZERITH GOLD TRADE PRO EA (MT5 v1.34) ---\n";
   text += "Status: " + (g_trading_paused ? "PAUSED (DD Limit Breached)" : "RUNNING & SCANNING") + "\n";
   text += "Active Modules: " + IntegerToString(active_modules) + " / 7 (A, C, D, E, F, G, H)\n";
   text += "Open Positions: " + IntegerToString(PositionsTotal()) + " | Pending Orders: " + IntegerToString(OrdersTotal()) + "\n";
   text += "Account Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   text += "Account Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   text += "Trailing Engine: " + (InpEnableTrailing ? "ACTIVE (Real-time)" : "OFF") + "\n";
   text += "Virtual Expiry: ACTIVE (D1/H1 Sweeps)\n";
   
   Comment(text);
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_sym.RefreshRates()) return;
   
   // 1. Drawdown & Capital Protection (Every tick)
   if(CheckDrawdown())
     {
      DrawDashboard();
      return;
     }
   
   // 2. Trailing Stop Management (Every tick)
   ManageTrailingStops();
   
   // 3. Hourly Bar Open: Virtual Expiration Cleanup & Daily Breakout Scan
   static datetime last_h1 = 0;
   datetime curr_h1 = iTime(_Symbol, PERIOD_H1, 0);
   if(curr_h1 != last_h1)
     {
      ManageVirtualExpiration();
      ExecuteStrategies();
      last_h1 = curr_h1;
     }
   
   // 4. Update Dashboard
   DrawDashboard();
  }
//+------------------------------------------------------------------+
