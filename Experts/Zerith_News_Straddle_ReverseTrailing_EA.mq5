//+------------------------------------------------------------------+
//|                        Zerith_News_Straddle_ReverseTrailing_EA.mq5|
//|   Zerith Series - News Straddle with Opposite Order Trailing SL  |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / BlamzKunG Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.00"
#property description "Zerith News Straddle Reverse-Trailing MT5 EA"
#property description "Places Buy Stop / Sell Stop before high-impact news events (CPI, NFP, FOMC)."
#property description "Opposite pending stop order acts as dynamic Trailing Stop Loss & Reversal entry."
#property description "When price moves into profit, the opposite stop order trails behind the market."
#property description "Upon market reversal hitting the stop, closes previous position, opens reverse position,"
#property description "and places a new opposite stop order with optional recovery lot multiplier."
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_TRIGGER_MODE
  {
   TRIGGER_MANUAL_BUTTON   = 0, // Manual GUI Button / Instant on Chart
   TRIGGER_SCHEDULED_TIME  = 1, // Scheduled News Time (Auto-arm)
   TRIGGER_IMMEDIATE       = 2  // Immediate on EA Launch
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED               = 0, // Fixed Lot Size
   LOT_RISK_PERCENT        = 1  // Dynamic Risk % of Balance
  };

enum ENUM_ON_MAX_REVERSALS
  {
   ON_MAX_CLOSE_ALL        = 0, // Close Active Position & End Cycle
   ON_MAX_HARD_SL_ONLY     = 1  // Apply Standard Hard SL (No New Orders)
  };

enum ENUM_EA_STATE
  {
   STATE_IDLE              = 0, // Idle / Standby
   STATE_ARMED             = 1, // Armed (Waiting for news countdown)
   STATE_STRADDLE_PLACED   = 2, // Both Buy Stop & Sell Stop pending
   STATE_BUY_ACTIVE        = 3, // Long position running, trailing Sell Stop
   STATE_SELL_ACTIVE       = 4, // Short position running, trailing Buy Stop
   STATE_CYCLE_COMPLETE    = 5  // Target reached or trading stopped
  };

//--- Input Parameters
input group ">>>> 1. News & Straddle Setup"
input ENUM_TRIGGER_MODE   InpTriggerMode             = TRIGGER_MANUAL_BUTTON; // Execution Trigger Mode
input string              InpNewsTime                = "15:30:00";            // News Time ("HH:MM:SS" or "YYYY.MM.DD HH:MM:SS")
input int                 InpSecondsBeforeNews       = 30;                    // Seconds Before News to Place Orders
input double              InpStraddleDistancePoints  = 200.0;                 // Distance from Price for Stop Orders (Points)
input int                 InpPendingExpiryMinutes    = 30;                    // Expire Unfilled Orders After X Minutes (0 = Off)

input group ">>>> 2. Opposite Order Trailing (Core Logic)"
input double              InpTrailingStartPoints     = 100.0;                 // Profit Points to Start Trailing Opposite Order
input double              InpTrailingDistancePoints  = 100.0;                 // Trailing Distance behind Market Price (Points)
input double              InpTrailingStepPoints      = 10.0;                  // Min Step Movement before Modifying Order (Points)

input group ">>>> 3. Reversal & Recovery Engine"
input int                 InpMaxReversals            = 5;                     // Max Allowed Reversals (0 = Unlimited)
input double              InpReverseMultiplier       = 1.0;                   // Reversal Lot Multiplier (1.0 = Fixed, >1.0 = Recovery)
input double              InpReverseDistancePoints   = 0.0;                   // Distance for New Opposite Order (0 = Use Straddle Distance)
input ENUM_ON_MAX_REVERSALS InpOnMaxReversals        = ON_MAX_CLOSE_ALL;      // Action when Max Reversals Reached

input group ">>>> 4. Money Management & Profit Targets"
input ENUM_LOT_MODE       InpLotMode                 = LOT_FIXED;             // Lot Sizing Method
input double              InpFixedLot                = 0.01;                  // Fixed Lot Size / Base Lot
input double              InpRiskPercent             = 1.0;                   // Risk % of Balance (if Dynamic Risk)
input double              InpTakeProfitPoints        = 0.0;                   // Hard Take Profit in Points (0 = Off / Trailing Only)
input double              InpTargetProfitMoney       = 0.0;                   // Basket Target Profit in Currency $ (0 = Off)

input group ">>>> 5. Capital Protection & Safety Filters"
input double              InpMaxSpreadPoints         = 50.0;                  // Max Allowed Spread in Points (0 = Disable filter)
input bool                InpEnableDDProtection      = true;                  // Enable Drawdown & Daily Loss Protection
input double              InpMaxTotalDDPercent       = 10.0;                  // Max Floating Drawdown % (Relative to Balance)
input double              InpMaxDailyLossPercent     = 5.0;                   // Max Daily Total Loss % (Realized + Floating)
input ulong               InpMagicNumber             = 889901;                // Magic Number
input int                 InpSlippage                = 20;                    // Max Slippage in Points
input string              InpTradeComment            = "Zerith_NewsStraddle"; // Order Comment

