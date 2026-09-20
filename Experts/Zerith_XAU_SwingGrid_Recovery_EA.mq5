//+------------------------------------------------------------------+
//|                             Zerith_XAU_SwingGrid_Recovery_EA.mq5 |
//|                 Zerith Series / BlamzKunG                        |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//|  v1.00 - Dynamic Daily Swing & Multi-TF ATR Grid Recovery Engine |
//|  Features: Breakout Initial Entry, Dynamic Daily Swing Spacing,  |
//|            Configurable ATR Gap, Anti-Martingale Deep Lots,       |
//|            Basket Trailing Stop, Staged Partial Close,            |
//|            Breakeven Escape & S/R Level Snapping                 |
//+------------------------------------------------------------------+
#property copyright   "Zerith Series / BlamzKunG"
#property link        "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version     "1.00"
#property description "Zerith XAU SwingGrid Recovery MT5 - Dynamic Daily Swing (Yesterday/10) + Configurable ATR Grid Recovery Engine"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//=====================================================================
// STRUCTS
//=====================================================================
struct TFView
{
   string tf_name;
   int    trend;            // 1: UP, -1: DOWN, 0: NEUTRAL
   double adx_val;
   double atr_val;
   double rsi_val;
   double bb_width;
   double last_close;
   double ema_fast;
   double ema_slow;
   double macd_hist;
   double macd_hist_prev; 
};

struct Signal
{
   string action;           // "BUY", "SELL", "WAIT"
   string strategy;         // "BREAKOUT"
   double confidence;
   string reason;
   int    tp_points;
};

struct SBasketCache
{
   int      count;
   double   lots;
   double   avg_price;
   double   last_price;
   datetime last_time;
   ulong    last_ticket;
   double   last_lot;
   double   profit;
   datetime oldest_time;
};

//=====================================================================
// INPUT PARAMETERS
//=====================================================================

input group ">>>> 1. Trading Basics"
input double   InpInitialLot          = 0.01;         // Initial Entry Lot Size
input int      InpDeviation           = 30;           // Max Slippage (Points)
input long     InpMagic               = 20260601;     // EA Magic Number
input string   InpTradeCommentPrefix  = "ZX_SwingGrid"; // Trade Comment Prefix

input group ">>>> 2. Yesterday Swing & ATR Dynamic Grid Spacing"
input double   InpSwingDivisor        = 10.0;         // Yesterday Swing Divisor (Swing / 10)
input ENUM_TIMEFRAMES InpGridAtrTf    = PERIOD_H1;    // ATR Timeframe for Grid Calculation
input int      InpGridAtrPeriod       = 14;           // ATR Period for Grid Calculation
input double   InpGridAtrMult         = 1.0;          // ATR Multiplier for Grid Spacing
input int      InpGridMinGapPts       = 100;          // Absolute Minimum Grid Gap (Points, 100pts=$1.0)
input int      InpGridMaxGapPts       = 2000;         // Absolute Maximum Grid Gap (Points)
input bool     InpUseLayerGapMultiplier = true;       // Progressive Layer Expansion (+% per layer)
input double   InpLayerGapExpansionPct = 10.0;        // Layer Gap Expansion % (+10% per layer)
input int      InpRecoveryMaxLayers   = 10;           // Maximum Recovery Layers Allowed
input int      InpMaxRecoveryAttempts = 8;            // Maximum Recovery Attempt Limit

input group ">>>> 3. Adaptive Recovery Lot Sizing"
input double   InpLotMultEarly        = 1.3;          // Early Layer Lot Multiplier (Layers 1-2)
input double   InpLotMultMid          = 1.5;          // Mid Layer Lot Multiplier (Layers 3-5)
input double   InpLotMultLate         = 1.3;          // Late Layer Lot Multiplier
input bool     InpAntiMartingaleDeep  = true;         // Enable Deep Anti-Martingale (>=6)
input double   InpDeepLotMult         = 0.8;          // Deep Layer Multiplier (< 1.0)
input double   InpRecoveryMaxLot      = 5.0;          // Absolute Maximum Lot Cap
input double   InpVolNeutralAtr       = 500.0;        // Volatility Neutral ATR Reference (Points)

input group ">>>> 4. Take-Profit & Fast Recovery Exit"
input int      InpTpPointsBase        = 200;          // Base Take-Profit (Points)
input int      InpTpPointsMin         = 50;           // Minimum Take-Profit (Points)
input double   InpTpAtrMult           = 1.0;          // Dynamic ATR TP Multiplier
input bool     InpRecoveryModeEnable  = true;         // Enable Fast Recovery TP at Deep Layers
input int      InpRecoveryModeAtLayer = 4;            // Reduced TP Activation Layer (>=)
input int      InpRecoveryReducedTp   = 40;           // Reduced Fast Exit TP (Points)

input group ">>>> 5. Basket Trailing Stop Engine"
input bool     InpTrailingEnable      = true;         // Enable Basket Trailing Stop
input double   InpTrailingTriggerUsd  = 5.0;          // Trailing Activation Profit ($)
input double   InpTrailingStepUsd     = 2.0;          // Trailing Callback / Step ($)

input group ">>>> 6. Staged Partial Close"
input bool     InpPartialCloseEnable  = true;         // Enable Staged Partial Close
input double   InpPartialCloseAtUsd   = 4.0;          // Profit Trigger per Stage ($)
input double   InpPartialClosePct     = 30.0;         // Volume Percentage to Close (%)
input bool     InpStagedPartialClose  = true;         // Multi-Stage Partial Close
input int      InpPartialCloseLevels  = 2;            // Maximum Partial Close Stages

input group ">>>> 7. Breakeven Escape & Capital Guards"
input bool     InpBreakevenExit       = true;         // Breakeven Exit After Deep Adverse Move
input double   InpBreakevenTriggerUsd = 1.0;          // Breakeven Profit Target ($)
input double   InpBreakevenBufferPts  = 5;            // Breakeven Profit Buffer (Points)
input bool     InpUseBasketStopLoss   = false;        // Enable Hard Basket Stop-Loss ($)
input double   InpMaxBasketLossUsd    = 50.0;         // Basket Hard Stop-Loss ($)
input int      InpBasketMaxAgeHours   = 8;            // Basket Max Holding Time (Hours, 0=Off)
input int      InpMaxSpreadPts        = 50;           // Max Allowed Spread (Points)

input group ">>>> 8. Initial Entry & Trend Filters"
input int      InpTrendAdx            = 25;           // Trend Strength Threshold (ADX)
input bool     InpUseHtfFilter        = true;         // Require H1 Trend Alignment for Initial Entry
input int      InpCooldownSec         = 30;           // Cooldown After Basket Close (Seconds)
input bool     InpWaitNextBarAfterClose = true;       // Wait for Next M1 Bar After Close

input group ">>>> 9. Global Risk & Prop-Firm Guards"
input double   InpDailyTargetUsd      = 100.0;        // Daily Profit Target ($)
input bool     InpUseMaxEquityDdPct   = false;        // Enable Max Equity Drawdown Guard
input double   InpMaxEquityDdPct      = 15.0;         // Max Equity Drawdown Allowed (%)
input bool     InpUseMinFreeMarginPct = false;        // Enable Min Free Margin Guard
input double   InpMinFreeMarginPct    = 30.0;         // Min Free Margin Allowed (%)

input group ">>>> 10. Session & Time Filters"
input bool     InpUseTimeFilter       = false;        // Enable Trading Session Filter
input int      InpAllowHourFrom       = 6;            // Trading Start Hour (UTC)
input int      InpAllowHourTo         = 20;           // Trading End Hour (UTC)
input int      InpServerGMTOffset     = 2;            // Broker Server GMT Offset

input group ">>>> 11. Chart History & Debug"
input int      InpBarsM1              = 150;          // M1 History Bars to Load
input int      InpBarsHTF             = 100;          // Higher TF History Bars to Load
input bool     InpPrintDebug          = false;        // Print Diagnostic Logs

input group ">>>> 12. Visual Dashboard"
input bool     InpShowDashboard       = true;         // Display On-Chart Dashboard
input int      InpDashX               = 20;           // Dashboard X Coordinate
input int      InpDashY               = 30;           // Dashboard Y Coordinate
input bool     InpDashAutoColor       = true;         // Auto Detect Dark/Light Background
input color    InpDashBgColor         = C'18,24,38';  // Dashboard Background Color
input color    InpDashBorderColor     = C'52,152,219';// Dashboard Border Color

//=====================================================================
// GLOBALS
//=====================================================================
bool     g_isTester       = false;
bool     g_isOptimization = false;
bool     g_isVisual       = false;

double   g_volStep        = 0.01;
double   g_volMin         = 0.01;
double   g_volMax         = 100.0;
int      g_stopsLevel     = 0;
double   g_point          = 0.0;
double   g_pointFactor    = 1.0;
int      g_digits         = 2;

SBasketCache g_bStats[2]; // 0: BUY, 1: SELL
CTrade         g_trade;
CPositionInfo  g_pos;
CSymbolInfo    g_sym;

color    g_dashBg         = C'18,24,38';
color    g_dashBorder     = C'52,152,219';

string   g_status         = "INIT";
string   g_regime         = "UNKNOWN";
double   g_resistPx       = 0.0;
double   g_supportPx      = 0.0;
double   g_atrM1          = 0.0;
double   g_atrM1Pts       = 0.0;

// Basket Tracking Variables
double   g_peakProfit[2]  = {0.0, 0.0};
bool     g_trailingActive[2] = {false, false};
int      g_partialStage[2]   = {0, 0};
bool     g_pendingPartialClose[2] = {false, false};
bool     g_recoveryMode[2]   = {false, false};
double   g_maxBasketLoss[2]  = {0.0, 0.0};

datetime g_lastRecBuy     = 0;
datetime g_lastRecSell    = 0;
datetime g_cooldownUntil  = 0;
datetime g_lastCloseTime  = 0;
datetime g_lastOpenBuy    = 0;
datetime g_lastOpenSell   = 0;

// Statistics & Account P&L
int      g_totalTrades    = 0;
double   g_totalProfit    = 0.0;
int      g_winningTrades  = 0;
double   g_grossProfit    = 0.0;
double   g_grossLoss      = 0.0;
double   g_dailyPl        = 0.0;
double   g_drawdownPct    = 0.0;
double   g_peakEquity     = 0.0;
double   g_dayStartEquity = 0.0;
datetime g_dayStartTime   = 0;

// Signal Tracking
string   g_lastSigAction     = "WAIT";
string   g_lastSigStrategy   = "-";
double   g_lastSigConfidence = 0.0;
string   g_lastSigReason     = "initializing";
string   g_gvPrefix          = "";
int      g_saveCounter       = 0;

// Multi-TF Cache Variables
datetime g_lastHtfBarM5   = 0;
datetime g_lastHtfBarM15  = 0;
datetime g_lastHtfBarH1   = 0;
datetime g_lastHtfBarH4   = 0;
TFView   g_cachedM5, g_cachedM15, g_cachedH1, g_cachedH4;
bool     g_cachedM5Ok = false, g_cachedM15Ok = false, g_cachedH1Ok = false, g_cachedH4Ok = false;

