//+------------------------------------------------------------------+
//|                                Zerith_SBR_Liquidity_Sweep_EA.mq5 |
//|          Zerith Series / Smart Money Concepts (SMC) Architecture |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / BlamzKunG Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.00"
#property description "Zerith SBR/RBS + Classic A/V + Liquidity Sweep MT5 EA"
#property description "Smart Money Concepts (SMC) Multi-Timeframe Reversal System"
#property description "HTF SBR/RBS Flip Zones with LTF Liquidity Sweep & Classic A/V Reversal Trigger"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                     |
//+------------------------------------------------------------------+
enum ENUM_LOT_MODE
  {
   LOT_MODE_RISK_PERCENT = 0, // Risk % Per Trade (Equity Based)
   LOT_MODE_FIXED        = 1, // Fixed Lot Size
   LOT_MODE_PER_BALANCE  = 2  // Lot Step Per Balance ($)
  };

enum ENUM_ZONE_TYPE
  {
   ZONE_NONE = 0,
   ZONE_SBR  = 1, // Support Becomes Resistance (Sell Zone)
   ZONE_RBS  = 2  // Resistance Becomes Support (Buy Zone)
  };

enum ENUM_TREND_STATE
  {
   TREND_BULLISH = 1,
   TREND_BEARISH = -1,
   TREND_NEUTRAL = 0
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group ">>>> 1. Multi-Timeframe (MTF) & Structure Engine"
input ENUM_TIMEFRAMES   InpHTF                  = PERIOD_H4;         // Higher Timeframe (Structure / SBR / RBS)
input ENUM_TIMEFRAMES   InpLTF                  = PERIOD_M15;        // Lower Timeframe (Sweep & Classic A/V Entry)
input int               InpSwingLeftBars        = 4;                 // HTF Swing Pivot Left Bars
input int               InpSwingRightBars       = 2;                 // HTF Swing Pivot Right Bars
input int               InpMaxScanBarsHTF       = 150;               // HTF Bars to Scan for Market Structure
input double            InpZoneAtrMult          = 0.25;              // Zone Buffer Thickness (x HTF ATR)
input bool              InpOnlyFirstRetest      = true;              // Trade ONLY 1st Retest of Flip Zone (Strict)
input int               InpMaxZoneAgeBars       = 120;               // Max Zone Age (in HTF Bars)

input group ">>>> 2. Liquidity Sweep (Stop Hunt) Mechanics"
input double            InpMinWickPercent       = 45.0;              // Min Wick % of Total Candle (e.g. 45%)
input int               InpMinSweepPoints       = 20;                // Min Points Wick must Pierce Beyond Level
input bool              InpUseVolumeFilter      = false;             // Require Volume Spike on Sweep Bar
input double            InpVolumeMultiplier     = 1.25;              // Volume Spike Threshold (x 20-period SMA)

input group ">>>> 3. Classic A / Classic V Reversal Engine"
input bool              InpRequireClassicAV     = true;              // Require Classic A (Top) / Classic V (Bottom)
input bool              InpRequireEngulfOrPin   = true;              // Require Pin Bar or Engulfing Confirmation
input int               InpAVMomentumBars       = 3;                 // Momentum Bars Leading Into Peak/Trough

input group ">>>> 4. Money Management & Lot Sizing"
input ENUM_LOT_MODE     InpLotMode              = LOT_MODE_RISK_PERCENT; // Lot Sizing Method
input double            InpRiskPercent          = 1.0;               // Risk % Per Trade (if Risk Mode)
input double            InpFixedLot             = 0.01;              // Fixed Lot Size
input double            InpLotPerBalanceStep    = 1000.0;            // Balance Step for 0.01 Lot ($)
input double            InpMaxLotSize           = 10.0;              // Maximum Allowed Lot Size
input int               InpMaxOpenPositions     = 1;                 // Max Allowed Open Positions
input int               InpMaxSpreadPoints      = 50;                // Max Spread Allowed (Points)
input int               InpSlippage             = 10;                // Max Slippage (Points)

input group ">>>> 5. Stop Loss, Take Profit & Trade Management"
input double            InpSLBufferATRMult      = 0.20;              // SL Buffer beyond Sweep Wick (x LTF ATR)
input double            InpRiskRewardRatio      = 2.5;               // Risk:Reward Ratio (e.g. 2.5 = 1:2.5)
input bool              InpMoveToBreakeven      = true;              // Move SL to Breakeven at 1:1 RR
input int               InpBEBufferPoints       = 10;                // Profit Lock-in Buffer for BE (Points)
input bool              InpUseTrailingStop      = false;             // Enable Trailing Stop
input double            InpTrailStartRR         = 1.5;               // Trailing Start Target (RR Multiple)
input int               InpTrailStepPoints      = 50;                // Trailing Step Distance (Points)

input group ">>>> 6. Drawdown & Capital Protection (DD Protection)"
input bool              InpEnableDDProtection   = true;              // Enable Capital Protection
input double            InpMaxDailyLossPercent  = 4.0;               // Max Daily Loss % (Realized + Floating)
input double            InpMaxTotalDDPercent    = 10.0;              // Max Total Floating Drawdown %
input bool              InpCloseAllOnBreach     = true;              // Close All Positions on DD Breach

input group ">>>> 7. Time Filters & System"
input bool              InpTradeFriday          = true;              // Trade on Friday
input bool              InpFridayCloseEarly     = true;              // Stop New Orders on Friday Afternoon
input int               InpFridayStopHour       = 19;                // Friday Stop Hour (Server Time)
input ulong             InpMagicNumber          = 998811;            // EA Magic Number
input string            InpTradeComment         = "Zerith_SMC_Sweep";// Trade Order Comment
input bool              InpDrawChartObjects     = true;              // Draw Zones & Sweep Signals on Chart
input bool              InpShowDashboard        = true;              // Display On-Chart HUD Dashboard

//+------------------------------------------------------------------+
//| INTERNAL STRUCTURES                                              |
//+------------------------------------------------------------------+
struct SSwingPoint
  {
   datetime time;
   double   price;
   bool     is_high;
   int      bar_index;
  };

struct SFlipZone
  {
   ulong           id;
   datetime        formed_time;
   ENUM_ZONE_TYPE  type;          // SBR or RBS
   double          level;         // Original Broken Swing Level
   double          top;           // Upper Bound (Level + Buffer)
   double          bottom;        // Lower Bound (Level - Buffer)
   int             retest_count;  // Count of retests
   bool            is_active;     // True if not broken / expired
   bool            is_traded;     // True if an order has been executed
   string          obj_name;      // Chart rectangle name
  };

//+------------------------------------------------------------------+
//| GLOBAL OBJECTS & STATE VARIABLES                                 |
//+------------------------------------------------------------------+
CTrade         g_trade;
CPositionInfo  g_pos;
CAccountInfo   g_acc;
CSymbolInfo    g_sym;

int            g_htf_atr_handle   = INVALID_HANDLE;
int            g_ltf_atr_handle   = INVALID_HANDLE;
int            g_ltf_vol_ma_handle= INVALID_HANDLE;

datetime       g_last_htf_bar     = 0;
datetime       g_last_ltf_bar     = 0;

SFlipZone      g_active_zones[];
ENUM_TREND_STATE g_htf_trend      = TREND_NEUTRAL;

// Capital & Daily Tracking
datetime       g_last_daily_reset = 0;
double         g_day_start_balance= 0.0;
bool           g_dd_tripped       = false;
string         g_last_signal_msg  = "Waiting for setup...";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_sym.Name(_Symbol))
     {
      Print("[Zerith_SMC] Error initializing SymbolInfo for ", _Symbol);
      return INIT_FAILED;
     }
   g_sym.Refresh();

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(_Symbol);

   // Initialize Indicator Handles
   g_htf_atr_handle = iATR(_Symbol, InpHTF, 14);
   g_ltf_atr_handle = iATR(_Symbol, InpLTF, 14);

   if(InpUseVolumeFilter)
      g_ltf_vol_ma_handle = iMA(_Symbol, InpLTF, 20, 0, MODE_SMA, PRICE_CLOSE);

   if(g_htf_atr_handle == INVALID_HANDLE || g_ltf_atr_handle == INVALID_HANDLE)
     {
      Print("[Zerith_SMC] Error initializing ATR handles");
      return INIT_FAILED;
     }

   g_day_start_balance = g_acc.Balance();
   g_last_daily_reset  = TimeCurrent();

   ArrayResize(g_active_zones, 0);

   // Initial scan of HTF structure
   UpdateHTFMarketStructure();

   if(InpShowDashboard)
      RenderDashboard();

   Print("===============================================================");
   Print(" [Zerith SBR/RBS + Classic A/V + Liquidity Sweep EA] Initialized");
   Print(" Symbol: ", _Symbol, " | HTF: ", EnumToString(InpHTF), " | LTF: ", EnumToString(InpLTF));
   Print(" Magic: ", InpMagicNumber, " | Risk: ", InpRiskPercent, "%");
   Print("===============================================================");

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_htf_atr_handle != INVALID_HANDLE)    IndicatorRelease(g_htf_atr_handle);
   if(g_ltf_atr_handle != INVALID_HANDLE)    IndicatorRelease(g_ltf_atr_handle);
   if(g_ltf_vol_ma_handle != INVALID_HANDLE) IndicatorRelease(g_ltf_vol_ma_handle);

   // Cleanup Chart Objects created by EA
   if(InpDrawChartObjects)
     {
      ObjectsDeleteAll(0, "Zerith_Zone_");
      ObjectsDeleteAll(0, "Zerith_Sig_");
     }

   Comment("");
  }