input group ">>>> 6. Graphical Dashboard & HUD"
input bool                InpShowPanel               = true;                  // Show On-Chart Interactive HUD
input int                 InpPanelX                  = 20;                    // Panel X Offset (Pixels)
input int                 InpPanelY                  = 30;                    // Panel Y Offset (Pixels)

//--- Global Objects & State Variables
CTrade         g_trade;
CPositionInfo  g_pos;
COrderInfo     g_ord;
CAccountInfo   g_acc;
CSymbolInfo    g_sym;

ENUM_EA_STATE  g_state                   = STATE_IDLE;
int            g_reversal_count          = 0;
datetime       g_straddle_placed_time    = 0;
bool           g_immediate_placed        = false;
datetime       g_scheduled_news_datetime = 0;
bool           g_scheduled_armed         = false;

// DD Protection State
datetime       g_last_daily_reset_date   = 0;
bool           g_dd_tripped              = false;
double         g_floating_pl             = 0.0;
double         g_floating_dd_pct         = 0.0;
double         g_today_realized_pl       = 0.0;
double         g_today_loss_pct          = 0.0;

// Panel UI Constants
#define PANEL_PREFIX "ZRNW_"

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_sym.Name(_Symbol))
     {
      PrintFormat("❌ Failed to initialize symbol %s", _Symbol);
      return INIT_FAILED;
     }
   g_sym.Refresh();

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // Parse Scheduled News Time if applicable
   if(InpTriggerMode == TRIGGER_SCHEDULED_TIME)
     {
      g_scheduled_news_datetime = ParseNewsDateTime(InpNewsTime);
      g_scheduled_armed         = true;
      g_state                   = STATE_ARMED;
      PrintFormat("⏰ [Zerith News] Armed for Scheduled News Time: %s (Placement %d sec before)",
                  TimeToString(g_scheduled_news_datetime, TIME_DATE|TIME_SECONDS), InpSecondsBeforeNews);
     }
   else if(InpTriggerMode == TRIGGER_IMMEDIATE)
     {
      g_state = STATE_IDLE; // Will be triggered on first tick
     }
   else
     {
      g_state = STATE_IDLE;
     }

   // Initialize Dashboard
   if(InpShowPanel)
     {
      CreateDashboard();
      UpdateDashboard();
     }

   EventSetTimer(1);
   PrintFormat("🚀 [Zerith News Straddle Reverse-Trailing EA] v1.00 Loaded. Magic: %I64u, Symbol: %s", InpMagicNumber, _Symbol);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpShowPanel)
     {
      DestroyDashboard();
     }
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert Timer Function (Handles Countdown & HUD Refresh)          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   // Check Scheduled Time Trigger
   if(InpTriggerMode == TRIGGER_SCHEDULED_TIME && g_scheduled_armed && g_state == STATE_ARMED)
     {
      datetime now = TimeCurrent();
      datetime trigger_time = g_scheduled_news_datetime - InpSecondsBeforeNews;

      if(now >= trigger_time && now < g_scheduled_news_datetime + 60)
        {
         PrintFormat("⏰ [News Countdown Trigger] Server time %s reached news trigger time %s -> Placing Straddle!",
                     TimeToString(now, TIME_SECONDS), TimeToString(trigger_time, TIME_SECONDS));
         g_scheduled_armed = false;
         PlaceStraddleOrders("Scheduled News Trigger");
        }
     }

   // Periodic Protection & Dashboard Refresh
   CheckDrawdownProtection();

   if(InpShowPanel)
      UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_sym.RefreshRates()) return;

   // 1. Capital & Drawdown Protection Check
   CheckDrawdownProtection();
   if(g_dd_tripped) return;

   // 2. Immediate Placement Mode
   if(InpTriggerMode == TRIGGER_IMMEDIATE && !g_immediate_placed && g_state == STATE_IDLE)
     {
      g_immediate_placed = true;
      PlaceStraddleOrders("Immediate Trigger Mode");
     }

   // 3. Scan Existing Positions and Pending Orders
   int buy_positions = 0, sell_positions = 0;
   ulong buy_pos_ticket = 0, sell_pos_ticket = 0;
   double buy_pos_open_price = 0.0, sell_pos_open_price = 0.0;
   double buy_pos_volume = 0.0, sell_pos_volume = 0.0;
   double total_fl_profit = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
        {
         total_fl_profit += (g_pos.Profit() + g_pos.Swap());
         if(g_pos.PositionType() == POSITION_TYPE_BUY)
           {
            buy_positions++;
            buy_pos_ticket     = g_pos.Ticket();
            buy_pos_open_price = g_pos.PriceOpen();
            buy_pos_volume     = g_pos.Volume();
           }
         else if(g_pos.PositionType() == POSITION_TYPE_SELL)
           {
            sell_positions++;
            sell_pos_ticket     = g_pos.Ticket();
            sell_pos_open_price = g_pos.PriceOpen();
            sell_pos_volume     = g_pos.Volume();
           }
        }
     }

   int buy_stop_orders = 0, sell_stop_orders = 0;
   ulong buy_stop_ticket = 0, sell_stop_ticket = 0;
   double buy_stop_price = 0.0, sell_stop_price = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
        {
         if(g_ord.OrderType() == ORDER_TYPE_BUY_STOP)
           {
            buy_stop_orders++;
            buy_stop_ticket = g_ord.Ticket();
            buy_stop_price  = g_ord.PriceOpen();
           }
         else if(g_ord.OrderType() == ORDER_TYPE_SELL_STOP)
           {
            sell_stop_orders++;
            sell_stop_ticket = g_ord.Ticket();
            sell_stop_price  = g_ord.PriceOpen();
           }
        }
     }

   // 4. Basket / Currency Profit Target Check
   if(InpTargetProfitMoney > 0.0 && total_fl_profit >= InpTargetProfitMoney)
     {
      PrintFormat("🎯 [Profit Target Reached] Basket profit $%.2f reached target $%.2f -> Closing all & resetting!",
                  total_fl_profit, InpTargetProfitMoney);
      CloseAllPositionsAndOrders("Target Profit Money Reached");
      g_state = STATE_CYCLE_COMPLETE;
      if(InpShowPanel) UpdateDashboard();
      return;
     }

   // 5. CORE LOGIC: REVERSAL EXECUTION DETECTION
   // If both Buy and Sell positions are detected simultaneously,
   // it means the opposite stop order was just triggered by market reversal!
   if(buy_positions > 0 && sell_positions > 0)
     {
      HandleOppositeStopReversal(buy_pos_ticket, sell_pos_ticket);
      return;
     }

   // 6. SINGLE POSITION ACTIVE STATES
   if(buy_positions > 0 && sell_positions == 0)
     {
      g_state = STATE_BUY_ACTIVE;

      // Check Hard Take Profit in points
      if(InpTakeProfitPoints > 0.0)
        {
         double p_pts = (g_sym.Bid() - buy_pos_open_price) / g_sym.Point();
         if(p_pts >= InpTakeProfitPoints)
           {
            PrintFormat("🎯 [TP Reached] Buy position hit Take Profit (%.1f pts) -> Closing all!", p_pts);
            CloseAllPositionsAndOrders("Take Profit Hit");
            g_state = STATE_CYCLE_COMPLETE;
            return;
           }
        }

      // Trail the Opposite Pending Sell Stop Order
      if(sell_stop_orders > 0)
        {
         TrailOppositeSellStop(buy_pos_open_price, sell_stop_ticket, sell_stop_price);
        }
     }
   else if(sell_positions > 0 && buy_positions == 0)
     {
      g_state = STATE_SELL_ACTIVE;

      // Check Hard Take Profit in points
      if(InpTakeProfitPoints > 0.0)
        {
         double p_pts = (sell_pos_open_price - g_sym.Ask()) / g_sym.Point();
         if(p_pts >= InpTakeProfitPoints)
           {
            PrintFormat("🎯 [TP Reached] Sell position hit Take Profit (%.1f pts) -> Closing all!", p_pts);
            CloseAllPositionsAndOrders("Take Profit Hit");
            g_state = STATE_CYCLE_COMPLETE;
            return;
           }
        }

      // Trail the Opposite Pending Buy Stop Order
      if(buy_stop_orders > 0)
        {
         TrailOppositeBuyStop(sell_pos_open_price, buy_stop_ticket, buy_stop_price);
        }
     }
   else if(buy_positions == 0 && sell_positions == 0)
     {
      // No active positions: check pending straddle expiry
      if(buy_stop_orders > 0 && sell_stop_orders > 0)
        {
         g_state = STATE_STRADDLE_PLACED;
         if(InpPendingExpiryMinutes > 0 && g_straddle_placed_time > 0)
           {
            if(TimeCurrent() >= g_straddle_placed_time + InpPendingExpiryMinutes * 60)
              {
               PrintFormat("⏰ [Straddle Expired] Orders unfilled after %d minutes -> Canceling pending orders.", InpPendingExpiryMinutes);
               DeleteAllPendingOrders("Straddle Orders Timeout");
               g_state = STATE_IDLE;
              }
           }
        }
      else if(buy_stop_orders == 0 && sell_stop_orders == 0)
        {
         if(g_state == STATE_STRADDLE_PLACED || g_state == STATE_BUY_ACTIVE || g_state == STATE_SELL_ACTIVE)
           {
            g_state = STATE_IDLE;
           }
        }
     }

   if(InpShowPanel)
      UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Trade Transaction Event (Instant Reversal Capture)               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // If a deal was added for our symbol, immediately execute tick check
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == _Symbol)
     {
      OnTick();
     }
  }