//=====================================================================
// FORWARD DECLARATIONS
//=====================================================================
double NormPrice(double p);
double NormLot(double lot);
void   CalcEMA(const double &src[], double &out[], int period, int count);
double CalcRSI(const double &close[], int count, int period);
double CalcATR(const double &high[], const double &low[], const double &close[], int count, int period);
void   CalcADX(const double &high[], const double &low[], const double &close[], int count, int period, double &adx_out, double &pdi_out, double &mdi_out);
double CalcBBWidth(const double &close[], int count, int period);
void   CalcMACDArr(const double &close[], double &out[], int count, int fast=12, int slow=26, int signal_p=9);
bool   AnalyzeTF(ENUM_TIMEFRAMES tf, const string tf_name, int n_bars, TFView &v);
void   UpdateBasketCache();
bool   ShouldUpdateDashboard();
void   UpdateSRRanges();
double GetYesterdaySwingPts();
double GetGridAtrPts();
double CalculateDynamicGridGap(int layer);
string EvaluateMarketRegime(const TFView &m1, const TFView &m5, const TFView &m15, const TFView &h1);
void   DecideSignal(TFView &views[], bool &viewsOk[], Signal &out);
string DecideStatus(double bal, double eq, double fm);
bool   AllowedHour();
double CurrentSpreadPts();
bool   SpreadAcceptable();
int    BasketCount(int direction);
double BasketAvgPrice(int direction);
double BasketLastOpenPrice(int direction);
double BasketProfit(int direction);
datetime BasketOldestTime(int direction);
int    BasketCalcTpPoints(int direction, int n);
double BasketTargetPrice(int direction);
double NextRecoveryLot(int direction);
void   CloseAllPositions(const string reason);
void   CloseBasket(int direction, const string reason);
void   FinaliseBasket(int direction);
void   ManageRecovery(TFView &views[], bool &viewsOk[]);
void   ManageBasketRisk(int direction);
void   ManageBreakevenExit(int direction);
void   UpdateMaxBasketLoss(int direction);
void   UpdateBasketTPs();
void   TryOpenNew(const Signal &sig);
void   RecordCloses();
void   ResetDay();
void   CheckDayRollover();
void   UpdateDailyPL(double eq);
void   UpdateDD(double eq);
void   ManageTrailing(int direction);
void   ManagePartialClose(int direction);
void   RetryPartialClose(int direction);
string GVKey(const string field);
void   SaveState();
void   LoadState();
ENUM_ORDER_TYPE_FILLING PickFilling();
void   PrintFmt(const string msg);
void   RefreshDashColors();
void   DashInit();
void   DashDelete();
void   DashUpdate(double bal, double eq, double fm, TFView &views[], bool &viewsOk[]);
void   ObjDel(const string name);
void   ObjRect(const string name, int x, int y, int w, int h, color bg, color border, int bw=1);
void   ObjLabel(const string name, int x, int y, const string txt, color clr, int fs=9, const string font="Consolas", int anchor=0);
void   ObjDivider(const string name, int x, int y, int w);
void   ObjRow(const string lname, const string rname, int x, int y, int panelW, const string lbl, const string val, color lclr=0, color vclr=0);
void   ObjBar(const string name, int x, int y, int maxW, double pct, color clr);

//=====================================================================
// OnInit
//=====================================================================
int OnInit()
{
   if(!g_sym.Name(Symbol())) { Print("ERROR: SymbolInfo init failed for ", Symbol()); return INIT_FAILED; }
   g_sym.Refresh();
   g_digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   g_point  = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   if(g_point == 0) g_point = 0.01;
   
   g_pointFactor = (g_digits == 3 || g_digits == 5) ? 10.0 : 1.0;

   g_volStep    = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   g_volMin     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   g_volMax     = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   g_stopsLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);

   g_isTester       = (bool)MQLInfoInteger(MQL_TESTER);
   g_isOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_isVisual       = (bool)MQLInfoInteger(MQL_VISUAL_MODE);

   if(InpMaxRecoveryAttempts > InpRecoveryMaxLayers)
   {
      Print("ERROR: InpMaxRecoveryAttempts must be <= InpRecoveryMaxLayers");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFilling(PickFilling());

   g_gvPrefix = StringFormat("ZXSG_%s_%d_", Symbol(), (int)InpMagic);

   ResetDay();
   LoadState();
   UpdateBasketCache();

   if(!g_isOptimization && (!g_isTester || g_isVisual))
   {
      RefreshDashColors();
      DashInit();
   }

   PrintFmt(StringFormat("Zerith XAU SwingGrid Recovery EA initialized. Magic=%d Digits=%d Point=%.5f PF=%.1f",
            (int)InpMagic, g_digits, g_point, g_pointFactor));
   return INIT_SUCCEEDED;
}

//=====================================================================
// OnDeinit
//=====================================================================
void OnDeinit(const int reason)
{
   if(!g_isTester) SaveState();
   DashDelete();
   PrintFmt(StringFormat("Zerith XAU SwingGrid Recovery EA deinit (reason: %d)", reason));
}

//=====================================================================
// OnTick
//=====================================================================
void OnTick()
{
   CheckDayRollover();
   UpdateBasketCache();

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   UpdateDailyPL(eq);
   UpdateDD(eq);
   RecordCloses();

   TFView views[5];
   bool   viewsOk[5];
   ENUM_TIMEFRAMES tfs[5] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
   string  tfNames[5]     = {"M1","M5","M15","H1","H4"};
   int     tfBars[5]      = {InpBarsM1, InpBarsHTF, InpBarsHTF, InpBarsHTF, InpBarsHTF};

   static double   s_lastM1Price = 0.0;
   static datetime s_lastM1Bar   = 0;
   static TFView   s_cachedM1View;
   static bool     s_cachedM1Ok  = false;

   datetime curM1Bar = iTime(Symbol(), PERIOD_M1, 0);
   double curBid = g_sym.Bid();
   if(curM1Bar == s_lastM1Bar && curBid == s_lastM1Price && s_cachedM1Ok)
   {
      views[0]   = s_cachedM1View;
      viewsOk[0] = s_cachedM1Ok;
   }
   else
   {
      viewsOk[0] = AnalyzeTF(tfs[0], tfNames[0], tfBars[0], views[0]);
      s_cachedM1View = views[0];
      s_cachedM1Ok   = viewsOk[0];
      s_lastM1Bar    = curM1Bar;
      s_lastM1Price  = curBid;
   }

   datetime curM5Bar  = iTime(Symbol(), PERIOD_M5, 0);  if(curM5Bar == 0)  curM5Bar  = TimeCurrent();
   datetime curM15Bar = iTime(Symbol(), PERIOD_M15, 0); if(curM15Bar == 0) curM15Bar = TimeCurrent();
   datetime curH1Bar  = iTime(Symbol(), PERIOD_H1, 0);  if(curH1Bar == 0)  curH1Bar  = TimeCurrent();
   datetime curH4Bar  = iTime(Symbol(), PERIOD_H4, 0);  if(curH4Bar == 0)  curH4Bar  = TimeCurrent();

   if(curM5Bar != g_lastHtfBarM5 || !g_cachedM5Ok)
   { g_cachedM5Ok = AnalyzeTF(tfs[1], tfNames[1], tfBars[1], g_cachedM5); g_lastHtfBarM5 = curM5Bar; }
   if(curM15Bar != g_lastHtfBarM15 || !g_cachedM15Ok)
   { g_cachedM15Ok = AnalyzeTF(tfs[2], tfNames[2], tfBars[2], g_cachedM15); g_lastHtfBarM15 = curM15Bar; }
   if(curH1Bar != g_lastHtfBarH1 || !g_cachedH1Ok)
   { g_cachedH1Ok = AnalyzeTF(tfs[3], tfNames[3], tfBars[3], g_cachedH1); g_lastHtfBarH1 = curH1Bar; }
   if(curH4Bar != g_lastHtfBarH4 || !g_cachedH4Ok)
   { g_cachedH4Ok = AnalyzeTF(tfs[4], tfNames[4], tfBars[4], g_cachedH4); g_lastHtfBarH4 = curH4Bar; }

   views[1] = g_cachedM5;  viewsOk[1] = g_cachedM5Ok;
   views[2] = g_cachedM15; viewsOk[2] = g_cachedM15Ok;
   views[3] = g_cachedH1;  viewsOk[3] = g_cachedH1Ok;
   views[4] = g_cachedH4;  viewsOk[4] = g_cachedH4Ok;

   if(!viewsOk[0] || !viewsOk[1] || !viewsOk[2] || !viewsOk[3])
   { g_status = "INIT"; return; }

   g_atrM1    = views[0].atr_val;
   if(g_point > 0.0 && g_pointFactor > 0.0)
      g_atrM1Pts = g_atrM1 / (g_point * g_pointFactor);
   else
      g_atrM1Pts = 50.0;

   UpdateSRRanges();
   g_regime = EvaluateMarketRegime(views[0], views[1], views[2], views[3]);
   g_status = DecideStatus(bal, eq, fm);

   Signal sig;
   DecideSignal(views, viewsOk, sig);
   g_lastSigAction     = sig.action;
   g_lastSigStrategy   = sig.strategy;
   g_lastSigConfidence = sig.confidence;
   g_lastSigReason     = sig.reason;

   if(g_status == "HALT")
   {
      if(PositionsTotal() > 0)
         CloseAllPositions("HALT: equity DD limit");
      if(ShouldUpdateDashboard()) DashUpdate(bal, eq, fm, views, viewsOk);
      return;
   }

   // 1. Manage Basket Floating Risks & Trailing
   for(int d = 0; d < 2; d++) UpdateMaxBasketLoss(d);
   for(int d = 0; d < 2; d++) ManageBasketRisk(d);

   for(int d = 0; d < 2; d++)
      if(g_pendingPartialClose[d]) RetryPartialClose(d);

   if(InpPartialCloseEnable)
      for(int d = 0; d < 2; d++) ManagePartialClose(d);

   if(InpTrailingEnable)
      for(int d = 0; d < 2; d++) ManageTrailing(d);

   // 2. Manage Dynamic Swing-Grid Recovery Layers
   if(g_status == "ACTIVE" || g_status == "RECOVERY_ONLY")
      ManageRecovery(views, viewsOk);

   // 3. Open Initial Position when no basket is active
   if(g_status == "ACTIVE" && (sig.action == "BUY" || sig.action == "SELL") && SpreadAcceptable())
      TryOpenNew(sig);

   // 4. Update Unified TP for active baskets
   UpdateBasketTPs();

   if(ShouldUpdateDashboard()) DashUpdate(bal, eq, fm, views, viewsOk);

   if(!g_isTester)
   {
      g_saveCounter++;
      if(g_saveCounter >= 60) { SaveState(); g_saveCounter = 0; }
   }
}