//+------------------------------------------------------------------+
//| Check Daily Reset & Drawdown Protections                         |
//+------------------------------------------------------------------+
void CheckDailyReset()
  {
   MqlDateTime dt_curr, dt_last;
   TimeToStruct(TimeCurrent(), dt_curr);
   TimeToStruct(g_last_daily_reset, dt_last);

   if(dt_curr.day != dt_last.day)
     {
      g_day_start_balance = g_acc.Balance();
      g_last_daily_reset  = TimeCurrent();
      g_dd_tripped        = false;
      Print("[Zerith_SMC] New trading day detected. Daily balance baseline reset to: $", DoubleToString(g_day_start_balance, 2));
     }
  }

bool CheckDrawdownProtections()
  {
   if(!InpEnableDDProtection) return false;

   double balance = g_acc.Balance();
   double equity  = g_acc.Equity();

   // 1. Total Floating Drawdown Check
   if(balance > 0.0)
     {
      double total_dd_pct = ((balance - equity) / balance) * 100.0;
      if(total_dd_pct >= InpMaxTotalDDPercent)
        {
         g_dd_tripped = true;
         PrintFormat("[Zerith_SMC] [EMERGENCY] Max Total DD breach: %.2f%% >= %.2f%%. Stopping trading.", total_dd_pct, InpMaxTotalDDPercent);
         if(InpCloseAllOnBreach) CloseAllPositions();
         return true;
        }
     }

   // 2. Daily Loss Limit Check
   if(g_day_start_balance > 0.0)
     {
      double daily_loss = g_day_start_balance - equity;
      double daily_loss_pct = (daily_loss / g_day_start_balance) * 100.0;

      if(daily_loss_pct >= InpMaxDailyLossPercent)
        {
         g_dd_tripped = true;
         PrintFormat("[Zerith_SMC] [EMERGENCY] Max Daily Loss breach: %.2f%% >= %.2f%%. Stopping trading for today.", daily_loss_pct, InpMaxDailyLossPercent);
         if(InpCloseAllOnBreach) CloseAllPositions();
         return true;
        }
     }

   return false;
  }

void CloseAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i))
        {
         if(g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
           {
            g_trade.PositionClose(g_pos.Ticket());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Forward Declarations                                             |
//+------------------------------------------------------------------+
void UpdateHTFMarketStructure();
void AddOrUpdateFlipZone(ENUM_ZONE_TYPE type, double level, double buffer, datetime formed_time);
void CleanupZones();
void ScanForEntrySignals();
double CalculateLotSize(double sl_distance_points);
void ManageActiveTrades();
int CountOpenPositions();
void DrawZonesOnChart();
void DrawSignalArrow(datetime time, double price, bool is_buy, string text);
void RenderDashboard();

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_sym.RefreshRates();
   CheckDailyReset();

   // Check Drawdown Breaches
   if(CheckDrawdownProtections() || g_dd_tripped)
     {
      if(InpShowDashboard) RenderDashboard();
      return;
     }

   // 1. Active Trade Management (BE & Trailing Stop) - runs on every tick
   ManageActiveTrades();

   // 2. Check for New HTF Bar -> Update Structure & Flip Zones
   datetime htf_time = iTime(_Symbol, InpHTF, 0);
   if(htf_time != g_last_htf_bar)
     {
      g_last_htf_bar = htf_time;
      UpdateHTFMarketStructure();
     }

   // 3. Check for New LTF Bar -> Scan for Liquidity Sweeps & Classic A/V
   datetime ltf_time = iTime(_Symbol, InpLTF, 0);
   if(ltf_time != g_last_ltf_bar)
     {
      g_last_ltf_bar = ltf_time;
      ScanForEntrySignals();
     }

   // Update HUD Dashboard
   if(InpShowDashboard)
      RenderDashboard();
  }

//+------------------------------------------------------------------+
//| Update HTF Market Structure & SBR/RBS Flip Zones                 |
//+------------------------------------------------------------------+
void UpdateHTFMarketStructure()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, InpHTF, 0, InpMaxScanBarsHTF, rates);
   if(copied < InpSwingLeftBars + InpSwingRightBars + 10) return;

   // Fetch HTF ATR for dynamic zone buffer
   double atr_val[1];
   if(CopyBuffer(g_htf_atr_handle, 0, 1, 1, atr_val) <= 0) return;
   double zone_buffer = atr_val[0] * InpZoneAtrMult;

   // Detect Swings on HTF
   SSwingPoint swings[];
   ArrayResize(swings, 0);

   for(int i = InpSwingRightBars; i < copied - InpSwingLeftBars; i++)
     {
      bool is_swing_high = true;
      bool is_swing_low  = true;

      // Check Highs
      for(int k = 1; k <= InpSwingLeftBars; k++)
        {
         if(rates[i].high <= rates[i + k].high) { is_swing_high = false; break; }
        }
      if(is_swing_high)
        {
         for(int k = 1; k <= InpSwingRightBars; k++)
           {
            if(rates[i].high < rates[i - k].high) { is_swing_high = false; break; }
           }
        }

      // Check Lows
      for(int k = 1; k <= InpSwingLeftBars; k++)
        {
         if(rates[i].low >= rates[i + k].low) { is_swing_low = false; break; }
        }
      if(is_swing_low)
        {
         for(int k = 1; k <= InpSwingRightBars; k++)
           {
            if(rates[i].low > rates[i - k].low) { is_swing_low = false; break; }
           }
        }

      if(is_swing_high)
        {
         int size = ArraySize(swings);
         ArrayResize(swings, size + 1);
         swings[size].time = rates[i].time;
         swings[size].price = rates[i].high;
         swings[size].is_high = true;
         swings[size].bar_index = i;
        }
      else if(is_swing_low)
        {
         int size = ArraySize(swings);
         ArrayResize(swings, size + 1);
         swings[size].time = rates[i].time;
         swings[size].price = rates[i].low;
         swings[size].is_high = false;
         swings[size].bar_index = i;
        }
     }

   // Detect Break of Structure (BOS) and Flip Zones (SBR / RBS)
   for(int s = 0; s < ArraySize(swings); s++)
     {
      int swing_bar = swings[s].bar_index;
      double swing_price = swings[s].price;

      if(swings[s].is_high)
        {
         for(int b = swing_bar - 1; b >= 1; b--)
           {
            if(rates[b].close > swing_price)
              {
               AddOrUpdateFlipZone(ZONE_RBS, swing_price, zone_buffer, rates[b].time);
               g_htf_trend = TREND_BULLISH;
               break;
              }
           }
        }
      else
        {
         for(int b = swing_bar - 1; b >= 1; b--)
           {
            if(rates[b].close < swing_price)
              {
               AddOrUpdateFlipZone(ZONE_SBR, swing_price, zone_buffer, rates[b].time);
               g_htf_trend = TREND_BEARISH;
               break;
              }
           }
        }
     }

   // Clean up expired or heavily invalidated zones
   CleanupZones();

   // Redraw chart visual objects
   if(InpDrawChartObjects)
      DrawZonesOnChart();
  }