//+------------------------------------------------------------------+
//| Handle Market Reversal When Opposite Stop Order Triggers         |
//| User Logic:                                                      |
//| "เมื่อ ราคาย้อนมาชน sell stop ปิด buy เปิด Sell และ วาง Buy stop" |
//+------------------------------------------------------------------+
void HandleOppositeStopReversal(ulong buy_ticket, ulong sell_ticket)
  {
   PrintFormat("⚡ [REVERSAL TRIGGERED] Opposite stop hit! State: %s, BuyTicket: #%I64u, SellTicket: #%I64u",
               EnumToString(g_state), buy_ticket, sell_ticket);

   double point  = g_sym.Point();
   int    digits = g_sym.Digits();
   double rev_distance = (InpReverseDistancePoints > 0.0) ? InpReverseDistancePoints : InpStraddleDistancePoints;

   long stop_level_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double safe_distance_pts = MathMax(rev_distance, (double)stop_level_pts + 10.0);

   if(g_state == STATE_BUY_ACTIVE || g_state == STATE_STRADDLE_PLACED)
     {
      // Previous position was BUY, broker just triggered the SELL STOP!
      // Step 1: Close the previous BUY position immediately
      PrintFormat("🔄 [Reversal Event #%d] Closing old BUY position #%I64u and holding new SELL position #%I64u",
                  g_reversal_count + 1, buy_ticket, sell_ticket);
      g_trade.PositionClose(buy_ticket, InpSlippage);

      g_reversal_count++;

      // Step 2: Check Max Reversals limit
      if(InpMaxReversals > 0 && g_reversal_count >= InpMaxReversals)
        {
         PrintFormat("🛑 Max Reversals (%d) reached! Applying OnMaxReversals policy.", InpMaxReversals);
         if(InpOnMaxReversals == ON_MAX_CLOSE_ALL)
           {
            g_trade.PositionClose(sell_ticket, InpSlippage);
            g_state = STATE_CYCLE_COMPLETE;
            DeleteAllPendingOrders("Max Reversals Reached");
            return;
           }
         else
           {
            // Apply hard SL on current Sell position and do not place new Buy Stop
            double sl = NormalizeDouble(g_sym.Ask() + safe_distance_pts * point, digits);
            g_trade.PositionModify(sell_ticket, sl, 0.0);
            g_state = STATE_SELL_ACTIVE;
            return;
           }
        }

      // Step 3: Place NEW BUY STOP above current Ask to act as SL & Next Reversal
      double next_lot = CalculateLot(g_reversal_count);
      double new_buy_stop_price = NormalizeDouble(g_sym.Ask() + safe_distance_pts * point, digits);

      string comment = StringFormat("%s_Rev%d", InpTradeComment, g_reversal_count);
      bool ok = g_trade.BuyStop(next_lot, new_buy_stop_price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, comment);
      if(ok)
        {
         PrintFormat("✅ Placed New BUY STOP #%I64u at %.5f (Lot: %.2f) acting as SL & Reversal",
                     g_trade.ResultOrder(), new_buy_stop_price, next_lot);
         g_state = STATE_SELL_ACTIVE;
        }
      else
        {
         PrintFormat("❌ Failed to place new BUY STOP: Error %d (%s)", GetLastError(), g_trade.ResultRetcodeDescription());
        }
     }
   else if(g_state == STATE_SELL_ACTIVE)
     {
      // Previous position was SELL, broker just triggered the BUY STOP!
      // Step 1: Close the previous SELL position immediately
      PrintFormat("🔄 [Reversal Event #%d] Closing old SELL position #%I64u and holding new BUY position #%I64u",
                  g_reversal_count + 1, sell_ticket, buy_ticket);
      g_trade.PositionClose(sell_ticket, InpSlippage);

      g_reversal_count++;

      // Step 2: Check Max Reversals limit
      if(InpMaxReversals > 0 && g_reversal_count >= InpMaxReversals)
        {
         PrintFormat("🛑 Max Reversals (%d) reached! Applying OnMaxReversals policy.", InpMaxReversals);
         if(InpOnMaxReversals == ON_MAX_CLOSE_ALL)
           {
            g_trade.PositionClose(buy_ticket, InpSlippage);
            g_state = STATE_CYCLE_COMPLETE;
            DeleteAllPendingOrders("Max Reversals Reached");
            return;
           }
         else
           {
            // Apply hard SL on current Buy position and do not place new Sell Stop
            double sl = NormalizeDouble(g_sym.Bid() - safe_distance_pts * point, digits);
            g_trade.PositionModify(buy_ticket, sl, 0.0);
            g_state = STATE_BUY_ACTIVE;
            return;
           }
        }

      // Step 3: Place NEW SELL STOP below current Bid to act as SL & Next Reversal
      double next_lot = CalculateLot(g_reversal_count);
      double new_sell_stop_price = NormalizeDouble(g_sym.Bid() - safe_distance_pts * point, digits);

      string comment = StringFormat("%s_Rev%d", InpTradeComment, g_reversal_count);
      bool ok = g_trade.SellStop(next_lot, new_sell_stop_price, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, comment);
      if(ok)
        {
         PrintFormat("✅ Placed New SELL STOP #%I64u at %.5f (Lot: %.2f) acting as SL & Reversal",
                     g_trade.ResultOrder(), new_sell_stop_price, next_lot);
         g_state = STATE_BUY_ACTIVE;
        }
      else
        {
         PrintFormat("❌ Failed to place new SELL STOP: Error %d (%s)", GetLastError(), g_trade.ResultRetcodeDescription());
        }
     }
  }