//=====================================================================
// OnChartEvent
//=====================================================================
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE && ShouldUpdateDashboard() && InpDashAutoColor)
   {
      RefreshDashColors();
      ChartRedraw();
   }
}

//=====================================================================
// STATE PERSISTENCE
//=====================================================================
string GVKey(const string field) { return g_gvPrefix + field; }

void SaveState()
{
   string dirs[2] = {"buy", "sell"};
   for(int d = 0; d < 2; d++)
   {
      GlobalVariableSet(GVKey(dirs[d] + "_peak"),      g_peakProfit[d]);
      GlobalVariableSet(GVKey(dirs[d] + "_trailing"),  g_trailingActive[d] ? 1.0 : 0.0);
      GlobalVariableSet(GVKey(dirs[d] + "_pstage"),    (double)g_partialStage[d]);
      GlobalVariableSet(GVKey(dirs[d] + "_pendingpc"), g_pendingPartialClose[d] ? 1.0 : 0.0);
      GlobalVariableSet(GVKey(dirs[d] + "_recmode"),   g_recoveryMode[d] ? 1.0 : 0.0);
      GlobalVariableSet(GVKey(dirs[d] + "_maxloss"),   g_maxBasketLoss[d]);
   }
   GlobalVariableSet(GVKey("lastRecBuy"),     (double)(long)g_lastRecBuy);
   GlobalVariableSet(GVKey("lastRecSell"),    (double)(long)g_lastRecSell);
   GlobalVariableSet(GVKey("day_start"),      (double)(long)g_dayStartTime);
   GlobalVariableSet(GVKey("day_start_eq"),   g_dayStartEquity);
   GlobalVariableSet(GVKey("peak_equity"),    g_peakEquity);
   GlobalVariableSet(GVKey("total_trades"),   (double)g_totalTrades);
   GlobalVariableSet(GVKey("total_profit"),   g_totalProfit);
   GlobalVariableSet(GVKey("winning_trades"), (double)g_winningTrades);
   GlobalVariableSet(GVKey("gross_profit"),   g_grossProfit);
   GlobalVariableSet(GVKey("gross_loss"),     g_grossLoss);
   GlobalVariableSet(GVKey("cooldown_until"), (double)(long)g_cooldownUntil);
}

void LoadState()
{
   string dirs[2] = {"buy", "sell"};
   for(int d = 0; d < 2; d++)
   {
      string kp = GVKey(dirs[d] + "_peak");
      if(GlobalVariableCheck(kp)) g_peakProfit[d]     = GlobalVariableGet(kp);
      string kt = GVKey(dirs[d] + "_trailing");
      if(GlobalVariableCheck(kt)) g_trailingActive[d] = (GlobalVariableGet(kt) > 0.5);
      string ks = GVKey(dirs[d] + "_pstage");
      if(GlobalVariableCheck(ks)) g_partialStage[d]   = (int)GlobalVariableGet(ks);
      string kpp = GVKey(dirs[d] + "_pendingpc");
      if(GlobalVariableCheck(kpp)) g_pendingPartialClose[d] = (GlobalVariableGet(kpp) > 0.5);
      string kr = GVKey(dirs[d] + "_recmode");
      if(GlobalVariableCheck(kr)) g_recoveryMode[d]   = (GlobalVariableGet(kr) > 0.5);
      string kl = GVKey(dirs[d] + "_maxloss");
      if(GlobalVariableCheck(kl)) g_maxBasketLoss[d]  = GlobalVariableGet(kl);
   }
   string lb = GVKey("lastRecBuy");     if(GlobalVariableCheck(lb))  g_lastRecBuy    = (datetime)(long)GlobalVariableGet(lb);
   string ls = GVKey("lastRecSell");    if(GlobalVariableCheck(ls))  g_lastRecSell   = (datetime)(long)GlobalVariableGet(ls);
   string pe = GVKey("peak_equity");    if(GlobalVariableCheck(pe)) { double sv = GlobalVariableGet(pe); if(sv > 0.0) g_peakEquity = sv; }
   string tt = GVKey("total_trades");   if(GlobalVariableCheck(tt))  g_totalTrades   = (int)GlobalVariableGet(tt);
   string tp = GVKey("total_profit");   if(GlobalVariableCheck(tp))  g_totalProfit   = GlobalVariableGet(tp);
   string wt = GVKey("winning_trades"); if(GlobalVariableCheck(wt))  g_winningTrades = (int)GlobalVariableGet(wt);
   string gp = GVKey("gross_profit");   if(GlobalVariableCheck(gp))  g_grossProfit   = GlobalVariableGet(gp);
   string gl = GVKey("gross_loss");     if(GlobalVariableCheck(gl))  g_grossLoss     = GlobalVariableGet(gl);
   string cu = GVKey("cooldown_until"); if(GlobalVariableCheck(cu))  g_cooldownUntil = (datetime)(long)GlobalVariableGet(cu);
}

//=====================================================================
// YESTERDAY'S SWING & CONFIGURABLE ATR CALCULATION ENGINE
//=====================================================================
double GetYesterdaySwingPts()
{
   static datetime lastD1Bar = 0;
   static double   cachedSwingPts = 0.0;

   datetime curD1Bar = iTime(Symbol(), PERIOD_D1, 0);
   if(curD1Bar == lastD1Bar && cachedSwingPts > 0.0)
      return cachedSwingPts;

   double yHigh = iHigh(Symbol(), PERIOD_D1, 1);
   double yLow  = iLow(Symbol(), PERIOD_D1, 1);

   if(yHigh > 0.0 && yLow > 0.0 && yHigh >= yLow)
   {
      double swingPrice = yHigh - yLow;
      if(g_point > 0.0 && g_pointFactor > 0.0)
         cachedSwingPts = swingPrice / (g_point * g_pointFactor);
      else
         cachedSwingPts = swingPrice / 0.01;
      lastD1Bar = curD1Bar;
   }
   return (cachedSwingPts > 0.0) ? cachedSwingPts : 1000.0;
}

double GetGridAtrPts()
{
   static datetime lastAtrBar = 0;
   static double   cachedAtrPts = 0.0;

   datetime curAtrBar = iTime(Symbol(), InpGridAtrTf, 0);
   if(curAtrBar == lastAtrBar && cachedAtrPts > 0.0)
      return cachedAtrPts;

   double high_arr[], low_arr[], close_arr[];
   ArraySetAsSeries(high_arr, true);
   ArraySetAsSeries(low_arr,  true);
   ArraySetAsSeries(close_arr, true);

   int needed = InpGridAtrPeriod + 1;
   if(CopyHigh (Symbol(), InpGridAtrTf, 1, needed, high_arr) < needed ||
      CopyLow  (Symbol(), InpGridAtrTf, 1, needed, low_arr)  < needed ||
      CopyClose(Symbol(), InpGridAtrTf, 1, needed, close_arr)< needed)
   {
      return (g_atrM1Pts > 0) ? g_atrM1Pts : 100.0;
   }

   double tr_sum = 0.0;
   for(int i = 0; i < InpGridAtrPeriod; i++)
   {
      double tr1 = high_arr[i] - low_arr[i];
      double tr2 = MathAbs(high_arr[i] - close_arr[i+1]);
      double tr3 = MathAbs(low_arr[i]  - close_arr[i+1]);
      tr_sum += MathMax(tr1, MathMax(tr2, tr3));
   }

   double atr_price = tr_sum / InpGridAtrPeriod;
   if(g_point > 0.0 && g_pointFactor > 0.0)
      cachedAtrPts = atr_price / (g_point * g_pointFactor);
   else
      cachedAtrPts = atr_price / 0.01;

   lastAtrBar = curAtrBar;
   return (cachedAtrPts > 0.0) ? cachedAtrPts : 100.0;
}

double CalculateDynamicGridGap(int layer)
{
   double ySwingPts = GetYesterdaySwingPts();
   double swingPart = (InpSwingDivisor > 0.0) ? (ySwingPts / InpSwingDivisor) : 0.0;
   double atrPart   = GetGridAtrPts() * InpGridAtrMult;

   double baseGap = swingPart + atrPart;

   if(InpUseLayerGapMultiplier && layer > 1)
      baseGap += baseGap * (InpLayerGapExpansionPct / 100.0) * (layer - 1);

   return MathMax((double)InpGridMinGapPts, MathMin((double)InpGridMaxGapPts, baseGap));
}

//=====================================================================
// CALCULATION HELPERS
//=====================================================================
void CalcEMA(const double &src[], double &out[], int period, int count)
{
   if(count <= 0) return;
   if(ArraySize(out) < count) ArrayResize(out, count);
   double alpha = 2.0 / (period + 1.0);
   out[0] = src[0];
   for(int i = 1; i < count; i++)
      out[i] = alpha * src[i] + (1.0 - alpha) * out[i-1];
}

double CalcRSI(const double &close[], int count, int period)
{
   if(count <= period) return 50.0;
   double gains = 0.0, losses = 0.0;
   int start = count - period;
   for(int i = start; i < count; i++)
   {
      double diff = close[i] - close[i-1];
      if(diff > 0.0) gains += diff;
      else           losses -= diff;
   }
   double avgGain = gains / period;
   double avgLoss = losses / period;
   if(avgLoss == 0.0) return 100.0;
   double rs = avgGain / avgLoss;
   return 100.0 - (100.0 / (1.0 + rs));
}

double CalcATR(const double &high[], const double &low[], const double &close[], int count, int period)
{
   if(count <= period) return 0.0;
   double tr_sum = 0.0;
   int start = count - period;
   for(int i = start; i < count; i++)
   {
      double tr1 = high[i] - low[i];
      double tr2 = MathAbs(high[i] - close[i-1]);
      double tr3 = MathAbs(low[i]  - close[i-1]);
      tr_sum += MathMax(tr1, MathMax(tr2, tr3));
   }
   return tr_sum / period;
}

void CalcADX(const double &high[], const double &low[], const double &close[], int count, int period,
             double &adx_out, double &pdi_out, double &mdi_out)
{
   adx_out = 20.0; pdi_out = 20.0; mdi_out = 20.0;
   if(count <= period * 2) return;
   double tr_sum = 0.0, dm_plus_sum = 0.0, dm_minus_sum = 0.0;
   int start = count - period;
   for(int i = start; i < count; i++)
   {
      double tr1 = high[i] - low[i];
      double tr2 = MathAbs(high[i] - close[i-1]);
      double tr3 = MathAbs(low[i]  - close[i-1]);
      tr_sum += MathMax(tr1, MathMax(tr2, tr3));

      double up_move   = high[i] - high[i-1];
      double down_move = low[i-1] - low[i];
      if(up_move > down_move && up_move > 0.0)   dm_plus_sum  += up_move;
      if(down_move > up_move && down_move > 0.0) dm_minus_sum += down_move;
   }
   if(tr_sum == 0.0) return;
   pdi_out = (dm_plus_sum  / tr_sum) * 100.0;
   mdi_out = (dm_minus_sum / tr_sum) * 100.0;
   double di_diff = MathAbs(pdi_out - mdi_out);
   double di_sum  = pdi_out + mdi_out;
   adx_out = (di_sum > 0.0) ? (di_diff / di_sum) * 100.0 : 20.0;
}

