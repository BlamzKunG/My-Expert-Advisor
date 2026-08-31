//+------------------------------------------------------------------+
//|                                       Quantum_Emperor_EA.mq5     |
//|                 Quantum Emperor EA MT5 Port (Native MQL5)        |
//|                             https://www.mql5.com                 |
//+------------------------------------------------------------------+
#property copyright "Bogdan Puscasu (from MQL5.com) / MT5 Port 2026"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.70"
#property description "Quantum Emperor MT5 - High Probability Asian/London Session Box Range Breakout (ORB)"
#property description "Features Smart Recovery System, OCO Order Cancellation, Expiry Management & NFP Filters"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_RISK_LEVEL
  {
   RISK_VERY_LOW=0,     // Very Low
   RISK_LOW=1,          // Low
   RISK_MEDIUM=2,       // Medium
   RISK_MEDIUM_HIGH=3,  // Medium-High
   RISK_HIGH=4,         // High
   RISK_VERY_HIGH=5     // Very High
  };

enum ENUM_ON_OFF
  {
   STATUS_ENABLE=0,     // Enable
   STATUS_DISABLE=1     // Disable
  };

//--- Input Parameters
input group ">>>> 1. General & Range Box Settings"
input string            InpEAComment          = "Quantum Emperor MT5"; // Trade Comment
input string            InpBoxStart           = "03:00";              // Box Hour Start (HH:MM)
input string            InpBoxEnd             = "11:00";              // Box Hour End (HH:MM)
input double            InpAbovePoints        = 10.0;                 // Points Above Range for Buy Stop
input double            InpBelowPoints        = 10.0;                 // Points Below Range for Sell Stop
input bool              InpCancelOpposite     = true;                 // Cancel opposite orders when one triggers
input string            InpExpirePendingTime  = "21:30";              // Cancel Unfilled Pending Orders At (HH:MM)

input group ">>>> 2. Money Management & Take Profit"
input ENUM_RISK_LEVEL   InpRiskLevel          = RISK_MEDIUM;          // Risk Level
input double            InpFixedLot           = 0.01;                 // Fixed Lot (if Manual sizing)
input bool              InpUseAutoLot         = true;                 // Use Automatic Lot Sizing by Risk Level
input double            InpTakeProfit         = 1000.0;               // Take Profit (Points, e.g. 1000 = 100 pips)
input double            InpStopLoss           = 0.0;                  // Stop Loss (Points, 0 = Off / Managed by Smart Recovery)

input group ">>>> 3. Smart Recovery Settings"
input bool              InpSmartRecovery      = true;                 // Activate Smart Recovery Settings
input double            InpRecoveryMultiplier = 1.7;                  // Recovery Lot Multiplier
input int               InpRecoveryMaxTimes   = 3;                    // Max Recovery Multiplier Times

input group ">>>> 4. Trading Days & Filters"
input ENUM_ON_OFF       InpTradeFriday        = STATUS_DISABLE;       // Trade Friday (Disable avoids weekend gap)
input bool              InpDisableNFP         = true;                 // Disable trading on NFP Friday (1st Friday)
input ulong             InpMagicNumber        = 777888;               // Magic Number
input int               InpSlippage           = 10;                   // Max Slippage (Points)
input int               InpMaxSpread          = 100;                  // Max Allowed Spread (Points)

//--- Global Objects & State Variables
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_ord;
CAccountInfo   g_acc;
CSymbolInfo    g_sym;