//+------------------------------------------------------------------+
//| Trail Pending Sell Stop UPWARDS as BUY Position Profit Increases  |
//| User Logic:                                                      |
//| "Buy 4000 ราคาขึ้นไป 4001 ขยับ sell stop ขึ้นมา 4000              |
//|  ราคาไปต่อก็ก็ขยับขึ้นตามมาเรื่อยๆ"                                |
//+------------------------------------------------------------------+
void TrailOppositeSellStop(double buy_open_price, ulong sell_stop_ticket, double current_sell_stop_price)
  {
   double point  = g_sym.Point();
   int    digits = g_sym.Digits();
   double bid    = g_sym.Bid();

   double profit_pts = (bid - buy_open_price) / point;
   if(profit_pts < InpTrailingStartPoints)
      return; // Not reached trailing activation threshold

   // Calculate target Sell Stop price
   double target_price = NormalizeDouble(bid - InpTrailingDistancePoints * point, digits);

   // Respect broker minimum StopLevel
   long stop_level_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_dist = MathMax((double)stop_level_pts + 5.0, 5.0) * point;

   if(bid - target_price < min_stop_dist)
      target_price = NormalizeDouble(bid - min_stop_dist, digits);

   // Sell Stop can ONLY MOVE UP! Never move down!
   if(target_price >= current_sell_stop_price + InpTrailingStepPoints * point)
     {
      bool res = g_trade.OrderModify(sell_stop_ticket, target_price, 0.0, 0.0, ORDER_TIME_GTC, 0);
      if(res)
        {
         PrintFormat("📈 [Trail Sell Stop] Trailed Sell Stop #%I64u UP: %.5f -> %.5f (Bid: %.5f, Floating: +%.1f pts)",
                     sell_stop_ticket, current_sell_stop_price, target_price, bid, profit_pts);
        }
     }
  }