double CalcBBWidth(const double &close[], int count, int period)
{
   if(count < period) return 0.0;
   double sum = 0.0;
   int start = count - period;
   for(int i = start; i < count; i++) sum += close[i];
   double ma = sum / period;
   double sumSq = 0.0;
   for(int i = start; i < count; i++) sumSq += MathPow(close[i] - ma, 2.0);
   double std = MathSqrt(sumSq / period);
   return (ma > 0.0) ? (2.0 * std * 2.0 / ma) : 0.0;
}

void CalcMACDArr(const double &close[], double &out[], int count, int fast=12, int slow=26, int signal_p=9)
{
   if(count <= 0) return;
   if(ArraySize(out) < count) ArrayResize(out, count);
   double af  = 2.0 / (fast + 1.0);
   double as_ = 2.0 / (slow + 1.0);
   double ag  = 2.0 / (signal_p + 1.0);
   double ef  = close[0];
   double es  = close[0];
   double sig = 0.0;
   double ml  = 0.0;
   out[0] = 0.0;
   for(int i = 1; i < count; i++)
   { 
      ef  = af  * close[i] + (1.0 - af)  * ef; 
      es  = as_ * close[i] + (1.0 - as_) * es; 
      ml  = ef - es; 
      sig = ag  * ml       + (1.0 - ag)  * sig; 
      out[i] = ml - sig; 
   }
}

bool AnalyzeTF(ENUM_TIMEFRAMES tf, const string tf_name, int n_bars, TFView &v)
{
   if(n_bars < 80) n_bars = 80;
   static double close_arr[], high_arr[], low_arr[];
   ArraySetAsSeries(close_arr, false);
   ArraySetAsSeries(high_arr,  false);
   ArraySetAsSeries(low_arr,   false);
   int copied = CopyClose(Symbol(), tf, 0, n_bars, close_arr);
   if(copied < 80) return false;
   if(CopyHigh(Symbol(), tf, 0, n_bars, high_arr) < 80) return false;
   if(CopyLow (Symbol(), tf, 0, n_bars, low_arr ) < 80) return false;

   int cnt = ArraySize(close_arr);
   static double ema_f[], ema_s[];
   if(ArraySize(ema_f) < cnt) ArrayResize(ema_f, cnt);
   if(ArraySize(ema_s) < cnt) ArrayResize(ema_s, cnt);
   CalcEMA(close_arr, ema_f, 20, cnt);
   CalcEMA(close_arr, ema_s, 50, cnt);
   double lc = close_arr[cnt-1], ef = ema_f[cnt-1], es = ema_s[cnt-1];
   int trend = 0;
   if(ef > es && lc > ef) trend = 1;
   else if(ef < es && lc < ef) trend = -1;

   double adx_v, pdi_v, mdi_v;
   CalcADX(high_arr, low_arr, close_arr, cnt, 14, adx_v, pdi_v, mdi_v);

   static double macd_arr[];
   CalcMACDArr(close_arr, macd_arr, cnt, 12, 26, 9);

   v.tf_name        = tf_name;
   v.trend          = trend;
   v.adx_val        = adx_v;
   v.atr_val        = CalcATR(high_arr, low_arr, close_arr, cnt, 14);
   v.rsi_val        = CalcRSI(close_arr, cnt, 14);
   v.bb_width       = (cnt >= 20) ? CalcBBWidth(close_arr, cnt, 20) : 0.0;
   v.macd_hist      = macd_arr[cnt-1];
   v.macd_hist_prev = macd_arr[cnt-2];
   v.last_close     = lc;
   v.ema_fast       = ef;
   v.ema_slow       = es;
   return true;
}

//=====================================================================
// S/R LEVEL FINDER
//=====================================================================
void UpdateSRRanges()
{
   static datetime lastSrH1Bar = 0;
   datetime curH1Bar = iTime(Symbol(), PERIOD_H1, 0);
   if(curH1Bar == lastSrH1Bar && g_resistPx > 0.0 && g_supportPx > 0.0) return;

   static double high_arr[], low_arr[];
   ArraySetAsSeries(high_arr, true);
   ArraySetAsSeries(low_arr,  true);
   if(CopyHigh(Symbol(), PERIOD_H1, 1, 100, high_arr) < 100) return;
   if(CopyLow (Symbol(), PERIOD_H1, 1, 100, low_arr ) < 100) return;
   double maxHigh = high_arr[0];
   double minLow  = low_arr[0];
   for(int i = 1; i < 100; i++)
   {
      if(high_arr[i] > maxHigh) maxHigh = high_arr[i];
      if(low_arr[i]  < minLow)  minLow  = low_arr[i];
   }
   g_resistPx = maxHigh;
   g_supportPx = minLow;
   lastSrH1Bar = curH1Bar;
}

//=====================================================================
// MARKET REGIME ENGINE
//=====================================================================
string EvaluateMarketRegime(const TFView &m1, const TFView &m5, const TFView &m15, const TFView &h1)
{
   if(m15.trend > 0 && h1.trend < 0) return "CHOPPY";
   if(m15.trend < 0 && h1.trend > 0) return "CHOPPY";
   if(m5.atr_val > 0 && m1.atr_val > m5.atr_val * 1.5) return "VOLATILE";
   if(g_atrM1Pts > 50.0) return "VOLATILE";
   if(h1.adx_val > InpTrendAdx && m15.adx_val > 20 && h1.trend != 0) return "TREND_STRONG";
   if(h1.adx_val < 20) return "RANGE";
   return "NORMAL";
}

//=====================================================================
// SIGNAL DECISION (Initial Entry Breakout Engine)
//=====================================================================
void DecideSignal(TFView &views[], bool &viewsOk[], Signal &out)
{
   out.action="WAIT"; out.strategy="BREAKOUT"; out.confidence=0.0; out.reason="no setup"; out.tp_points=InpTpPointsBase;
   if(!viewsOk[0] || !viewsOk[1] || !viewsOk[2] || !viewsOk[3]) return;
   TFView m1 = views[0], m5 = views[1], m15 = views[2], h1 = views[3];

   // 1. Choppy filter
   if(g_regime == "CHOPPY" || (m15.trend > 0 && h1.trend < 0) || (m15.trend < 0 && h1.trend > 0))
   {
      out.reason = "Choppy Market (Stay Out)";
      return;
   }

   // 2. Momentum Breakout Evaluation
   bool buy_breakout  = (m1.trend > 0 && m1.macd_hist > 0);
   bool sell_breakout = (m1.trend < 0 && m1.macd_hist < 0);

   if(buy_breakout)
   {
      out.action     = "BUY";
      out.strategy   = "BREAKOUT";
      out.confidence = (h1.trend > 0) ? 0.70 : 0.60;
      out.reason     = (h1.trend > 0) ? "Trend-Aligned BUY Breakout" : "M1 BUY Breakout";
      out.tp_points  = InpTpPointsBase;
   }
   else if(sell_breakout)
   {
      out.action     = "SELL";
      out.strategy   = "BREAKOUT";
      out.confidence = (h1.trend < 0) ? 0.70 : 0.60;
      out.reason     = (h1.trend < 0) ? "Trend-Aligned SELL Breakout" : "M1 SELL Breakout";
      out.tp_points  = InpTpPointsBase;
   }
   else
   {
      out.reason = "Waiting for M1 Breakout alignment";
   }

   if(out.action == "WAIT") return;

   // 3. Optional Strict H1 Trend Filter
   if(InpUseHtfFilter)
   {
      if(out.action == "BUY" && h1.trend < 0)
      {
         out.action = "WAIT";
         out.reason = "Filtered: H1 Trend opposes BUY";
         return;
      }
      if(out.action == "SELL" && h1.trend > 0)
      {
         out.action = "WAIT";
         out.reason = "Filtered: H1 Trend opposes SELL";
         return;
      }
   }

   // 4. H4 Macro Trend Guard
   if(viewsOk[4] && views[4].trend != 0 && h1.adx_val > InpTrendAdx)
   {
      if(out.action == "BUY" && views[4].trend < 0 && h1.trend < 0)
      {
         out.action = "WAIT";
         out.reason = "Filtered: Strong H4+H1 opposes BUY";
         return;
      }
      if(out.action == "SELL" && views[4].trend > 0 && h1.trend > 0)
      {
         out.action = "WAIT";
         out.reason = "Filtered: Strong H4+H1 opposes SELL";
         return;
      }
   }
}

//=====================================================================
// STATUS DECISION
//=====================================================================
string DecideStatus(double bal, double eq, double fm)
{
   double fm_pct = (eq > 0) ? fm / eq * 100.0 : 0.0;
   if(InpUseMaxEquityDdPct && g_drawdownPct >= InpMaxEquityDdPct) return "HALT";
   if(g_dailyPl >= InpDailyTargetUsd && InpDailyTargetUsd > 0)   return "RECOVERY_ONLY";
   if(InpUseTimeFilter && !AllowedHour())                        return "RECOVERY_ONLY";
   if(InpUseMinFreeMarginPct && fm_pct < InpMinFreeMarginPct)    return "RECOVERY_ONLY";
   if(TimeCurrent() < g_cooldownUntil)                          return "RECOVERY_ONLY";
   return "ACTIVE";
}

bool AllowedHour()
{
   datetime serverTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(serverTime, dt);
   int utcHour = (dt.hour - InpServerGMTOffset + 24) % 24;
   return (utcHour >= InpAllowHourFrom && utcHour <= InpAllowHourTo);
}

//=====================================================================
// SPREAD HELPERS
//=====================================================================
double CurrentSpreadPts()
{
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   if(g_point <= 0.0 || g_pointFactor <= 0.0) return 0.0;
   return (ask - bid) / (g_point * g_pointFactor);
}

bool SpreadAcceptable()
{
   return (CurrentSpreadPts() <= (double)InpMaxSpreadPts);
}