datetime       g_last_box_date       = 0;
double         g_box_high            = 0.0;
double         g_box_low             = 0.0;
bool           g_box_calculated      = false;
bool           g_buy_pending_placed  = false;
bool           g_sell_pending_placed = false;
int            g_consecutive_losses  = 0;

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk Level & Smart Recovery          |
//+------------------------------------------------------------------+
double CalculateOrderLot()
  {
   if(!InpUseAutoLot)
      return InpFixedLot;

   double balance = g_acc.Balance();
   double divisor = 2000.0;

   switch(InpRiskLevel)
     {
      case RISK_VERY_LOW:    divisor = 3000.0; break;
      case RISK_LOW:         divisor = 2000.0; break;
      case RISK_MEDIUM:      divisor = 1500.0; break;
      case RISK_MEDIUM_HIGH: divisor = 1000.0; break;
      case RISK_HIGH:        divisor = 700.0;  break;
      case RISK_VERY_HIGH:   divisor = 500.0;  break;
     }

   double calculated_lot = (balance / divisor) * 0.01;

   // Apply Smart Recovery Multiplier if previous trade was in loss
   if(InpSmartRecovery && g_consecutive_losses > 0)
     {
      int times = MathMin(g_consecutive_losses, InpRecoveryMaxTimes);
      calculated_lot = calculated_lot * MathPow(InpRecoveryMultiplier, times);
     }

   double min_lot = g_sym.LotsMin();
   double max_lot = g_sym.LotsMax();
   double step    = g_sym.LotsStep();
   if(step <= 0.0) step = 0.01;

   calculated_lot = MathMax(min_lot, MathMin(max_lot, calculated_lot));
   return MathFloor(calculated_lot / step) * step;
  }

//+------------------------------------------------------------------+
//| Check if Day / Time is Valid for Trading                         |
//+------------------------------------------------------------------+
bool IsTradingAllowed()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // 1. Friday Filter
   if(dt.day_of_week == 5 && InpTradeFriday == STATUS_DISABLE)
      return false;

   // 2. NFP Friday Filter (1st Friday of month: day <= 7)
   if(InpDisableNFP && dt.day_of_week == 5 && dt.day <= 7)
      return false;

   // 3. Weekend Filter
   if(dt.day_of_week == 0 || dt.day_of_week == 6)
      return false;

   return true;
  }