//+------------------------------------------------------------------+
//| Trail Pending Buy Stop DOWNWARDS as SELL Position Profit Rises   |
//+------------------------------------------------------------------+
void TrailOppositeBuyStop(double sell_open_price, ulong buy_stop_ticket, double current_buy_stop_price)
  {
   double point  = g_sym.Point();
   int    digits = g_sym.Digits();
   double ask    = g_sym.Ask();

   double profit_pts = (sell_open_price - ask) / point;
   if(profit_pts < InpTrailingStartPoints)
      return; // Not reached trailing activation threshold

   // Calculate target Buy Stop price
   double target_price = NormalizeDouble(ask + InpTrailingDistancePoints * point, digits);

   // Respect broker minimum StopLevel
   long stop_level_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double min_stop_dist = MathMax((double)stop_level_pts + 5.0, 5.0) * point;

   if(target_price - ask < min_stop_dist)
      target_price = NormalizeDouble(ask + min_stop_dist, digits);

   // Buy Stop can ONLY MOVE DOWN! Never move up!
   if(target_price <= current_buy_stop_price - InpTrailingStepPoints * point)
     {
      bool res = g_trade.OrderModify(buy_stop_ticket, target_price, 0.0, 0.0, ORDER_TIME_GTC, 0);
      if(res)
        {
         PrintFormat("📉 [Trail Buy Stop] Trailed Buy Stop #%I64u DOWN: %.5f -> %.5f (Ask: %.5f, Floating: +%.1f pts)",
                     buy_stop_ticket, current_buy_stop_price, target_price, ask, profit_pts);
        }
     }
  }

//+------------------------------------------------------------------+
//| Count Open Positions for this EA Symbol & Magic                  |
//+------------------------------------------------------------------+
int CountOurPositions()
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
//| Count Pending Orders for this EA Symbol & Magic                  |
//+------------------------------------------------------------------+
int CountOurPendingOrders()
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Place Initial Straddle Pending Orders (Buy Stop & Sell Stop)     |
//+------------------------------------------------------------------+
bool PlaceStraddleOrders(string trigger_source)
  {
   if(!g_sym.RefreshRates()) return false;

   // Prevent duplicate order placement if positions or orders already exist
   if(CountOurPositions() > 0 || CountOurPendingOrders() > 0)
     {
      PrintFormat("⚠️ [Straddle Placement] Orders or positions already exist for Magic %I64u on %s. Placement aborted.",
                  InpMagicNumber, _Symbol);
      return false;
     }

   double point  = g_sym.Point();
   int    digits = g_sym.Digits();
   double ask    = g_sym.Ask();
   double bid    = g_sym.Bid();

   // 1. Spread Filter
   double spread = (ask - bid) / point;
   if(InpMaxSpreadPoints > 0.0 && spread > InpMaxSpreadPoints)
     {
      PrintFormat("⚠️ [Spread Filter] Spread %.1f pts exceeds limit %.1f pts! Order placement aborted.",
                  spread, InpMaxSpreadPoints);
      return false;
     }

   // 2. Broker StopLevel Validation
   long stop_level_pts = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double safe_distance_pts = MathMax(InpStraddleDistancePoints, (double)stop_level_pts + 10.0);

   double buy_stop_price  = NormalizeDouble(ask + safe_distance_pts * point, digits);
   double sell_stop_price = NormalizeDouble(bid - safe_distance_pts * point, digits);

   double lot = CalculateLot(0);
   if(lot <= 0.0) return false;

   datetime expiry = 0;
   if(InpPendingExpiryMinutes > 0)
      expiry = TimeCurrent() + InpPendingExpiryMinutes * 60;

   ENUM_ORDER_TYPE_TIME type_time = (expiry > 0) ? ORDER_TIME_SPECIFIED : ORDER_TIME_GTC;

   PrintFormat("🚀 [Placing Straddle Orders] Source: %s | Distance: %.1f pts | Lot: %.2f | Ask: %.5f | Bid: %.5f",
               trigger_source, safe_distance_pts, lot, ask, bid);

   // Place Buy Stop
   bool buy_ok = g_trade.BuyStop(lot, buy_stop_price, _Symbol, 0.0, 0.0, type_time, expiry, InpTradeComment + "_BuyStop");
   if(!buy_ok)
     {
      PrintFormat("❌ Failed BuyStop: %d (%s)", GetLastError(), g_trade.ResultRetcodeDescription());
      return false;
     }

   // Place Sell Stop
   bool sell_ok = g_trade.SellStop(lot, sell_stop_price, _Symbol, 0.0, 0.0, type_time, expiry, InpTradeComment + "_SellStop");
   if(!sell_ok)
     {
      PrintFormat("❌ Failed SellStop: %d (%s). Canceling placed BuyStop...", GetLastError(), g_trade.ResultRetcodeDescription());
      DeleteAllPendingOrders("Rollback unpaired BuyStop");
      return false;
     }

   g_state                = STATE_STRADDLE_PLACED;
   g_reversal_count       = 0;
   g_straddle_placed_time = TimeCurrent();

   PrintFormat("✅ Straddle Placed Successfully! BuyStop @ %.5f, SellStop @ %.5f", buy_stop_price, sell_stop_price);
   return true;
  }