//=====================================================================
// POSITION CACHE & HELPERS
//=====================================================================
void UpdateBasketCache()
{
   for(int d = 0; d < 2; d++)
   {
      g_bStats[d].count       = 0;
      g_bStats[d].lots        = 0.0;
      g_bStats[d].avg_price   = 0.0;
      g_bStats[d].last_price  = 0.0;
      g_bStats[d].last_time   = 0;
      g_bStats[d].last_ticket = 0;
      g_bStats[d].last_lot    = 0.0;
      g_bStats[d].profit      = 0.0;
      g_bStats[d].oldest_time = 0;
   }

   int total = PositionsTotal();
   if(total == 0) return;

   double sw[2] = {0.0, 0.0};
   for(int i = 0; i < total; i++)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;

      int dir = (g_pos.PositionType() == POSITION_TYPE_BUY) ? 0 : 1;
      double v = g_pos.Volume();
      double p = g_pos.PriceOpen();
      datetime ot = (datetime)g_pos.Time();

      g_bStats[dir].count++;
      g_bStats[dir].lots += v;
      sw[dir] += p * v;
      g_bStats[dir].profit += (g_pos.Profit() + g_pos.Swap());

      if(g_bStats[dir].oldest_time == 0 || ot < g_bStats[dir].oldest_time)
         g_bStats[dir].oldest_time = ot;

      if(ot >= g_bStats[dir].last_time)
      {
         g_bStats[dir].last_time   = ot;
         g_bStats[dir].last_price  = p;
         g_bStats[dir].last_ticket = g_pos.Ticket();
         g_bStats[dir].last_lot    = v;
      }
   }

   for(int d = 0; d < 2; d++)
      if(g_bStats[d].lots > 0.0)
         g_bStats[d].avg_price = sw[d] / g_bStats[d].lots;
}

int BasketCount(int direction)
{
   return g_bStats[direction].count;
}

double BasketAvgPrice(int direction)
{
   return g_bStats[direction].avg_price;
}

double BasketLastOpenPrice(int direction)
{
   return g_bStats[direction].last_price;
}

double BasketProfit(int direction)
{
   return g_bStats[direction].profit;
}

datetime BasketOldestTime(int direction)
{
   return g_bStats[direction].oldest_time;
}

//=====================================================================
// ADAPTIVE LOT SIZING & TARGET TP CALCULATION
//=====================================================================
double NextRecoveryLot(int direction)
{
   int n = BasketCount(direction);
   double last_lot = (n > 0) ? g_bStats[direction].last_lot : InpInitialLot;

   double mult;
   if(n <= 2)
      mult = InpLotMultEarly;
   else if(n <= 5)
      mult = InpLotMultMid;
   else
      mult = InpLotMultLate;

   if(InpAntiMartingaleDeep && n >= 6)
      mult = InpDeepLotMult;

   if(g_regime == "VOLATILE") mult *= 0.85;

   double raw_lot = last_lot * mult;
   return MathMin(InpRecoveryMaxLot, NormLot(raw_lot));
}

int BasketCalcTpPoints(int direction, int n)
{
   if(InpRecoveryModeEnable && g_recoveryMode[direction] && n >= InpRecoveryModeAtLayer)
      return InpRecoveryReducedTp;

   double base = (double)InpTpPointsBase;
   if(InpTpAtrMult > 0.0)
      base += GetGridAtrPts() * InpTpAtrMult;

   if(n > 1)
      base = MathMax((double)InpTpPointsMin, base * MathPow(0.85, (double)(n - 1)));

   return (int)MathMax((double)InpTpPointsMin, base);
}

double BasketTargetPrice(int direction)
{
   int n = BasketCount(direction);
   if(n == 0) return 0.0;
   double avg = BasketAvgPrice(direction);
   int tp_pts = BasketCalcTpPoints(direction, n);
   if(direction == 0) return avg + tp_pts * g_point * g_pointFactor;
   else               return avg - tp_pts * g_point * g_pointFactor;
}

//=====================================================================
// DYNAMIC SWING-GRID RECOVERY ENGINE
//=====================================================================
void ManageRecovery(TFView &views[], bool &viewsOk[])
{
   for(int direction = 0; direction <= 1; direction++)
   {
      int n = BasketCount(direction);
      if(n == 0 || n >= InpRecoveryMaxLayers) continue;
      if(n >= InpMaxRecoveryAttempts) continue;

      if(InpRecoveryModeEnable && !g_recoveryMode[direction] && n >= InpRecoveryModeAtLayer)
      {
         g_recoveryMode[direction] = true;
         PrintFmt(StringFormat("RecoveryMode ON %s at layer %d (TP->%d pts)",
                  direction==0?"BUY":"SELL", n, InpRecoveryReducedTp));
      }

      double wait_atr_part = (g_atrM1Pts > 0) ? g_atrM1Pts / 10.0 * n : 5.0 * n;
      int    min_wait      = (int)(30.0 + wait_atr_part);
      datetime lastRecDir  = (direction == 0) ? g_lastRecBuy : g_lastRecSell;
      if(TimeCurrent() - lastRecDir < min_wait) continue;

      double lastPx = BasketLastOpenPrice(direction);
      if(lastPx == 0.0) continue;
      double curPrice = (direction == 0) ? g_sym.Bid() : g_sym.Ask();
      double adv_px   = (direction == 0) ? (lastPx - curPrice) : (curPrice - lastPx);
      double adv_pts  = (g_point > 0 && g_pointFactor > 0) ? adv_px / (g_point * g_pointFactor) : 0.0;

      // Calculate Dynamic Grid Gap (Yesterday Swing/10 + Configurable ATR)
      double min_gap = CalculateDynamicGridGap(n);

      // Snap to Support / Resistance levels if close
      if(direction == 0 && g_supportPx > 0 && g_supportPx < curPrice)
      {
         double distToSup = (curPrice - g_supportPx) / (g_point * g_pointFactor);
         if(distToSup > 0 && distToSup < min_gap * 0.5)
            min_gap = distToSup + 2.0;
      }
      if(direction == 1 && g_resistPx > 0 && g_resistPx > curPrice)
      {
         double distToRes = (g_resistPx - curPrice) / (g_point * g_pointFactor);
         if(distToRes > 0 && distToRes < min_gap * 0.5)
            min_gap = distToRes + 2.0;
      }

      if(adv_pts < min_gap) continue;

      // Momentum safety check (do not enter recovery against strong momentum cascade)
      if(viewsOk[0])
      {
         TFView m1 = views[0];
         if(direction == 0 && m1.macd_hist < m1.macd_hist_prev && m1.rsi_val < 25) continue;
         if(direction == 1 && m1.macd_hist > m1.macd_hist_prev && m1.rsi_val > 75) continue;
      }

      if(viewsOk[3] && viewsOk[4])
      {
         TFView h1 = views[3], h4 = views[4];
         if(direction == 0 && h1.trend < 0 && h4.trend < 0 && h1.adx_val > 25) continue;
         if(direction == 1 && h1.trend > 0 && h4.trend > 0 && h1.adx_val > 25) continue;
      }

      double eq_r = AccountInfoDouble(ACCOUNT_EQUITY);
      double fm   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(InpUseMinFreeMarginPct && eq_r > 0 && fm / eq_r * 100.0 < InpMinFreeMarginPct) continue;

      double lot   = NextRecoveryLot(direction);
      double tp_px = NormPrice(BasketTargetPrice(direction));
      string cmt   = StringFormat("%s_%s_%d", InpTradeCommentPrefix, direction==0?"BUY":"SELL", n+1);

      bool ok = false;
      if(direction == 0) ok = g_trade.Buy (lot, Symbol(), 0.0, 0.0, tp_px, cmt);
      else               ok = g_trade.Sell(lot, Symbol(), 0.0, 0.0, tp_px, cmt);

      if(ok)
      {
         if(direction == 0) g_lastRecBuy  = TimeCurrent();
         else               g_lastRecSell = TimeCurrent();
         UpdateBasketCache();
         PrintFmt(StringFormat("SWING-GRID REC %s lot=%.2f layer=%d gap=%.1f/%.1f (Y-Swing=%.0f ATR=%.0f)",
                  direction==0?"BUY":"SELL", lot, n+1, adv_pts, min_gap, GetYesterdaySwingPts(), GetGridAtrPts()));
      }
   }
}

//=====================================================================
// UPDATE BASKET TPs
//=====================================================================
void UpdateBasketTPs()
{
   if(g_bStats[0].count == 0 && g_bStats[1].count == 0) return;
   double one_pt = g_point * g_pointFactor;

   for(int direction = 0; direction <= 1; direction++)
   {
      int n = g_bStats[direction].count;
      if(n == 0) continue;
      double target = NormPrice(BasketTargetPrice(direction));
      if(target <= 0.0) continue;

      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;
         if((g_pos.PositionType() == POSITION_TYPE_BUY ? 0 : 1) != direction) continue;

         double curTP = g_pos.TakeProfit();
         if(MathAbs(curTP - target) > one_pt * 2.0)
            g_trade.PositionModify(g_pos.Ticket(), g_pos.StopLoss(), target);
      }
   }
}

//=====================================================================
// BASKET RISK & CAPITAL PROTECTION
//=====================================================================
void ManageBasketRisk(int direction)
{
   int n = BasketCount(direction);
   if(n == 0) return;

   double bpnl = BasketProfit(direction);

   // Hard Basket Stop Loss
   if(InpUseBasketStopLoss && bpnl <= -InpMaxBasketLossUsd)
   {
      CloseBasket(direction, StringFormat("Basket Stop Loss hit: $%.2f <= -$%.2f", bpnl, InpMaxBasketLossUsd));
      return;
   }

   // Basket Max Age Time Stop
   if(InpBasketMaxAgeHours > 0)
   {
      datetime oldest = BasketOldestTime(direction);
      if(oldest > 0 && (TimeCurrent() - oldest) >= (datetime)(InpBasketMaxAgeHours * 3600))
      {
         CloseBasket(direction, StringFormat("Basket Max Age exceeded (%d hours)", InpBasketMaxAgeHours));
         return;
      }
   }

   // Breakeven Exit
   if(InpBreakevenExit && n >= 3)
      ManageBreakevenExit(direction);
}

void ManageBreakevenExit(int direction)
{
   double bpnl = BasketProfit(direction);
   if(g_maxBasketLoss[direction] < -3.0 && bpnl >= InpBreakevenTriggerUsd)
   {
      CloseBasket(direction, StringFormat("Breakeven Exit: maxLoss=$%.2f recovered to $%.2f",
                  g_maxBasketLoss[direction], bpnl));
   }
}

void UpdateMaxBasketLoss(int direction)
{
   int n = BasketCount(direction);
   if(n == 0) { g_maxBasketLoss[direction] = 0.0; return; }
   double p = BasketProfit(direction);
   if(p < g_maxBasketLoss[direction]) g_maxBasketLoss[direction] = p;
}

//=====================================================================
// TRAILING STOP BASKET
//=====================================================================
void ManageTrailing(int direction)
{
   int n = BasketCount(direction);
   double profit = BasketProfit(direction);

   if(n == 0)
   {
      if(g_trailingActive[direction] || g_peakProfit[direction] != 0.0)
         FinaliseBasket(direction);
      return;
   }

   if(!g_trailingActive[direction])
   {
      if(profit >= InpTrailingTriggerUsd)
      {
         g_trailingActive[direction] = true;
         g_peakProfit[direction]     = profit;
         PrintFmt(StringFormat("Trailing ARMED %s peak=%.2f", direction==0?"BUY":"SELL", profit));
      }
   }
   else
   {
      if(profit > g_peakProfit[direction])
         g_peakProfit[direction] = profit;

      if(g_peakProfit[direction] - profit >= InpTrailingStepUsd)
      {
         PrintFmt(StringFormat("Trailing EXIT %s peak=%.2f now=%.2f",
                  direction==0?"BUY":"SELL", g_peakProfit[direction], profit));
         CloseBasket(direction, StringFormat("Trailing exit peak=%.2f drop=%.2f",
                     g_peakProfit[direction], g_peakProfit[direction] - profit));
      }
   }
}