//+------------------------------------------------------------------+
//| Calculate Range Box High & Low between BoxStart and BoxEnd       |
//+------------------------------------------------------------------+
bool CalculateRangeBox()
  {
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   string today_str = TimeToString(now, TIME_DATE);
   datetime start_time = StringToTime(today_str + " " + InpBoxStart);
   datetime end_time   = StringToTime(today_str + " " + InpBoxEnd);

   // Only calculate after BoxEnd time has passed
   if(now < end_time)
      return false;

   // Prevent recalculating on the same day if already done
   datetime today_midnight = StringToTime(today_str + " 00:00");
   if(g_last_box_date == today_midnight && g_box_calculated)
      return true;

   int start_bar = iBarShift(_Symbol, PERIOD_M1, start_time, false);
   int end_bar   = iBarShift(_Symbol, PERIOD_M1, end_time, false);

   if(start_bar < 0 || end_bar < 0 || start_bar <= end_bar)
      return false;

   int count = start_bar - end_bar + 1;
   int highest_bar = iHighest(_Symbol, PERIOD_M1, MODE_HIGH, count, end_bar);
   int lowest_bar  = iLowest(_Symbol, PERIOD_M1, MODE_LOW, count, end_bar);

   if(highest_bar < 0 || lowest_bar < 0)
      return false;

   g_box_high = iHigh(_Symbol, PERIOD_M1, highest_bar);
   g_box_low  = iLow(_Symbol, PERIOD_M1, lowest_bar);

   if(g_box_high > 0 && g_box_low > 0 && g_box_high > g_box_low)
     {
      g_last_box_date       = today_midnight;
      g_box_calculated      = true;
      g_buy_pending_placed  = false;
      g_sell_pending_placed = false;

      PrintFormat("📦 [Quantum Emperor] Range Box Calculated for %s: High = %.2f, Low = %.2f (Range: %.1f pts)",
                  today_str, g_box_high, g_box_low, (g_box_high - g_box_low) / g_sym.Point());
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Count Open Positions & Pending Orders by Magic                   |
//+------------------------------------------------------------------+
int CountOpenPositions(long &pos_type)
  {
   int count = 0;
   pos_type = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
        {
         count++;
         pos_type = g_pos.PositionType();
        }
     }
   return count;
  }

int CountPendingOrders(ENUM_ORDER_TYPE &ord_type, ulong &ticket)
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
        {
         count++;
         ord_type = g_ord.OrderType();
         ticket   = g_ord.Ticket();
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Cancel Opposite Pending Orders when one triggers (OCO)          |
//+------------------------------------------------------------------+
void HandleCancelOppositeOrders()
  {
   if(!InpCancelOpposite)
      return;

   long pos_type = -1;
   int open_pos = CountOpenPositions(pos_type);

   if(open_pos > 0)
     {
      // If we have an active position, cancel any remaining pending orders
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!g_ord.SelectByIndex(i)) continue;
         if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
           {
            ulong t = g_ord.Ticket();
            PrintFormat("⚡ [OCO Cancellation] Active %s position detected -> Canceling opposite pending order #%I64u",
                        (pos_type == POSITION_TYPE_BUY ? "BUY" : "SELL"), t);
            g_trade.OrderDelete(t);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Cancel Pending Orders at Expiry Time (Ex_Pend)                   |
//+------------------------------------------------------------------+
void HandlePendingOrderExpiration()
  {
   datetime now = TimeCurrent();
   string today_str = TimeToString(now, TIME_DATE);
   datetime expire_time = StringToTime(today_str + " " + InpExpirePendingTime);

   if(now >= expire_time)
     {
      for(int i = OrdersTotal() - 1; i >= 0; i--)
        {
         if(!g_ord.SelectByIndex(i)) continue;
         if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
           {
            ulong t = g_ord.Ticket();
            PrintFormat("⏰ [Pending Expiry] Time reached %s -> Deleting unfilled pending order #%I64u", InpExpirePendingTime, t);
            g_trade.OrderDelete(t);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Account History for Win/Loss to update Smart Recovery      |
//+------------------------------------------------------------------+
void UpdateHistoryLossTracking()
  {
   datetime from_time = TimeCurrent() - 86400 * 3;
   if(!HistorySelect(from_time, TimeCurrent())) return;

   int deals = HistoryDealsTotal();
   for(int i = deals - 1; i >= 0; i--)
     {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;
      if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetString(deal_ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
      if(profit < 0.0)
        {
         // Loss occurred
         g_consecutive_losses = MathMin(g_consecutive_losses + 1, InpRecoveryMaxTimes);
        }
      else if(profit > 0.0)
        {
         // Win occurred -> reset recovery
         g_consecutive_losses = 0;
        }
      break;
     }
  }

//+------------------------------------------------------------------+
//| Place Breakout Buy Stop & Sell Stop Orders                       |
//+------------------------------------------------------------------+
void PlaceBreakoutOrders()
  {
   if(!g_box_calculated || g_box_high <= 0 || g_box_low <= 0)
      return;

   datetime now = TimeCurrent();
   string today_str = TimeToString(now, TIME_DATE);
   datetime end_time    = StringToTime(today_str + " " + InpBoxEnd);
   datetime expire_time = StringToTime(today_str + " " + InpExpirePendingTime);

   // Place orders only between BoxEnd and ExpirePendingTime
   if(now < end_time || now >= expire_time)
      return;

   long pos_type = -1;
   if(CountOpenPositions(pos_type) > 0)
      return; // Already in trade

   double point  = g_sym.Point();
   int    digits = g_sym.Digits();

   // Spread filter
   double spread = (g_sym.Ask() - g_sym.Bid()) / point;
   if(spread > InpMaxSpread)
      return;

   double volume = CalculateOrderLot();
   if(volume <= 0.0) return;

   double buy_stop_price  = NormalizeDouble(g_box_high + InpAbovePoints * point, digits);
   double sell_stop_price = NormalizeDouble(g_box_low  - InpBelowPoints * point, digits);

   double buy_tp  = (InpTakeProfit > 0) ? NormalizeDouble(buy_stop_price + InpTakeProfit * point, digits) : 0.0;
   double buy_sl  = (InpStopLoss > 0)   ? NormalizeDouble(buy_stop_price - InpStopLoss * point, digits)   : 0.0;

   double sell_tp = (InpTakeProfit > 0) ? NormalizeDouble(sell_stop_price - InpTakeProfit * point, digits) : 0.0;
   double sell_sl = (InpStopLoss > 0)   ? NormalizeDouble(sell_stop_price + InpStopLoss * point, digits)   : 0.0;

   // 1. Place Buy Stop Order
   if(!g_buy_pending_placed && g_sym.Ask() < buy_stop_price)
     {
      if(g_trade.BuyStop(volume, buy_stop_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_SPECIFIED, expire_time, InpEAComment + " [BuyStop]"))
        {
         PrintFormat("👑 [Quantum Emperor] Placed BUY STOP at %.2f (Box High: %.2f + %.1f pts) Lot: %.2f TP: %.2f",
                     buy_stop_price, g_box_high, InpAbovePoints, volume, buy_tp);
         g_buy_pending_placed = true;
        }
     }

   // 2. Place Sell Stop Order
   if(!g_sell_pending_placed && g_sym.Bid() > sell_stop_price)
     {
      if(g_trade.SellStop(volume, sell_stop_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_SPECIFIED, expire_time, InpEAComment + " [SellStop]"))
        {
         PrintFormat("👑 [Quantum Emperor] Placed SELL STOP at %.2f (Box Low: %.2f - %.1f pts) Lot: %.2f TP: %.2f",
                     sell_stop_price, g_box_low, InpBelowPoints, volume, sell_tp);
         g_sell_pending_placed = true;
        }
     }
  }

//+------------------------------------------------------------------+
//| Chart Information Dashboard                                      |
//+------------------------------------------------------------------+
void DrawDashboard()
  {
   long pos_type = -1;
   int open_pos = CountOpenPositions(pos_type);
   ENUM_ORDER_TYPE ord_type; ulong t;
   int pending_orders = CountPendingOrders(ord_type, t);

   string text = StringFormat("--- QUANTUM EMPEROR EA (MT5 PORT) ---\n"
                              "Trading Allowed: %s\n"
                              "Session Box: %s - %s (High: %.2f | Low: %.2f)\n"
                              "Risk Level: %s | Next Order Lot: %.2f\n"
                              "Smart Recovery: %s (Loss Streak: %d / %d)\n"
                              "Active Positions: %d | Pending Orders: %d\n"
                              "Take Profit: %.0f pts | Expiry Time: %s\n"
                              "Account Equity: $%.2f | Balance: $%.2f",
                              (IsTradingAllowed() ? "YES" : "NO (Filter Active)"),
                              InpBoxStart, InpBoxEnd, g_box_high, g_box_low,
                              EnumToString(InpRiskLevel), CalculateOrderLot(),
                              (InpSmartRecovery ? "ACTIVE" : "OFF"), g_consecutive_losses, InpRecoveryMaxTimes,
                              open_pos, pending_orders,
                              InpTakeProfit, InpExpirePendingTime,
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

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   g_last_box_date       = 0;
   g_box_high            = 0.0;
   g_box_low             = 0.0;
   g_box_calculated      = false;
   g_buy_pending_placed  = false;
   g_sell_pending_placed = false;

   Print("Quantum Emperor EA MT5 Port successfully initialized.");
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

   // 1. Filter: Check if day/time is allowed
   if(!IsTradingAllowed())
     {
      DrawDashboard();
      return;
     }

   // 2. Manage OCO Order Cancellation (If one side opens, cancel the other)
   HandleCancelOppositeOrders();

   // 3. Manage Pending Order Expiration at Ex_Pend
   HandlePendingOrderExpiration();

   // 4. Update Loss/Recovery tracking from deal history
   UpdateHistoryLossTracking();

   // 5. Calculate Asian/London Session Box Range
   CalculateRangeBox();

   // 6. Place Buy Stop / Sell Stop Breakout Orders
   PlaceBreakoutOrders();

   // 7. Render Chart Dashboard
   DrawDashboard();
  }
//+------------------------------------------------------------------+