//+------------------------------------------------------------------+
//| Calculate Order Lot Size (Supports Fixed & Risk % + Reversal)    |
//+------------------------------------------------------------------+
double CalculateLot(int reversal_step)
  {
   double base_lot = InpFixedLot;

   if(InpLotMode == LOT_RISK_PERCENT && InpRiskPercent > 0.0)
     {
      double balance = g_acc.Balance();
      double risk_money = balance * (InpRiskPercent / 100.0);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_value > 0.0 && tick_size > 0.0)
        {
         double point_value = tick_value * (g_sym.Point() / tick_size);
         double stop_pts    = InpStraddleDistancePoints;
         double calculated  = risk_money / (stop_pts * point_value);
         if(calculated > 0.0)
            base_lot = calculated;
        }
     }

   // Apply Reversal Multiplier
   double final_lot = base_lot * MathPow(InpReverseMultiplier, reversal_step);

   // Broker Volume Clamp
   double min_vol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_vol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step_vol > 0.0)
      final_lot = MathFloor(final_lot / step_vol) * step_vol;

   final_lot = MathMax(min_vol, MathMin(max_vol, final_lot));
   return NormalizeDouble(final_lot, 2);
  }

//+------------------------------------------------------------------+
//| Close All Positions and Delete Pending Orders                    |
//+------------------------------------------------------------------+
void CloseAllPositionsAndOrders(string reason)
  {
   PrintFormat("🚨 [CloseAll] Executing Emergency/Target Close. Reason: %s", reason);

   // Close Positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
        {
         g_trade.PositionClose(g_pos.Ticket(), InpSlippage);
        }
     }

   // Delete Pending Orders
   DeleteAllPendingOrders(reason);
  }

//+------------------------------------------------------------------+
//| Delete All Pending Orders Only                                   |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders(string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
        {
         g_trade.OrderDelete(g_ord.Ticket());
        }
     }
  }

//+------------------------------------------------------------------+
//| Check and Enforce Drawdown & Daily Capital Protection            |
//+------------------------------------------------------------------+
void CheckDrawdownProtection()
  {
   datetime now = TimeCurrent();
   string today_str = TimeToString(now, TIME_DATE);
   datetime today_midnight = StringToTime(today_str + " 00:00");

   // Daily reset at 00:00
   if(g_last_daily_reset_date != today_midnight)
     {
      g_last_daily_reset_date = today_midnight;
      g_dd_tripped            = false;
     }

   double balance = g_acc.Balance();
   if(balance <= 0.0) return;

   // Calculate Floating Loss for this EA
   double floating = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() == InpMagicNumber && g_pos.Symbol() == _Symbol)
        {
         floating += (g_pos.Profit() + g_pos.Swap());
        }
     }
   g_floating_pl     = floating;
   g_floating_dd_pct = (floating < 0.0) ? (MathAbs(floating) / balance) * 100.0 : 0.0;

   // Calculate Realized Loss for Today
   double today_realized = 0.0;
   if(HistorySelect(today_midnight, now))
     {
      int total_deals = HistoryDealsTotal();
      for(int i = 0; i < total_deals; i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber) continue;
         if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

         today_realized += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP);
        }
     }
   g_today_realized_pl = today_realized;
   double today_loss   = (today_realized < 0.0 ? MathAbs(today_realized) : 0.0) + (floating < 0.0 ? MathAbs(floating) : 0.0);
   g_today_loss_pct    = (today_loss / balance) * 100.0;

   if(!InpEnableDDProtection) return;

   bool breach_total = (InpMaxTotalDDPercent > 0.0 && g_floating_dd_pct >= InpMaxTotalDDPercent);
   bool breach_daily = (InpMaxDailyLossPercent > 0.0 && g_today_loss_pct >= InpMaxDailyLossPercent);

   if(breach_total || breach_daily)
     {
      if(!g_dd_tripped)
        {
         string msg = breach_total ? StringFormat("Total Floating DD %.2f%% reached limit %.2f%%", g_floating_dd_pct, InpMaxTotalDDPercent)
                                   : StringFormat("Daily Total Loss %.2f%% reached limit %.2f%%", g_today_loss_pct, InpMaxDailyLossPercent);
         PrintFormat("🚨 [Capital Protection Breach] %s -> Executing emergency close!", msg);
         g_dd_tripped = true;
         CloseAllPositionsAndOrders(msg);
         g_state = STATE_CYCLE_COMPLETE;
        }
     }
  }