//=====================================================================
// STAGED PARTIAL CLOSE
//=====================================================================
void ManagePartialClose(int direction)
{
   int maxStage = InpStagedPartialClose ? InpPartialCloseLevels : 1;
   if(g_partialStage[direction] >= maxStage) return;

   int    n      = BasketCount(direction);
   double profit = BasketProfit(direction);
   double triggerUsd = InpPartialCloseAtUsd * (g_partialStage[direction] + 1);

   if(n >= 2 && profit >= triggerUsd && !g_pendingPartialClose[direction])
   {
      ulong  bestTicket = 0;
      double bestProfit = 0.0;
      double bestLot    = 0.0;

      for(int i = 0; i < PositionsTotal(); i++)
      {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;
         if((g_pos.PositionType() == POSITION_TYPE_BUY ? 0 : 1) != direction) continue;

         double p = g_pos.Profit() + g_pos.Swap();
         if(p > bestProfit) { bestProfit = p; bestTicket = g_pos.Ticket(); bestLot = g_pos.Volume(); }
      }

      if(bestTicket > 0 && bestLot > g_volMin)
      {
         double closeLot = NormLot(bestLot * (InpPartialClosePct / 100.0));
         if(closeLot >= g_volMin && closeLot < bestLot)
         {
            bool ok = g_trade.PositionClosePartial(bestTicket, closeLot);
            if(ok)
            {
               g_partialStage[direction]++;
               g_pendingPartialClose[direction] = false;
               PrintFmt(StringFormat("Partial Close Stage %d %s: ticket=%d closed=%.2f",
                        g_partialStage[direction], direction==0?"BUY":"SELL", bestTicket, closeLot));
            }
            else
            {
               g_pendingPartialClose[direction] = true;
            }
         }
      }
   }
}

void RetryPartialClose(int direction)
{
   if(!g_pendingPartialClose[direction]) return;
   ManagePartialClose(direction);
}

//=====================================================================
// CLOSE BASKET & FINALISE
//=====================================================================
void CloseAllPositions(const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;
      g_trade.PositionClose(g_pos.Ticket());
   }
   for(int d = 0; d < 2; d++) FinaliseBasket(d);
   PrintFmt("All positions closed: " + reason);
}

void CloseBasket(int direction, const string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;
      if((g_pos.PositionType() == POSITION_TYPE_BUY ? 0 : 1) != direction) continue;
      g_trade.PositionClose(g_pos.Ticket());
   }
   FinaliseBasket(direction);
   PrintFmt(StringFormat("Closed %s basket: %s", direction==0?"BUY":"SELL", reason));
}

void FinaliseBasket(int direction)
{
   g_peakProfit[direction]          = 0.0;
   g_trailingActive[direction]      = false;
   g_partialStage[direction]        = 0;
   g_pendingPartialClose[direction] = false;
   g_recoveryMode[direction]        = false;
   g_maxBasketLoss[direction]       = 0.0;
   g_cooldownUntil                  = TimeCurrent() + InpCooldownSec;
   g_lastCloseTime                  = TimeCurrent();
   if(!g_isTester) SaveState();
}

//=====================================================================
// INITIAL ENTRY ORDER EXECUTION
//=====================================================================
void TryOpenNew(const Signal &sig)
{
   int direction = (sig.action == "BUY") ? 0 : 1;

   if(BasketCount(0) > 0 || BasketCount(1) > 0) return;
   if(sig.confidence < 0.60) return;
   if(TimeCurrent() < g_cooldownUntil) return;

   if(InpWaitNextBarAfterClose && g_lastCloseTime > 0)
   {
      datetime currentBarTime = (datetime)SeriesInfoInteger(Symbol(), PERIOD_M1, SERIES_LASTBAR_DATE);
      if(currentBarTime == 0) currentBarTime = TimeCurrent();
      if(currentBarTime <= g_lastCloseTime) return;
   }

   if(!SpreadAcceptable()) return;

   datetime lastTs = (direction == 0) ? g_lastOpenBuy : g_lastOpenSell;
   if(TimeCurrent() - lastTs < 30) return;

   double entry, tp_px;
   int tp_pts = (int)MathMax((double)sig.tp_points, (double)BasketCalcTpPoints(direction, 1));
   if(direction == 0)
   {
      entry = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      tp_px = NormPrice(entry + tp_pts * g_point * g_pointFactor);
   }
   else
   {
      entry = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      tp_px = NormPrice(entry - tp_pts * g_point * g_pointFactor);
   }

   string cmt = StringFormat("%s_%s_1", InpTradeCommentPrefix, direction==0?"BUY":"SELL");
   double open_lot = NormLot(InpInitialLot);
   bool ok = false;

   if(direction == 0) ok = g_trade.Buy (open_lot, Symbol(), 0.0, 0.0, tp_px, cmt);
   else               ok = g_trade.Sell(open_lot, Symbol(), 0.0, 0.0, tp_px, cmt);

   if(ok)
   {
      if(direction == 0) g_lastOpenBuy  = TimeCurrent();
      else               g_lastOpenSell = TimeCurrent();
      FinaliseBasket(direction);
      UpdateBasketCache();
      PrintFmt(StringFormat("NEW INITIAL ENTRY %s lot=%.2f TP=%.*f [Y-Swing=%.0f GridGap=%.0f] %s",
               sig.action, open_lot, g_digits, tp_px, GetYesterdaySwingPts(), CalculateDynamicGridGap(1), sig.reason));
   }
}

//=====================================================================
// CLOSED TRADE RECORDING & DEAL TRACKING
//=====================================================================
void RecordCloses()
{
   static datetime lastCheck = 0;
   datetime now = TimeCurrent();
   if(now - lastCheck < 1 && g_isTester) return;
   lastCheck = now;

   if(!HistorySelect(now - 86400 * 3, now)) return;
   int total = HistoryDealsTotal();
   static ulong lastProcessedDeal = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || ticket <= lastProcessedDeal) break;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != Symbol()) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)InpMagic) continue;

      long entry_type = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_INOUT) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      g_totalTrades++;
      g_totalProfit += profit;
      if(profit > 0)
      {
         g_winningTrades++;
         g_grossProfit += profit;
      }
      else
      {
         g_grossLoss += MathAbs(profit);
      }

      lastProcessedDeal = ticket;
   }
}

void ResetDay()
{
   g_dayStartTime   = TimeCurrent();
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyPl        = 0.0;
   g_peakEquity     = g_dayStartEquity;
}

void CheckDayRollover()
{
   MqlDateTime dtCurrent, dtStart;
   TimeToStruct(TimeCurrent(), dtCurrent);
   TimeToStruct(g_dayStartTime, dtStart);
   if(dtCurrent.day != dtStart.day)
   {
      ResetDay();
      if(!g_isTester) SaveState();
   }
}

void UpdateDailyPL(double eq)
{
   if(g_dayStartEquity > 0.0)
      g_dailyPl = eq - g_dayStartEquity;
}

void UpdateDD(double eq)
{
   if(eq > g_peakEquity) g_peakEquity = eq;
   if(g_peakEquity > 0.0)
      g_drawdownPct = (g_peakEquity - eq) / g_peakEquity * 100.0;
}

//=====================================================================
// UTILITIES
//=====================================================================
double NormPrice(double p) { return NormalizeDouble(p, g_digits); }

double NormLot(double lot)
{
   if(g_volStep <= 0.0) return lot;
   double steps = MathRound(lot / g_volStep);
   double res   = steps * g_volStep;
   return MathMax(g_volMin, MathMin(g_volMax, res));
}

void PrintFmt(const string msg)
{
   if(InpPrintDebug || !g_isTester) Print(msg);
}

ENUM_ORDER_TYPE_FILLING PickFilling()
{
   uint fillMode = (uint)SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
   if((fillMode & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   if((fillMode & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

//=====================================================================
// DASHBOARD
//=====================================================================
bool ShouldUpdateDashboard()
{
   if(!InpShowDashboard) return false;
   if(g_isOptimization) return false;
   if(g_isTester && !g_isVisual) return false;
   if(g_isVisual)
   {
      static uint s_lastDashTick = 0;
      uint now = GetTickCount();
      if(now - s_lastDashTick < 250) return false;
      s_lastDashTick = now;
   }
   return true;
}

void RefreshDashColors()
{
   if(!InpDashAutoColor)
   {
      g_dashBg     = InpDashBgColor;
      g_dashBorder = InpDashBorderColor;
      return;
   }
   color chartBg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   int r = (int)((chartBg >> 16) & 0xFF);
   int g = (int)((chartBg >> 8)  & 0xFF);
   int b = (int)(chartBg & 0xFF);
   int br = (int)MathMax(0, r - 20);
   int bg = (int)MathMax(0, g - 15);
   int bb = (int)MathMin(255, b + 8);
   g_dashBg = (color)((br<<16)|(bg<<8)|bb);
   int lr = (int)MathMin(255, r + 60);
   int lg = (int)MathMin(255, g + 80);
   int lb = (int)MathMin(255, b + 120);
   g_dashBorder = (color)((lr<<16)|(lg<<8)|lb);
}

#define DASH_COL_W   290
#define DASH_GAP     10
#define DASH_W       (DASH_COL_W * 2 + DASH_GAP)
#define ROW_H        16
#define BAR_H        5
#define SEC_GAP      6
#define DASH_FONT    "Consolas"
#define DASH_FONT_BOLD "Consolas"
#define DASH_PFX     "ZXSG_"

#define CLR_TITLE    C'240,240,240'
#define CLR_LABEL    C'140,150,165'
#define CLR_GREEN    C'39,174,96'
#define CLR_RED      C'231,76,60'
#define CLR_YELLOW   C'243,156,18'
#define CLR_CYAN     C'26,188,156'
#define CLR_ORANGE   C'230,126,34'
#define CLR_PURPLE   C'155,89,182'
#define CLR_WHITE    C'255,255,255'
#define CLR_DIVIDER  C'38,50,72'

void ObjDel(const string name) { ObjectDelete(0, name); }

void ObjRect(const string name, int x, int y, int w, int h, color bg, color border, int bw=1)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     border);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     bw);
}

void ObjLabel(const string name, int x, int y, const string txt, color clr, int fs=9, const string font="Consolas", int anchor=0)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString (0, name, OBJPROP_TEXT,      txt);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetString (0, name, OBJPROP_FONT,      font);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    anchor);
}

void ObjDivider(const string name, int x, int y, int w)
{
   ObjRect(name, x, y, w, 1, CLR_DIVIDER, CLR_DIVIDER, 0);
}