//+------------------------------------------------------------------+
//| Add or update a Flip Zone in the tracking list                   |
//+------------------------------------------------------------------+
void AddOrUpdateFlipZone(ENUM_ZONE_TYPE type, double level, double buffer, datetime formed_time)
  {
   for(int i = 0; i < ArraySize(g_active_zones); i++)
     {
      if(MathAbs(g_active_zones[i].level - level) < buffer * 0.5)
         return; // Zone already tracked
     }

   int size = ArraySize(g_active_zones);
   ArrayResize(g_active_zones, size + 1);

   g_active_zones[size].id           = (ulong)formed_time + (ulong)(level * 1000);
   g_active_zones[size].formed_time  = formed_time;
   g_active_zones[size].type         = type;
   g_active_zones[size].level        = level;
   g_active_zones[size].top          = level + buffer;
   g_active_zones[size].bottom       = level - buffer;
   g_active_zones[size].retest_count = 0;
   g_active_zones[size].is_active    = true;
   g_active_zones[size].is_traded    = false;
   g_active_zones[size].obj_name     = "Zerith_Zone_" + IntegerToString(size) + "_" + (type == ZONE_SBR ? "SBR" : "RBS");
  }

//+------------------------------------------------------------------+
//| Clean up outdated or invalid zones                               |
//+------------------------------------------------------------------+
void CleanupZones()
  {
   double current_bid = g_sym.Bid();
   datetime current_time = TimeCurrent();

   for(int i = ArraySize(g_active_zones) - 1; i >= 0; i--)
     {
      int age_seconds = (int)(current_time - g_active_zones[i].formed_time);
      int max_seconds = InpMaxZoneAgeBars * PeriodSeconds(InpHTF);

      if(age_seconds > max_seconds)
        {
         g_active_zones[i].is_active = false;
        }

      if(g_active_zones[i].type == ZONE_SBR && current_bid > g_active_zones[i].top + (g_active_zones[i].top - g_active_zones[i].bottom))
        {
         g_active_zones[i].is_active = false;
        }
      else if(g_active_zones[i].type == ZONE_RBS && current_bid < g_active_zones[i].bottom - (g_active_zones[i].top - g_active_zones[i].bottom))
        {
         g_active_zones[i].is_active = false;
        }

      if(InpOnlyFirstRetest && g_active_zones[i].retest_count >= 1)
        {
         g_active_zones[i].is_active = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| Scan for Liquidity Sweeps & Classic A/V Patterns on LTF          |
//+------------------------------------------------------------------+
void ScanForEntrySignals()
  {
   if(InpFridayCloseEarly)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.day_of_week == 5 && dt.hour >= InpFridayStopHour)
        {
         g_last_signal_msg = "Friday session lockout";
         return;
        }
     }

   if(CountOpenPositions() >= InpMaxOpenPositions)
     {
      g_last_signal_msg = "Max position reached";
      return;
     }

   if((int)g_sym.Spread() > InpMaxSpreadPoints)
     {
      g_last_signal_msg = "Spread too high: " + IntegerToString((int)g_sym.Spread());
      return;
     }

   MqlRates ltf_rates[];
   ArraySetAsSeries(ltf_rates, true);
   if(CopyRates(_Symbol, InpLTF, 0, InpAVMomentumBars + 5, ltf_rates) < InpAVMomentumBars + 3)
      return;

   MqlRates bar1 = ltf_rates[1];
   MqlRates bar2 = ltf_rates[2];

   double candle_range = bar1.high - bar1.low;
   if(candle_range <= 0.0) return;

   double upper_wick = bar1.high - MathMax(bar1.open, bar1.close);
   double lower_wick = MathMin(bar1.open, bar1.close) - bar1.low;
   double upper_wick_pct = (upper_wick / candle_range) * 100.0;
   double lower_wick_pct = (lower_wick / candle_range) * 100.0;

   double ltf_atr[1];
   if(CopyBuffer(g_ltf_atr_handle, 0, 1, 1, ltf_atr) <= 0) return;
   double sl_atr_buffer = ltf_atr[0] * InpSLBufferATRMult;

   bool volume_ok = true;
   if(InpUseVolumeFilter)
     {
      double vol_ma[1];
      if(CopyBuffer(g_ltf_vol_ma_handle, 0, 1, 1, vol_ma) > 0)
        {
         if((double)bar1.tick_volume < vol_ma[0] * InpVolumeMultiplier)
            volume_ok = false;
        }
     }
   if(!volume_ok) return;

   for(int z = 0; z < ArraySize(g_active_zones); z++)
     {
      if(!g_active_zones[z].is_active) continue;
      if(InpOnlyFirstRetest && g_active_zones[z].retest_count >= 1) continue;

      //=============================================================
      // CASE A: BEARISH REVERSAL (SBR + Classic A + Liquidity Sweep)
      //=============================================================
      if(g_active_zones[z].type == ZONE_SBR)
        {
         bool pierced_level = (bar1.high >= g_active_zones[z].level);
         bool closed_below  = (bar1.close < g_active_zones[z].level);
         bool sweep_dist_ok = (bar1.high - g_active_zones[z].level) >= (InpMinSweepPoints * _Point);

         if(pierced_level && closed_below && sweep_dist_ok)
           {
            if(upper_wick_pct >= InpMinWickPercent)
              {
               bool is_classic_A = true;
               if(InpRequireClassicAV)
                 {
                  bool upward_momentum = (ltf_rates[2].high > ltf_rates[3].high || ltf_rates[2].close > ltf_rates[4].close);
                  bool rejection_candle = (bar1.close < bar1.open) || (upper_wick > candle_range * 0.50);
                  if(!upward_momentum || !rejection_candle) is_classic_A = false;
                 }

               bool candle_ok = true;
               if(InpRequireEngulfOrPin)
                 {
                  bool is_pinbar = (upper_wick_pct >= 50.0);
                  bool is_engulfing = (bar1.close < bar1.open && bar1.close <= bar2.low && bar1.open >= bar2.close);
                  candle_ok = (is_pinbar || is_engulfing);
                 }

               if(is_classic_A && candle_ok)
                 {
                  double sl = bar1.high + sl_atr_buffer + (g_sym.Spread() * _Point);
                  double entry_price = g_sym.Bid();
                  double risk_points = (sl - entry_price) / _Point;

                  if(risk_points > 0)
                    {
                     double tp = entry_price - (risk_points * InpRiskRewardRatio * _Point);
                     double lot = CalculateLotSize(risk_points);

                     if(g_trade.Sell(lot, _Symbol, entry_price, sl, tp, InpTradeComment))
                       {
                        g_active_zones[z].retest_count++;
                        g_active_zones[z].is_traded = true;
                        g_last_signal_msg = "SELL Opened at SBR (" + DoubleToString(g_active_zones[z].level, _Digits) + ")";
                        PrintFormat("[Zerith_SMC] [ENTRY SELL] SBR Sweep confirmed! Level: %.5f | Lots: %.2f | SL: %.5f | TP: %.5f",
                                    g_active_zones[z].level, lot, sl, tp);

                        if(InpDrawChartObjects)
                           DrawSignalArrow(bar1.time, bar1.high, false, "Bearish A-Sweep");
                        return;
                       }
                    }
                 }
              }
           }
        }

      //=============================================================
      // CASE B: BULLISH REVERSAL (RBS + Classic V + Liquidity Sweep)
      //=============================================================
      else if(g_active_zones[z].type == ZONE_RBS)
        {
         bool pierced_level = (bar1.low <= g_active_zones[z].level);
         bool closed_above  = (bar1.close > g_active_zones[z].level);
         bool sweep_dist_ok = (g_active_zones[z].level - bar1.low) >= (InpMinSweepPoints * _Point);

         if(pierced_level && closed_above && sweep_dist_ok)
           {
            if(lower_wick_pct >= InpMinWickPercent)
              {
               bool is_classic_V = true;
               if(InpRequireClassicAV)
                 {
                  bool downward_momentum = (ltf_rates[2].low < ltf_rates[3].low || ltf_rates[2].close < ltf_rates[4].close);
                  bool rebound_candle = (bar1.close > bar1.open) || (lower_wick > candle_range * 0.50);
                  if(!downward_momentum || !rebound_candle) is_classic_V = false;
                 }

               bool candle_ok = true;
               if(InpRequireEngulfOrPin)
                 {
                  bool is_pinbar = (lower_wick_pct >= 50.0);
                  bool is_engulfing = (bar1.close > bar1.open && bar1.close >= bar2.high && bar1.open <= bar2.close);
                  candle_ok = (is_pinbar || is_engulfing);
                 }

               if(is_classic_V && candle_ok)
                 {
                  double sl = bar1.low - sl_atr_buffer;
                  double entry_price = g_sym.Ask();
                  double risk_points = (entry_price - sl) / _Point;

                  if(risk_points > 0)
                    {
                     double tp = entry_price + (risk_points * InpRiskRewardRatio * _Point);
                     double lot = CalculateLotSize(risk_points);

                     if(g_trade.Buy(lot, _Symbol, entry_price, sl, tp, InpTradeComment))
                       {
                        g_active_zones[z].retest_count++;
                        g_active_zones[z].is_traded = true;
                        g_last_signal_msg = "BUY Opened at RBS (" + DoubleToString(g_active_zones[z].level, _Digits) + ")";
                        PrintFormat("[Zerith_SMC] [ENTRY BUY] RBS Sweep confirmed! Level: %.5f | Lots: %.2f | SL: %.5f | TP: %.5f",
                                    g_active_zones[z].level, lot, sl, tp);

                        if(InpDrawChartObjects)
                           DrawSignalArrow(bar1.time, bar1.low, true, "Bullish V-Sweep");
                        return;
                       }
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Money Management Mode                |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance_points)
  {
   double lot = InpFixedLot;

   if(InpLotMode == LOT_MODE_FIXED)
     {
      lot = InpFixedLot;
     }
   else if(InpLotMode == LOT_MODE_PER_BALANCE)
     {
      double balance = g_acc.Balance();
      lot = (balance / InpLotPerBalanceStep) * 0.01;
     }
   else if(InpLotMode == LOT_MODE_RISK_PERCENT)
     {
      if(sl_distance_points <= 0.0) return InpFixedLot;

      double equity = g_acc.Equity();
      double risk_amount = equity * (InpRiskPercent / 100.0);

      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(tick_size > 0.0 && tick_value > 0.0)
        {
         double sl_price_dist = sl_distance_points * _Point;
         double num_ticks = sl_price_dist / tick_size;
         double money_per_lot = num_ticks * tick_value;

         if(money_per_lot > 0.0)
            lot = risk_amount / money_per_lot;
        }
     }

   // Normalize lot to broker limits
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lot_step > 0.0)
      lot = MathFloor(lot / lot_step) * lot_step;

   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   if(lot > InpMaxLotSize) lot = InpMaxLotSize;

   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Manage Active Trades (Breakeven & Trailing Stop)                 |
//+------------------------------------------------------------------+
void ManageActiveTrades()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i))
        {
         if(g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
           {
            double open_price = g_pos.PriceOpen();
            double current_sl = g_pos.StopLoss();
            double current_tp = g_pos.TakeProfit();
            double current_price = (g_pos.PositionType() == POSITION_TYPE_BUY) ? g_sym.Bid() : g_sym.Ask();

            double initial_risk_points = MathAbs(open_price - current_sl) / _Point;
            if(initial_risk_points <= 0) continue;

            // 1. Breakeven Management (Move SL to BE at 1:1 RR)
            if(InpMoveToBreakeven)
              {
               if(g_pos.PositionType() == POSITION_TYPE_BUY)
                 {
                  if(current_price >= open_price + (initial_risk_points * _Point))
                    {
                     double new_sl = open_price + (InpBEBufferPoints * _Point);
                     if(current_sl < open_price)
                       {
                        g_trade.PositionModify(g_pos.Ticket(), new_sl, current_tp);
                        PrintFormat("[Zerith_SMC] Breakeven locked for BUY #%I64u at %.5f", g_pos.Ticket(), new_sl);
                       }
                    }
                 }
               else if(g_pos.PositionType() == POSITION_TYPE_SELL)
                 {
                  if(current_price <= open_price - (initial_risk_points * _Point))
                    {
                     double new_sl = open_price - (InpBEBufferPoints * _Point);
                     if(current_sl > open_price || current_sl == 0.0)
                       {
                        g_trade.PositionModify(g_pos.Ticket(), new_sl, current_tp);
                        PrintFormat("[Zerith_SMC] Breakeven locked for SELL #%I64u at %.5f", g_pos.Ticket(), new_sl);
                       }
                    }
                 }
              }

            // 2. Trailing Stop Management
            if(InpUseTrailingStop)
              {
               double trail_target_points = initial_risk_points * InpTrailStartRR;

               if(g_pos.PositionType() == POSITION_TYPE_BUY)
                 {
                  if(current_price >= open_price + (trail_target_points * _Point))
                    {
                     double new_sl = current_price - (InpTrailStepPoints * _Point);
                     if(new_sl > current_sl + (10 * _Point))
                       {
                        g_trade.PositionModify(g_pos.Ticket(), new_sl, current_tp);
                       }
                    }
                 }
               else if(g_pos.PositionType() == POSITION_TYPE_SELL)
                 {
                  if(current_price <= open_price - (trail_target_points * _Point))
                    {
                     double new_sl = current_price + (InpTrailStepPoints * _Point);
                     if(new_sl < current_sl - (10 * _Point) || current_sl == 0.0)
                       {
                        g_trade.PositionModify(g_pos.Ticket(), new_sl, current_tp);
                       }
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Count Open Positions by this EA                                  |
//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(g_pos.SelectByIndex(i))
        {
         if(g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Draw SBR & RBS Zones on the Chart                                |
//+------------------------------------------------------------------+
void DrawZonesOnChart()
  {
   for(int i = 0; i < ArraySize(g_active_zones); i++)
     {
      if(!g_active_zones[i].is_active)
        {
         ObjectDelete(0, g_active_zones[i].obj_name);
         continue;
        }

      string name = g_active_zones[i].obj_name;
      color zone_color = (g_active_zones[i].type == ZONE_SBR) ? clrCrimson : clrMediumSeaGreen;

      if(ObjectFind(0, name) < 0)
        {
         ObjectCreate(0, name, OBJ_RECTANGLE, 0, g_active_zones[i].formed_time, g_active_zones[i].top, TimeCurrent() + 7200, g_active_zones[i].bottom);
         ObjectSetInteger(0, name, OBJPROP_COLOR, zone_color);
         ObjectSetInteger(0, name, OBJPROP_FILL, true);
         ObjectSetInteger(0, name, OBJPROP_BACK, true);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
         string desc = (g_active_zones[i].type == ZONE_SBR ? "[SBR Resistance] " : "[RBS Support] ") + DoubleToString(g_active_zones[i].level, _Digits);
         ObjectSetString(0, name, OBJPROP_TEXT, desc);
        }
      else
        {
         ObjectSetInteger(0, name, OBJPROP_TIME, 1, TimeCurrent() + 7200);
         ObjectSetDouble(0, name, OBJPROP_PRICE, 0, g_active_zones[i].top);
         ObjectSetDouble(0, name, OBJPROP_PRICE, 1, g_active_zones[i].bottom);
        }
     }
  }

//+------------------------------------------------------------------+
//| Draw Signal Arrow on Chart                                       |
//+------------------------------------------------------------------+
void DrawSignalArrow(datetime time, double price, bool is_buy, string text)
  {
   string name = "Zerith_Sig_" + IntegerToString((int)time);
   if(is_buy)
     {
      ObjectCreate(0, name, OBJ_ARROW_UP, 0, time, price - (15 * _Point));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
     }
   else
     {
      ObjectCreate(0, name, OBJ_ARROW_DOWN, 0, time, price + (15 * _Point));
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
     }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

//+------------------------------------------------------------------+
//| Render On-Chart HUD Dashboard                                    |
//+------------------------------------------------------------------+
void RenderDashboard()
  {
   double balance = g_acc.Balance();
   double equity  = g_acc.Equity();
   double dd_pct  = (balance > 0.0) ? ((balance - equity) / balance) * 100.0 : 0.0;
   double day_pnl = equity - g_day_start_balance;

   string trend_str = "NEUTRAL";
   if(g_htf_trend == TREND_BULLISH) trend_str = "BULLISH (RBS Dominant)";
   if(g_htf_trend == TREND_BEARISH) trend_str = "BEARISH (SBR Dominant)";

   int active_sbr = 0, active_rbs = 0;
   for(int i = 0; i < ArraySize(g_active_zones); i++)
     {
      if(g_active_zones[i].is_active)
        {
         if(g_active_zones[i].type == ZONE_SBR) active_sbr++;
         if(g_active_zones[i].type == ZONE_RBS) active_rbs++;
        }
     }

   string dash = "";
   dash += "=========================================================\n";
   dash += " [ZERITH] SBR/RBS + CLASSIC A/V + LIQUIDITY SWEEP EA v1.0\n";
   dash += "=========================================================\n";
   dash += StringFormat(" Symbol: %s | HTF: %s | LTF: %s | Magic: %d\n", _Symbol, EnumToString(InpHTF), EnumToString(InpLTF), InpMagicNumber);
   dash += StringFormat(" HTF Structure Trend: %s\n", trend_str);
   dash += StringFormat(" Active Flip Zones  : %d SBR (Resistance) | %d RBS (Support)\n", active_sbr, active_rbs);
   dash += StringFormat(" Strict Discipline  : %s\n", InpOnlyFirstRetest ? "1st Retest ONLY" : "All Retests");
   dash += "---------------------------------------------------------\n";
   dash += StringFormat(" Account Balance    : $%.2f | Equity: $%.2f\n", balance, equity);
   dash += StringFormat(" Today PnL          : $%.2f\n", day_pnl);
   dash += StringFormat(" Floating Drawdown  : %.2f%% (Limit: %.1f%%)\n", dd_pct, InpMaxTotalDDPercent);
   dash += StringFormat(" Current Spread     : %d pts (Max: %d)\n", (int)g_sym.Spread(), InpMaxSpreadPoints);
   dash += StringFormat(" Open Positions     : %d / %d\n", CountOpenPositions(), InpMaxOpenPositions);
   dash += StringFormat(" Risk / Reward      : 1 : %.1f | Breakeven: %s\n", InpRiskRewardRatio, InpMoveToBreakeven ? "Enabled (1:1 RR)" : "Disabled");
   dash += "---------------------------------------------------------\n";
   dash += StringFormat(" Last Status        : %s\n", g_last_signal_msg);
   dash += "=========================================================";

   Comment(dash);
  }
//+------------------------------------------------------------------+