//+------------------------------------------------------------------+
//| Parse News DateTime Input String                                 |
//+------------------------------------------------------------------+
datetime ParseNewsDateTime(string time_str)
  {
   StringTrimLeft(time_str);
   StringTrimRight(time_str);

   // Check if user provided full date e.g. "2026.09.04 15:30:00"
   if(StringFind(time_str, ".") >= 0 || StringFind(time_str, "-") >= 0 || StringFind(time_str, "/") >= 0)
     {
      datetime dt = StringToTime(time_str);
      if(dt > 0) return dt;
     }

   // Format is "HH:MM:SS" or "HH:MM" -> prepend today's date
   string today_date = TimeToString(TimeCurrent(), TIME_DATE);
   datetime res = StringToTime(today_date + " " + time_str);
   return res;
  }

//+------------------------------------------------------------------+
//| Handle Chart Events (Interactive GUI Buttons)                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == PANEL_PREFIX + "BtnArm")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ChartRedraw();
      if(CountOurPositions() > 0 || CountOurPendingOrders() > 0)
        {
         Print("⚠️ [GUI] Orders or positions already active for this EA! Action ignored.");
         return;
        }
      Print("🖱️ [GUI] User clicked [ARM / PLACE STRADDLE NOW]");
      PlaceStraddleOrders("Manual Chart Button");
     }
   else if(sparam == PANEL_PREFIX + "BtnCloseAll")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ChartRedraw();
      Print("🖱️ [GUI] User clicked [CLOSE ALL & RESET]");
      CloseAllPositionsAndOrders("Manual Chart Button Click");
      g_state          = STATE_IDLE;
      g_reversal_count = 0;
     }
   else if(sparam == PANEL_PREFIX + "BtnCancelPending")
     {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ChartRedraw();
      Print("🖱️ [GUI] User clicked [CANCEL PENDING]");
      DeleteAllPendingOrders("Manual Cancel Button");
      if(CountOurPositions() == 0)
        {
         g_state          = STATE_IDLE;
         g_reversal_count = 0;
        }
     }
  }