void ObjRow(const string lname, const string rname, int x, int y, int panelW, const string lbl, const string val, color lclr=0, color vclr=0)
{
   if(lclr == 0) lclr = CLR_LABEL;
   if(vclr == 0) vclr = CLR_WHITE;
   ObjLabel(lname, x + 8,          y, lbl, lclr, 9, DASH_FONT,      ANCHOR_LEFT);
   ObjLabel(rname, x + panelW - 8, y, val, vclr, 9, DASH_FONT_BOLD, ANCHOR_RIGHT);
}

void ObjBar(const string name, int x, int y, int maxW, double pct, color clr)
{
   pct = MathMax(0.0, MathMin(1.0, pct));
   int fillW = (int)MathRound(maxW * pct);
   string bgName = name + "_bg";
   ObjRect(bgName, x, y, maxW,  BAR_H, C'30,40,58', C'30,40,58', 0);
   if(fillW > 0)
      ObjRect(name,   x, y, fillW, BAR_H, clr, clr, 0);
   else
      ObjDel(name);
}

void DashInit() { }

void DashDelete()
{
   ObjectsDeleteAll(0, DASH_PFX);
   ChartRedraw();
}

void DashUpdate(double bal, double eq, double fm, TFView &views[], bool &viewsOk[])
{
   if(!InpShowDashboard) return;
   if(InpDashAutoColor) RefreshDashColors();
   int XL = InpDashX, XR = InpDashX + DASH_COL_W + DASH_GAP;
   int CW = DASH_COL_W;
   int cyL = InpDashY + 32, cyR = InpDashY + 32;

   double fm_pct = (eq > 0) ? fm / eq * 100.0 : 0.0;
   int cd_left = (int)MathMax(0.0, (double)(g_cooldownUntil - TimeCurrent()));
   double spread_pts = CurrentSpreadPts();

   // --- COLUMN 1: ACCOUNT & DYNAMIC SWING-GRID METRICS ---
   ObjLabel(DASH_PFX+"s1hdr", XL+8, cyL, "▌ ACCOUNT", CLR_TITLE, 9, DASH_FONT_BOLD); cyL += ROW_H+2;
   color pl_clr = (g_dailyPl >= 0) ? CLR_GREEN : CLR_RED;
   ObjRow(DASH_PFX+"r_bal_l", DASH_PFX+"r_bal_v", XL, cyL, CW, "Balance",   StringFormat("$%.2f", bal),    CLR_LABEL, CLR_WHITE); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_eq_l",  DASH_PFX+"r_eq_v",  XL, cyL, CW, "Equity",     StringFormat("$%.2f", eq),     CLR_LABEL, CLR_WHITE); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_fm_l",  DASH_PFX+"r_fm_v",  XL, cyL, CW, "FreeMgn",    StringFormat("%.1f%%", fm_pct), CLR_LABEL, fm_pct < InpMinFreeMarginPct ? CLR_RED : CLR_GREEN); cyL += ROW_H-1;
   ObjBar(DASH_PFX+"fmbar",   XL+8, cyL, CW-16, fm_pct / 100.0, fm_pct < InpMinFreeMarginPct ? CLR_RED : CLR_CYAN); cyL += BAR_H+2;
   ObjRow(DASH_PFX+"r_dpl_l", DASH_PFX+"r_dpl_v", XL, cyL, CW, "Day P&L",    StringFormat("%s$%.2f", g_dailyPl>=0?"+":"", g_dailyPl), CLR_LABEL, pl_clr); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_sp_l",  DASH_PFX+"r_sp_v",  XL, cyL, CW, "Spread",     StringFormat("%.1f pts", spread_pts), CLR_LABEL, spread_pts > InpMaxSpreadPts ? CLR_RED : CLR_GREEN); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_dd_l",  DASH_PFX+"r_dd_v",  XL, cyL, CW, "DrawDn",     StringFormat("%.2f%%", g_drawdownPct), CLR_LABEL, g_drawdownPct > 10 ? CLR_RED : CLR_YELLOW); cyL += ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div1", XL+6, cyL, CW-12); cyL += 3;
   ObjLabel(DASH_PFX+"s2hdr", XL+8, cyL, "▌ SWING-GRID METRICS", CLR_TITLE, 9, DASH_FONT_BOLD); cyL += ROW_H+2;
   double ySwing = GetYesterdaySwingPts();
   double gridAtr = GetGridAtrPts();
   double dynGap1 = CalculateDynamicGridGap(1);
   ObjRow(DASH_PFX+"r_ysw_l", DASH_PFX+"r_ysw_v", XL, cyL, CW, "Y-Swing (D1)", StringFormat("%.0f pts ($%.2f)", ySwing, ySwing * g_point * g_pointFactor), CLR_LABEL, CLR_CYAN); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_sgp_l", DASH_PFX+"r_sgp_v", XL, cyL, CW, "Swing/10 Part",StringFormat("%.1f pts", ySwing / InpSwingDivisor), CLR_LABEL, CLR_WHITE); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_atr_l", DASH_PFX+"r_atr_v", XL, cyL, CW, StringFormat("ATR Gap (%s)", EnumToString(InpGridAtrTf)), StringFormat("%.1f pts", gridAtr * InpGridAtrMult), CLR_LABEL, CLR_WHITE); cyL += ROW_H;
   ObjRow(DASH_PFX+"r_cgp_l", DASH_PFX+"r_cgp_v", XL, cyL, CW, "Layer 1 Gap",   StringFormat("%.0f pts ($%.2f)", dynGap1, dynGap1 * g_point * g_pointFactor), CLR_LABEL, CLR_YELLOW); cyL += ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div2", XL+6, cyL, CW-12); cyL += 3;
   ObjLabel(DASH_PFX+"s3hdr", XL+8, cyL, "▌ BASKET RECOVERY", CLR_TITLE, 9, DASH_FONT_BOLD); cyL += ROW_H+2;
   int buy_n = BasketCount(0), sell_n = BasketCount(1);
   double buy_pl = BasketProfit(0), sell_pl = BasketProfit(1);

   string buy_flags = "";
   if(g_trailingActive[0]) buy_flags += " TR";
   if(g_partialStage[0]>0) buy_flags += StringFormat(" PC%d", g_partialStage[0]);
   if(g_recoveryMode[0])   buy_flags += " RM";
   ObjRow(DASH_PFX+"r_bb_l", DASH_PFX+"r_bb_v", XL, cyL, CW,
          StringFormat("BUY %d/%d%s", buy_n, InpRecoveryMaxLayers, buy_flags),
          StringFormat("%s$%.2f", buy_pl >= 0 ? "+" : "", buy_pl),
          CLR_GREEN, (buy_pl >= 0) ? CLR_GREEN : CLR_RED); cyL += ROW_H;

   if(buy_n > 0)
   {
      ObjRow(DASH_PFX+"r_bavg_l", DASH_PFX+"r_bavg_v", XL, cyL, CW,
             "  Avg->TP", StringFormat("%.*f->%.*f", g_digits, BasketAvgPrice(0), g_digits, BasketTargetPrice(0)), CLR_LABEL, CLR_CYAN); cyL += ROW_H;
      ObjRow(DASH_PFX+"r_bnl_l", DASH_PFX+"r_bnl_v", XL, cyL, CW,
             "  Next Lot", StringFormat("%.2f (Gap:%.0fpts)", NextRecoveryLot(0), CalculateDynamicGridGap(buy_n)), CLR_LABEL, CLR_YELLOW); cyL += ROW_H;
      if(g_trailingActive[0])
      {
         ObjRow(DASH_PFX+"r_btr_l", DASH_PFX+"r_btr_v", XL, cyL, CW, "  Trail Peak", StringFormat("$%.2f", g_peakProfit[0]), CLR_LABEL, CLR_PURPLE); cyL += ROW_H;
      }
      else
      {
         ObjDel(DASH_PFX+"r_btr_l"); ObjDel(DASH_PFX+"r_btr_v");
      }
   }
   else
   {
      ObjDel(DASH_PFX+"r_bavg_l"); ObjDel(DASH_PFX+"r_bavg_v");
      ObjDel(DASH_PFX+"r_bnl_l");  ObjDel(DASH_PFX+"r_bnl_v");
      ObjDel(DASH_PFX+"r_btr_l");  ObjDel(DASH_PFX+"r_btr_v");
   }

   string sell_flags = "";
   if(g_trailingActive[1]) sell_flags += " TR";
   if(g_partialStage[1]>0) sell_flags += StringFormat(" PC%d", g_partialStage[1]);
   if(g_recoveryMode[1])   sell_flags += " RM";
   ObjRow(DASH_PFX+"r_sb_l", DASH_PFX+"r_sb_v", XL, cyL, CW,
          StringFormat("SELL %d/%d%s", sell_n, InpRecoveryMaxLayers, sell_flags),
          StringFormat("%s$%.2f", sell_pl >= 0 ? "+" : "", sell_pl),
          CLR_RED, (sell_pl >= 0) ? CLR_GREEN : CLR_RED); cyL += ROW_H;

   if(sell_n > 0)
   {
      ObjRow(DASH_PFX+"r_savg_l", DASH_PFX+"r_savg_v", XL, cyL, CW,
             "  Avg->TP", StringFormat("%.*f->%.*f", g_digits, BasketAvgPrice(1), g_digits, BasketTargetPrice(1)), CLR_LABEL, CLR_CYAN); cyL += ROW_H;
      ObjRow(DASH_PFX+"r_snl_l", DASH_PFX+"r_snl_v", XL, cyL, CW,
             "  Next Lot", StringFormat("%.2f (Gap:%.0fpts)", NextRecoveryLot(1), CalculateDynamicGridGap(sell_n)), CLR_LABEL, CLR_YELLOW); cyL += ROW_H;
      if(g_trailingActive[1])
      {
         ObjRow(DASH_PFX+"r_str_l", DASH_PFX+"r_str_v", XL, cyL, CW, "  Trail Peak", StringFormat("$%.2f", g_peakProfit[1]), CLR_LABEL, CLR_PURPLE); cyL += ROW_H;
      }
      else
      {
         ObjDel(DASH_PFX+"r_str_l"); ObjDel(DASH_PFX+"r_str_v");
      }
   }
   else
   {
      ObjDel(DASH_PFX+"r_savg_l"); ObjDel(DASH_PFX+"r_savg_v");
      ObjDel(DASH_PFX+"r_snl_l");  ObjDel(DASH_PFX+"r_snl_v");
      ObjDel(DASH_PFX+"r_str_l");  ObjDel(DASH_PFX+"r_str_v");
   }

   double total_float = buy_pl + sell_pl;
   ObjRow(DASH_PFX+"r_flt_l", DASH_PFX+"r_flt_v", XL, cyL, CW,
          "Float Total", StringFormat("%s$%.2f", total_float >= 0 ? "+" : "", total_float),
          CLR_LABEL, total_float >= 0 ? CLR_GREEN : CLR_RED); cyL += ROW_H+SEC_GAP;

   // --- COLUMN 2: CONFLUENCE, STATS & RISK LIMITS ---
   ObjLabel(DASH_PFX+"s5hdr", XR+8, cyR, "▌ DECISION MATRIX", CLR_TITLE, 9, DASH_FONT_BOLD); cyR += ROW_H+2;
   color reg_clr = CLR_CYAN;
   if(g_regime == "TREND_STRONG") reg_clr = CLR_GREEN;
   else if(g_regime == "VOLATILE") reg_clr = CLR_RED;
   else if(g_regime == "CHOPPY") reg_clr = CLR_ORANGE;
   ObjRow(DASH_PFX+"r_reg_l", DASH_PFX+"r_reg_v", XR, cyR, CW, "Regime",     g_regime, CLR_LABEL, reg_clr); cyR += ROW_H;
   color sig_clr = (g_lastSigAction == "BUY") ? CLR_GREEN : (g_lastSigAction == "SELL" ? CLR_RED : CLR_LABEL);
   ObjRow(DASH_PFX+"r_sig_l", DASH_PFX+"r_sig_v", XR, cyR, CW, "Action",     g_lastSigAction, CLR_LABEL, sig_clr); cyR += ROW_H;
   color status_clr = (g_status == "HALT") ? CLR_RED : (g_status == "ACTIVE" ? CLR_GREEN : CLR_YELLOW);
   ObjRow(DASH_PFX+"r_sta_l", DASH_PFX+"r_sta_v", XR, cyR, CW, "Status",     g_status, CLR_LABEL, status_clr); cyR += ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div5", XR+6, cyR, CW-12); cyR += 3;
   ObjLabel(DASH_PFX+"s6hdr", XR+8, cyR, "▌ TF CONFLUENCE", CLR_TITLE, 9, DASH_FONT_BOLD); cyR += ROW_H+2;
   string tfnms[5] = {"M1","M5","M15","H1","H4"};
   for(int i = 0; i < 5; i++)
   {
      if(!viewsOk[i])
      {
         ObjRow(DASH_PFX+"r_tf_l"+tfnms[i], DASH_PFX+"r_tf_v"+tfnms[i], XR, cyR, CW, tfnms[i], "...", CLR_LABEL, CLR_LABEL);
         cyR += ROW_H;
         continue;
      }
      TFView v = views[i];
      string tdir; color tclr;
      if(v.trend > 0)      { tdir = "▲"; tclr = CLR_GREEN; }
      else if(v.trend < 0) { tdir = "▼"; tclr = CLR_RED;   }
      else                 { tdir = "—"; tclr = CLR_LABEL; }
      ObjRow(DASH_PFX+"r_tf_l"+tfnms[i], DASH_PFX+"r_tf_v"+tfnms[i], XR, cyR, CW,
             StringFormat("%-3s R:%.0f A:%.0f", tfnms[i], v.rsi_val, v.adx_val), tdir, CLR_LABEL, tclr);
      cyR += ROW_H;
   }
   cyR += SEC_GAP;

   ObjDivider(DASH_PFX+"div6", XR+6, cyR, CW-12); cyR += 3;
   ObjLabel(DASH_PFX+"s7hdr", XR+8, cyR, "▌ BASKET STATISTICS", CLR_TITLE, 9, DASH_FONT_BOLD); cyR += ROW_H+2;
   double wr = (g_totalTrades > 0) ? (double)g_winningTrades / g_totalTrades * 100.0 : 0.0;
   color wr_clr = (wr >= 60) ? CLR_GREEN : (wr >= 45 ? CLR_YELLOW : CLR_RED);
   double dtpct = (InpDailyTargetUsd > 0) ? MathMax(0.0, MathMin(1.0, g_dailyPl / InpDailyTargetUsd)) : 0.0;

   double pf = (g_grossLoss > 0.0) ? g_grossProfit / g_grossLoss : 0.0;
   string pfStr = (g_grossLoss == 0.0 && g_grossProfit > 0.0) ? "∞" : StringFormat("%.2f", pf);
   color pf_clr = (pf >= 1.5 || g_grossLoss == 0.0) ? CLR_GREEN : (pf >= 1.0 ? CLR_YELLOW : CLR_RED);

   ObjRow(DASH_PFX+"r_trd_l", DASH_PFX+"r_trd_v", XR, cyR, CW, "Deals Closed", IntegerToString(g_totalTrades), CLR_LABEL, CLR_WHITE); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_wr_l",  DASH_PFX+"r_wr_v",  XR, cyR, CW, "Win Rate",     StringFormat("%.1f%% (%d/%d)", wr, g_winningTrades, g_totalTrades), CLR_LABEL, wr_clr); cyR += ROW_H-1;
   ObjBar(DASH_PFX+"wrbar",   XR+8, cyR, CW-16, wr / 100.0, wr_clr); cyR += BAR_H+2;
   ObjRow(DASH_PFX+"r_pf_l",  DASH_PFX+"r_pf_v",  XR, cyR, CW, "Profit Factor",pfStr, CLR_LABEL, pf_clr); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_net_l", DASH_PFX+"r_net_v", XR, cyR, CW, "Net P&L",      StringFormat("%s$%.2f", g_totalProfit >= 0 ? "+" : "", g_totalProfit), CLR_LABEL, g_totalProfit >= 0 ? CLR_GREEN : CLR_RED); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_dtg_l", DASH_PFX+"r_dtg_v", XR, cyR, CW, "Daily Target", StringFormat("$%.2f/$%.0f", g_dailyPl, InpDailyTargetUsd), CLR_LABEL, dtpct >= 1.0 ? CLR_GREEN : CLR_YELLOW); cyR += ROW_H-1;
   ObjBar(DASH_PFX+"dtgbar",  XR+8, cyR, CW-16, dtpct, dtpct >= 1.0 ? CLR_GREEN : CLR_CYAN); cyR += BAR_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div7", XR+6, cyR, CW-12); cyR += 3;
   ObjLabel(DASH_PFX+"s8hdr", XR+8, cyR, "▌ RISK LIMITS", CLR_TITLE, 9, DASH_FONT_BOLD); cyR += ROW_H+2;
   bool lm_halt = InpUseMaxEquityDdPct && (g_drawdownPct >= InpMaxEquityDdPct);
   bool lm_dtgt = (InpDailyTargetUsd > 0 && g_dailyPl >= InpDailyTargetUsd);
   bool lm_fm   = InpUseMinFreeMarginPct && (fm_pct < InpMinFreeMarginPct);
   bool lm_time = (InpUseTimeFilter && !AllowedHour());
   bool lm_cd   = (TimeCurrent() < g_cooldownUntil);
   bool lm_sprd = (spread_pts > InpMaxSpreadPts);

   ObjRow(DASH_PFX+"r_g1_l", DASH_PFX+"r_g1_v", XR, cyR, CW,
          StringFormat("MaxDD %s %.0f%%", InpUseMaxEquityDdPct ? "ON" : "OFF", InpMaxEquityDdPct), 
          !InpUseMaxEquityDdPct ? "OFF" : (lm_halt ? "✗ HIT" : "✓ OK"),  
          CLR_LABEL, !InpUseMaxEquityDdPct ? CLR_LABEL : (lm_halt ? CLR_RED : CLR_GREEN)); cyR += ROW_H;

   ObjRow(DASH_PFX+"r_g3_l", DASH_PFX+"r_g3_v", XR, cyR, CW, StringFormat("DlyTgt $%.0f", InpDailyTargetUsd), lm_dtgt ? "✓ HIT" : "OK", CLR_LABEL, lm_dtgt ? CLR_YELLOW : CLR_GREEN); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_g5_l", DASH_PFX+"r_g5_v", XR, cyR, CW, "Time Filter", lm_time ? "BLOCKED" : "OPEN", CLR_LABEL, lm_time ? CLR_YELLOW : CLR_GREEN); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_g6_l", DASH_PFX+"r_g6_v", XR, cyR, CW, "Cooldown",    lm_cd ? StringFormat("WAIT %ds", cd_left) : "Ready", CLR_LABEL, lm_cd ? CLR_ORANGE : CLR_GREEN); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_g7_l", DASH_PFX+"r_g7_v", XR, cyR, CW, StringFormat("Spread %dpts", InpMaxSpreadPts), lm_sprd ? "✗ HIGH" : "✓ OK", CLR_LABEL, lm_sprd ? CLR_RED : CLR_GREEN); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_g8_l", DASH_PFX+"r_g8_v", XR, cyR, CW, StringFormat("BasketSL %s $%.0f", InpUseBasketStopLoss ? "ON" : "OFF", InpMaxBasketLossUsd), "OK", CLR_LABEL, InpUseBasketStopLoss ? CLR_CYAN : CLR_LABEL); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_g9_l", DASH_PFX+"r_g9_v", XR, cyR, CW, "Trailing", InpTrailingEnable ? StringFormat("ON trig=$%.1f", InpTrailingTriggerUsd) : "OFF", CLR_LABEL, InpTrailingEnable ? CLR_CYAN : CLR_LABEL); cyR += ROW_H;
   ObjRow(DASH_PFX+"r_ga_l", DASH_PFX+"r_ga_v", XR, cyR, CW, "PartialClose", InpPartialCloseEnable ? StringFormat("ON @$%.1f", InpPartialCloseAtUsd) : "OFF", CLR_LABEL, InpPartialCloseEnable ? CLR_CYAN : CLR_LABEL); cyR += ROW_H+SEC_GAP;

   int cyBot = MathMax(cyL, cyR);
   ObjDivider(DASH_PFX+"divF", XL+6, cyBot, DASH_W-12); cyBot += 4;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   ObjLabel(DASH_PFX+"footer", XL + DASH_W / 2, cyBot,
            StringFormat("%04d-%02d-%02d  %02d:%02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec),
            CLR_LABEL, 8, DASH_FONT, ANCHOR_CENTER);
   cyBot += ROW_H+4;

   int totalH = cyBot - InpDashY + 6;
   ObjRect(DASH_PFX+"bg",    InpDashX, InpDashY, DASH_W, totalH, g_dashBg, g_dashBorder, 2);
   ObjRect(DASH_PFX+"coldiv",InpDashX + DASH_COL_W + (DASH_GAP / 2) - 1, InpDashY + 30, 2, totalH - 30, CLR_DIVIDER, CLR_DIVIDER, 0);
   ObjRect(DASH_PFX+"hdr",   InpDashX, InpDashY, DASH_W, 26, C'30,45,72', g_dashBorder, 0);
   ObjLabel(DASH_PFX+"title",InpDashX + 12, InpDashY + 5, "ZERITH XAU SWING-GRID RECOVERY", CLR_TITLE, 10, DASH_FONT_BOLD);
   ObjLabel(DASH_PFX+"sub",  InpDashX + DASH_W - 12, InpDashY + 6, Symbol() + "  DYNAMIC MT5", CLR_LABEL, 8, DASH_FONT, ANCHOR_RIGHT);
   ChartRedraw();
}
//+------------------------------------------------------------------+