//+------------------------------------------------------------------+
//| Create Dashboard UI                                              |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   int x = InpPanelX;
   int y = InpPanelY;
   int width = 310;
   int height = 260;

   // Main Panel Background
   CreateRect(PANEL_PREFIX + "BG", x, y, width, height, C'20,24,33', C'45,55,72', 2);

   // Header Banner
   CreateRect(PANEL_PREFIX + "Header", x + 2, y + 2, width - 4, 32, C'30,37,50', C'30,37,50', 1);
   CreateLabel(PANEL_PREFIX + "Title", x + 10, y + 8, "⚡ ZERITH NEWS STRADDLE EA", "Arial Bold", 10, C'255,215,0');

   // Status & Metrics
   int row_y = y + 42;
   CreateLabel(PANEL_PREFIX + "LblState",     x + 12, row_y,      "Status: IDLE",               "Arial", 9, clrWhite);
   CreateLabel(PANEL_PREFIX + "LblSpread",    x + 12, row_y + 18, "Spread: 0.0 pts",           "Arial", 9, C'180,195,210');
   CreateLabel(PANEL_PREFIX + "LblProfit",    x + 12, row_y + 36, "Floating P/L: $0.00",       "Arial", 9, clrWhite);
   CreateLabel(PANEL_PREFIX + "LblReversals", x + 12, row_y + 54, "Reversals: 0 / 5",          "Arial", 9, C'180,195,210');
   CreateLabel(PANEL_PREFIX + "LblStopOrder", x + 12, row_y + 72, "Trailing Stop: None",       "Arial", 9, C'0,210,255');
   CreateLabel(PANEL_PREFIX + "LblNewsTime",  x + 12, row_y + 90, "News: Standby",             "Arial", 9, C'180,195,210');

   // Interactive Buttons
   int btn_y = y + 158;
   int btn_w = 90;
   int btn_h = 26;

   CreateButton(PANEL_PREFIX + "BtnArm",           x + 10,       btn_y, btn_w + 35, btn_h, "🚀 PLACE NOW", C'34,139,34', clrWhite);
   CreateButton(PANEL_PREFIX + "BtnCancelPending", x + 150,      btn_y, btn_w + 55, btn_h, "❌ CANCEL PENDING", C'180,90,0', clrWhite);
   CreateButton(PANEL_PREFIX + "BtnCloseAll",      x + 10, btn_y + 32, width - 20, btn_h + 4, "🛑 CLOSE ALL & RESET", C'178,34,34', clrWhite);

   // Footer
   CreateLabel(PANEL_PREFIX + "Footer", x + 12, y + height - 20, "Zerith Architecture • MT5 Native", "Arial", 8, C'100,115,130');
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Update Dashboard UI Labels                                       |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowPanel) return;

   // 1. Status String
   string state_str = "IDLE";
   color  state_col = clrDarkGray;

   switch(g_state)
     {
      case STATE_IDLE:
         state_str = "IDLE (Standby)";
         state_col = C'180,180,180';
         break;
      case STATE_ARMED:
         state_str = "ARMED (Waiting for News)";
         state_col = C'255,180,0';
         break;
      case STATE_STRADDLE_PLACED:
         state_str = "STRADDLE PENDING (Waiting Breakout)";
         state_col = C'0,210,255';
         break;
      case STATE_BUY_ACTIVE:
         state_str = "BUY RUNNING (Trailing Sell Stop)";
         state_col = C'50,220,100';
         break;
      case STATE_SELL_ACTIVE:
         state_str = "SELL RUNNING (Trailing Buy Stop)";
         state_col = C'255,100,100';
         break;
      case STATE_CYCLE_COMPLETE:
         state_str = "CYCLE COMPLETE";
         state_col = C'200,150,255';
         break;
     }

   if(g_dd_tripped)
     {
      state_str = "🛑 DD PROTECTION TRIPPED";
      state_col = clrRed;
     }

   ObjectSetString(0, PANEL_PREFIX + "LblState", OBJPROP_TEXT, "Status: " + state_str);
   ObjectSetInteger(0, PANEL_PREFIX + "LblState", OBJPROP_COLOR, state_col);

   // 2. Spread
   double spread = (g_sym.Ask() - g_sym.Bid()) / g_sym.Point();
   ObjectSetString(0, PANEL_PREFIX + "LblSpread", OBJPROP_TEXT,
                   StringFormat("Spread: %.1f pts (Max Allowed: %.1f)", spread, InpMaxSpreadPoints));

   // 3. Floating P/L
   color pl_col = (g_floating_pl >= 0.0) ? C'50,220,100' : C'255,90,90';
   ObjectSetString(0, PANEL_PREFIX + "LblProfit", OBJPROP_TEXT,
                   StringFormat("Floating P/L: $%.2f (Today Net: $%.2f)", g_floating_pl, g_today_realized_pl));
   ObjectSetInteger(0, PANEL_PREFIX + "LblProfit", OBJPROP_COLOR, pl_col);

   // 4. Reversals
   string rev_text = StringFormat("Reversals: %d / %d (Multiplier: %.2fx)",
                                  g_reversal_count, InpMaxReversals, InpReverseMultiplier);
   ObjectSetString(0, PANEL_PREFIX + "LblReversals", OBJPROP_TEXT, rev_text);

   // 5. Trailing Stop Status
   string stop_info = "Opposite Stop: None";
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!g_ord.SelectByIndex(i)) continue;
      if(g_ord.Magic() == InpMagicNumber && g_ord.Symbol() == _Symbol)
        {
         if(g_ord.OrderType() == ORDER_TYPE_SELL_STOP)
            stop_info = StringFormat("Opposite SellStop: %.5f", g_ord.PriceOpen());
         else if(g_ord.OrderType() == ORDER_TYPE_BUY_STOP)
            stop_info = StringFormat("Opposite BuyStop: %.5f", g_ord.PriceOpen());
        }
     }
   ObjectSetString(0, PANEL_PREFIX + "LblStopOrder", OBJPROP_TEXT, stop_info);

   // 6. News Countdown
   string news_info = "Mode: " + (InpTriggerMode == TRIGGER_MANUAL_BUTTON ? "Manual" : (InpTriggerMode == TRIGGER_IMMEDIATE ? "Immediate" : "Scheduled"));
   if(InpTriggerMode == TRIGGER_SCHEDULED_TIME && g_scheduled_news_datetime > 0)
     {
      long sec_left = (long)(g_scheduled_news_datetime - TimeCurrent());
      if(sec_left > 0)
        {
         int m = (int)(sec_left / 60);
         int s = (int)(sec_left % 60);
         news_info = StringFormat("News in: %02d:%02d (%s)", m, s, TimeToString(g_scheduled_news_datetime, TIME_SECONDS));
        }
      else
        {
         news_info = "News Time Elapsed";
        }
     }
   ObjectSetString(0, PANEL_PREFIX + "LblNewsTime", OBJPROP_TEXT, news_info);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| GUI Helper Functions                                             |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, color border, int border_w)
  {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, border_w);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void CreateLabel(string name, int x, int y, string text, string font, int font_size, color col)
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color col)
  {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DestroyDashboard()
  {
   ObjectsDeleteAll(0, PANEL_PREFIX);
   ChartRedraw();
  }
//+------------------------------------------------------------------+
