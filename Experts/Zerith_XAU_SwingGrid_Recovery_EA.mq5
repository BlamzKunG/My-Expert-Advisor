//+------------------------------------------------------------------+
//|                             Zerith_XAU_SwingGrid_Recovery_EA.mq5 |
//|                 Zerith Series / BlamzKunG                        |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//|  Dynamic SwingGrid Recovery: D1 Swing / 10 + Configurable TF ATR |
//+------------------------------------------------------------------+
#property copyright   "Zerith Series / BlamzKunG"
#property link        "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version     "1.00"
#property description "Zerith XAU SwingGrid Recovery MT5 - Dynamic Yesterday Daily Swing / 10 + Multi-TF ATR Spacing"
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
   int    trend;
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
   string action;
   string strategy;
   double confidence;
   string reason;
   int    tp_points;
};

struct SPosEntry
{
   ulong  ticket;
   double profit;
   datetime time; 
};

//=====================================================================
// INPUT PARAMETERS - Zerith XAU Scalping
//=====================================================================

input group ">>>> 1. Trading Basics"
input double   InpInitialLot          = 0.01;         // Base Initial Lot Size
input int      InpDeviation           = 30;           // Max Deviation / Slippage (Points)
input long     InpMagic               = 20260601;     // EA Magic Number (SwingGrid)
input string   InpTradeCommentPrefix  = "ZX_SwingGrid"; // Trade Comment Prefix

input group ">>>> 2. Zerith XAU Scalping: Decision Matrix & Regime"
input int      InpTrendAdx            = 25;           // Trend Threshold (ADX)
input int      InpRangeAdx            = 20;           // Range Threshold (ADX)
input double   InpVolatilityAtrPts    = 50.0;         // Volatility Threshold (M1 ATR Points)

input group ">>>> 3. Zerith XAU Scalping: ATR Dynamic Take-Profit"
input int      InpTpPointsBase        = 200;          // Base Take-Profit (Points)
input int      InpTpPointsMin         = 50;           // Minimum Take-Profit (Points)
input double   InpTpAtrMult           = 1.2;          // ATR Dynamic TP Multiplier

input group ">>>> 4. Dynamic Swing-Grid Recovery Spacing"
input double   InpSwingDivisor        = 10.0;         // Yesterday Daily Swing Divisor (Swing / 10)
input ENUM_TIMEFRAMES InpGridAtrTf    = PERIOD_H1;    // ATR Timeframe for Grid Calculation
input int      InpGridAtrPeriod       = 14;           // ATR Period for Grid Calculation
input double   InpGridAtrMult         = 1.0;          // ATR Multiplier for Grid Spacing
input int      InpRecoveryMinGap      = 100;          // Minimum Absolute Recovery Gap (Points)
input int      InpRecoveryMaxLayers   = 10;           // Maximum Recovery Layers Allowed

input group ">>>> 5. Zerith XAU Scalping: Adaptive Lot Sizing"
input double   InpLotMultEarly        = 1.3;          // Early Layer Lot Multiplier (1-2)
input double   InpLotMultMid          = 1.5;          // Mid Layer Lot Multiplier (3-5)
input double   InpLotMultLate         = 1.3;          // Late Layer Lot Multiplier
input bool     InpAntiMartingaleDeep  = true;         // Enable Deep Anti-Martingale (≥6)
input double   InpDeepLotMult         = 0.8;          // Deep Layer Multiplier (< 1.0)
input double   InpRecoveryMaxLot      = 5.0;          // Absolute Maximum Lot Cap
input double   InpVolNeutralAtr       = 500.0;        // Volatility Neutral ATR Reference (Pts)

input group ">>>> 6. Zerith XAU Scalping: Trailing Stop Basket"
input bool     InpTrailingEnable      = true;         // Enable Basket Trailing Stop
input double   InpTrailingTriggerUsd  = 5.0;          // Trailing Activation Basket Profit ($)
input double   InpTrailingStepUsd     = 2.0;          // Trailing Callback / Step ($)

input group ">>>> 7. Zerith XAU Scalping: Staged Partial Close"
input bool     InpPartialCloseEnable  = true;         // Enable Staged Partial Close
input double   InpPartialCloseAtUsd   = 4.0;          // Profit Trigger per Stage ($)
input double   InpPartialClosePct     = 30.0;         // Percentage of Winning Volume to Close (%)
input bool     InpStagedPartialClose  = true;         // Enable Multi-Stage Partial Close
input int      InpPartialCloseLevels  = 2;            // Maximum Partial Close Stages

input group ">>>> 8. Zerith XAU Scalping: Fast Recovery Exit Mode"
input bool     InpRecoveryModeEnable  = true;         // Enable Fast Recovery TP Mode
input int      InpRecoveryModeAtLayer = 4;            // Activate Recovery Mode at Layer (≥)
input int      InpRecoveryReducedTp   = 35;           // Reduced Fast Exit TP (Points)

input group ">>>> 9. Zerith XAU Scalping: Expert Basket Protection"
input bool     InpUseBasketStopLoss   = false;        // Enable Basket Hard Stop-Loss ($)
input double   InpMaxBasketLossUsd    = 30.0;         // Basket Hard Stop-Loss ($)
input int      InpBasketMaxAgeHours   = 8;            // Basket Max Holding Time (Hours)
input int      InpMaxSpreadPts        = 50;           // Max Allowed Spread (Points)
input int      InpMaxRecoveryAttempts = 8;            // Max Recovery Attempts Allowed
input bool     InpBreakevenExit       = true;         // Breakeven Exit After Deep Drawdown
input double   InpBreakevenTriggerUsd = 1.0;          // Breakeven Trigger Base ($)
input double   InpBreakevenBufferPts  = 5;            // Breakeven Profit Buffer (Points)

input group ">>>> 10. Zerith XAU Scalping: Capital & Risk Guards"
input double   InpDailyTargetUsd      = 50.0;         // Daily Profit Target ($)
input bool     InpUseMaxEquityDdPct   = false;        // Enable Max Equity Drawdown Guard
input double   InpMaxEquityDdPct      = 50.0;         // Max Equity Drawdown Allowed (%)
input bool     InpUseMinFreeMarginPct = false;        // Enable Min Free Margin Guard
input double   InpMinFreeMarginPct    = 30.0;         // Min Free Margin Allowed (%)
input int      InpCooldownSec         = 15;           // Base Cooldown After Close (Seconds)
input bool     InpWaitNextBarAfterClose = true;       // Wait for Next M1 Bar After Close

input group ">>>> 11. Zerith XAU Scalping: Session & Time Filters"
input bool     InpUseTimeFilter       = false;        // Enable Trading Session Filter
input int      InpAllowHourFrom       = 6;            // Trading Start Hour (UTC)
input int      InpAllowHourTo         = 20;           // Trading End Hour (UTC)
input int      InpServerGMTOffset     = 2;            // Broker Server GMT Offset

input group ">>>> 12. Zerith XAU Scalping: Chart History & Debug"
input int      InpBarsM1              = 300;          // M1 History Bars to Load
input int      InpBarsHTF             = 200;          // Higher TF History Bars to Load
input bool     InpPrintDebug          = false;        // Print Detailed Diagnostic Logs

input group ">>>> 13. Zerith XAU Scalping: Visual Dashboard"
input bool     InpShowDashboard       = true;         // Display On-Chart Dashboard
input int      InpDashX               = 20;           // Dashboard X Coordinate
input int      InpDashY               = 30;           // Dashboard Y Coordinate
input bool     InpDashAutoColor       = true;         // Auto Detect Dark/Light Background
input color    InpDashBgColor         = C'18,24,38';  // Dashboard Background Color
input color    InpDashBorderColor     = C'52,152,219';// Dashboard Border Color

//=====================================================================
// GLOBALS
//=====================================================================
// Tester & Optimization environment flags
bool     g_isTester       = false;
bool     g_isOptimization = false;
bool     g_isVisual       = false;

// Cached symbol trading properties
double   g_volStep        = 0.01;
double   g_volMin         = 0.01;
double   g_volMax         = 100.0;
int      g_stopsLevel     = 0;

// Single-Pass Basket Cache (O(1) lookups instead of looping PositionsTotal())
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
SBasketCache g_bStats[2]; // 0: BUY, 1: SELL
CTrade         g_trade;
CPositionInfo  g_pos;
CSymbolInfo    g_sym;

double   g_point;
int      g_digits;
double   g_pointFactor;

double   g_dayStartEquity   = 0.0;
datetime g_dayStartTime     = 0;
double   g_peakEquity       = 0.0;
double   g_dailyPl          = 0.0;
double   g_drawdownPct      = 0.0;

datetime g_cooldownUntil    = 0;
datetime g_lastOpenBuy      = 0;
datetime g_lastOpenSell     = 0;
datetime g_lastRecBuy       = 0;
datetime g_lastRecSell      = 0;
datetime g_lastCloseTime    = 0;

double   g_atrM1            = 0.0;
double   g_atrM1Pts         = 0.0;
int      g_atrGridHandle    = INVALID_HANDLE; // Handle for Dynamic Grid ATR

double g_scoreTrend         = 0.5;
double g_scoreMeanRev       = 0.5;
double g_scoreBreakout      = 0.5;
double g_scorePullback      = 0.5;

#define PERF_BUF 30
double g_perfTrend   [PERF_BUF]; int g_perfTrendIdx   = 0; int g_perfTrendN   = 0;
double g_perfMeanRev [PERF_BUF]; int g_perfMeanRevIdx = 0; int g_perfMeanRevN = 0;
double g_perfBreakout[PERF_BUF]; int g_perfBreakoutIdx= 0; int g_perfBreakoutN= 0;
double g_perfPullback[PERF_BUF]; int g_perfPullbackIdx= 0; int g_perfPullbackN= 0;

// [v17.00] Basket-level statistics (replaces per-position counting)
int    g_totalTrades   = 0;
double g_totalProfit   = 0.0;
int    g_winningTrades = 0;
double g_grossProfit   = 0.0;   // [v17.00] For profit factor
double g_grossLoss     = 0.0;   // [v17.00] For profit factor

// [v17.00] Basket accumulator - collects profits until basket fully closes
double   g_basketAccumProfit[2];       // Accumulated profit per direction
int      g_basketAccumCount[2];        // Count of closed positions per direction
string   g_basketAccumStrategy[2];     // Strategy from initial position
bool     g_basketAccumHasRecovery[2];  // Whether basket had recovery trades
datetime g_basketAccumTime[2];         // When first close was detected (for timeout)

string g_regime  = "UNKNOWN";
string g_status  = "INIT";

string g_lastSigAction     = "WAIT";
string g_lastSigStrategy   = "-";
double g_lastSigConfidence = 0.0;
string g_lastSigReason     = "";

#define DASH_PFX   "ZERITH_DASH_"
#define MAX_TRACKED 200
ulong  g_trackedTickets [MAX_TRACKED];
ulong  g_trackedPosIds  [MAX_TRACKED];
double g_trackedProfits [MAX_TRACKED];
string g_trackedComments[MAX_TRACKED];
double g_trackedVols    [MAX_TRACKED];
double g_trackedOpen    [MAX_TRACKED];
int    g_trackedDir     [MAX_TRACKED];
int    g_trackedCount   = 0;

ulong  g_pendingHistIds    [MAX_TRACKED];
double g_pendingHistProfits[MAX_TRACKED];
string g_pendingHistCmts   [MAX_TRACKED];
double g_pendingHistVols   [MAX_TRACKED];
int    g_pendingHistDirs   [MAX_TRACKED];
int    g_pendingHistCount  = 0;

double   g_peakProfit[2];
bool     g_trailingActive[2];
int      g_partialStage[2];
bool     g_pendingPartialClose[2];
bool     g_recoveryMode[2];
double   g_maxBasketLoss[2];

double   g_supportPx = 0.0;
double   g_resistPx  = 0.0;

int g_saveCounter = 0;
string   g_gvPrefix = "";
color    g_dashBg;
color    g_dashBorder;

// HTF analysis cache
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
string EvaluateMarketRegime(const TFView &m1, const TFView &m5, const TFView &m15, const TFView &h1); 
void   DecideSignal(TFView &views[], bool &viewsOk[], Signal &out); 
double GetStratScore(const string strat);
void   RecordOutcome(const string strat, double pnl);
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
double GetBasketFinalTarget(int direction);
double NextRecoveryLot(int direction); 
void   CloseAllPositions(const string reason);
void   CloseBasket(int direction, const string reason);
void   FinaliseBasket(int direction);
double GetYesterdaySwingPts();
double GetGridAtrPts();
void   ManageRecovery(TFView &views[], bool &viewsOk[]); 
void   ManageBasketRisk(int direction);
void   ManageBreakevenExit(int direction);
void   UpdateMaxBasketLoss(int direction);
void   UpdateBasketTPs();
void   TryOpenNew(const Signal &sig);
void   RecordCloses();
void   ProcessPendingHistory();
bool   HasPendingForDirection(int direction);       // [v17.00]
void   TryRecordBasketTrade(int direction);          // [v17.00]
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

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFilling(PickFilling());
   g_trade.SetAsyncMode(false);

   g_gvPrefix = StringFormat("ZXSWING_%I64d_%s_", InpMagic, Symbol());
   g_atrGridHandle = iATR(Symbol(), InpGridAtrTf, InpGridAtrPeriod);

   g_isTester       = (bool)MQLInfoInteger(MQL_TESTER);
   g_isOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   g_isVisual       = (bool)MQLInfoInteger(MQL_VISUAL_MODE);

   g_volStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   g_volMin  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   g_volMax  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   if(g_volStep <= 0) g_volStep = 0.01;
   if(g_volMin  <= 0) g_volMin  = 0.01;
   if(g_volMax  <= 0) g_volMax  = 100.0;

   g_stopsLevel = (int)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);

   if(InpTrailingEnable && InpTrailingStepUsd >= InpTrailingTriggerUsd)
      PrintFmt("WARN: TrailingStep >= TrailingTrigger.");
   if(InpPartialCloseEnable && InpPartialClosePct <= 0)
      { Print("ERROR: InpPartialClosePct must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRecoveryModeEnable && InpRecoveryModeAtLayer < 1)
      { Print("ERROR: InpRecoveryModeAtLayer must be >= 1"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRecoveryModeEnable && InpRecoveryReducedTp <= 0)
      { Print("ERROR: InpRecoveryReducedTp must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpInitialLot <= 0)
      { Print("ERROR: InpInitialLot must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpUseBasketStopLoss && InpMaxBasketLossUsd <= 0)
      { Print("ERROR: InpMaxBasketLossUsd must be > 0 when enabled"); return INIT_PARAMETERS_INCORRECT; }
   if(InpMaxRecoveryAttempts > InpRecoveryMaxLayers)
      { Print("ERROR: InpMaxRecoveryAttempts must be <= InpRecoveryMaxLayers"); return INIT_PARAMETERS_INCORRECT; }

   ArrayInitialize(g_perfTrend,    0.5);
   ArrayInitialize(g_perfMeanRev,  0.5);
   ArrayInitialize(g_perfBreakout, 0.5);
   ArrayInitialize(g_perfPullback, 0.5);

   // [v17.00] Initialize basket accumulators
   for(int d = 0; d < 2; d++)
   {
      g_peakProfit[d]          = 0.0;
      g_trailingActive[d]      = false;
      g_partialStage[d]        = 0;
      g_pendingPartialClose[d] = false;
      g_recoveryMode[d]        = false;
      g_maxBasketLoss[d]       = 0.0;
      g_basketAccumProfit[d]   = 0.0;
      g_basketAccumCount[d]    = 0;
      g_basketAccumStrategy[d] = "";
      g_basketAccumHasRecovery[d] = false;
      g_basketAccumTime[d]     = 0;
   }
   g_pendingHistCount = 0;
   g_grossProfit = 0.0;
   g_grossLoss   = 0.0;

   ResetDay();
   if(g_peakEquity <= 0.0) g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   LoadState();

   PrintFmt(StringFormat("Zerith XAU SwingGrid Recovery v1.00 EXPERT | %s digits=%d point=%.5f factor=%.0f",
            Symbol(), g_digits, g_point, g_pointFactor));
   
   if(ShouldUpdateDashboard())
   {
      RefreshDashColors();
      DashInit();
   }
   return INIT_SUCCEEDED;
}

//=====================================================================
// OnDeinit
//=====================================================================
void OnDeinit(const int reason)
{
   if(!g_isTester) SaveState();
   if(g_atrGridHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrGridHandle);
      g_atrGridHandle = INVALID_HANDLE;
   }
   DashDelete();
}

//=====================================================================
// OnTick
//=====================================================================
void OnTick()
{
   g_sym.RefreshRates();
   CheckDayRollover();
   UpdateBasketCache();

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   UpdateDailyPL(eq);
   UpdateDD(eq);
   RecordCloses();
   ProcessPendingHistory();

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
      g_atrM1Pts = (double)InpRecoveryMinGap;

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

   for(int d=0; d<2; d++) UpdateMaxBasketLoss(d);
   for(int d=0; d<2; d++) ManageBasketRisk(d);

   for(int d = 0; d < 2; d++)
      if(g_pendingPartialClose[d]) RetryPartialClose(d);

   if(InpPartialCloseEnable)
      for(int d = 0; d < 2; d++)
         ManagePartialClose(d);

   if(InpTrailingEnable)
      for(int d = 0; d < 2; d++)
         ManageTrailing(d);

   if(g_status == "ACTIVE" || g_status == "RECOVERY_ONLY")
      ManageRecovery(views, viewsOk);

   if(g_status == "ACTIVE" && (sig.action == "BUY" || sig.action == "SELL") && SpreadAcceptable())
      TryOpenNew(sig);

   // [v17.00] Try to record basket trades before opening new ones
   for(int d=0; d<2; d++) TryRecordBasketTrade(d);

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
      GlobalVariableSet(GVKey(dirs[d] + "_trailing"),  g_trailingActive[d]      ? 1.0 : 0.0);
      GlobalVariableSet(GVKey(dirs[d] + "_pstage"),    (double)g_partialStage[d]);
      GlobalVariableSet(GVKey(dirs[d] + "_pendingpc"), g_pendingPartialClose[d] ? 1.0 : 0.0);
      GlobalVariableSet(GVKey(dirs[d] + "_recmode"),   g_recoveryMode[d]        ? 1.0 : 0.0);
      GlobalVariableSet(GVKey(dirs[d] + "_maxloss"),   g_maxBasketLoss[d]);
      // [v17.00] Save basket accumulators
      GlobalVariableSet(GVKey(dirs[d] + "_baprof"),    g_basketAccumProfit[d]);
      GlobalVariableSet(GVKey(dirs[d] + "_bacount"),   (double)g_basketAccumCount[d]);
      GlobalVariableSet(GVKey(dirs[d] + "_batime"),    (double)(long)g_basketAccumTime[d]);
   }
   GlobalVariableSet(GVKey("score_trend"),    g_scoreTrend);
   GlobalVariableSet(GVKey("score_meanrev"),  g_scoreMeanRev);
   GlobalVariableSet(GVKey("score_breakout"), g_scoreBreakout);
   GlobalVariableSet(GVKey("score_pullback"), g_scorePullback);
   GlobalVariableSet(GVKey("lastRecBuy"),     (double)(long)g_lastRecBuy);
   GlobalVariableSet(GVKey("lastRecSell"),    (double)(long)g_lastRecSell);
   GlobalVariableSet(GVKey("day_start"),      (double)(long)g_dayStartTime);
   GlobalVariableSet(GVKey("day_start_eq"),   g_dayStartEquity);
   GlobalVariableSet(GVKey("peak_equity"),    g_peakEquity);
   GlobalVariableSet(GVKey("total_trades"),   (double)g_totalTrades);
   GlobalVariableSet(GVKey("total_profit"),   g_totalProfit);
   GlobalVariableSet(GVKey("winning_trades"), (double)g_winningTrades);
   // [v17.00] Save gross profit/loss for profit factor
   GlobalVariableSet(GVKey("gross_profit"),   g_grossProfit);
   GlobalVariableSet(GVKey("gross_loss"),     g_grossLoss);
   GlobalVariableSet(GVKey("cooldown_until"), (double)(long)g_cooldownUntil);
   GlobalVariableSet(GVKey("last_close_time"),(double)(long)g_lastCloseTime);
}

void LoadState()
{
   string dirs[2] = {"buy", "sell"};
   for(int d = 0; d < 2; d++)
   {
      string pk = GVKey(dirs[d] + "_peak");
      if(GlobalVariableCheck(pk)) g_peakProfit[d] = GlobalVariableGet(pk);
      string tr = GVKey(dirs[d] + "_trailing");
      if(GlobalVariableCheck(tr)) g_trailingActive[d] = GlobalVariableGet(tr) > 0.5;
      string ps = GVKey(dirs[d] + "_pstage");
      if(GlobalVariableCheck(ps)) g_partialStage[d] = (int)GlobalVariableGet(ps);
      else                        g_partialStage[d] = 0;
      string pp = GVKey(dirs[d] + "_pendingpc");
      if(GlobalVariableCheck(pp)) g_pendingPartialClose[d] = GlobalVariableGet(pp) > 0.5;
      string rm = GVKey(dirs[d] + "_recmode");
      if(GlobalVariableCheck(rm)) g_recoveryMode[d] = GlobalVariableGet(rm) > 0.5;
      string ml = GVKey(dirs[d] + "_maxloss");
      if(GlobalVariableCheck(ml)) g_maxBasketLoss[d] = GlobalVariableGet(ml);
      // [v17.00] Load basket accumulators
      string bp = GVKey(dirs[d] + "_baprof");
      if(GlobalVariableCheck(bp)) g_basketAccumProfit[d] = GlobalVariableGet(bp);
      string bc = GVKey(dirs[d] + "_bacount");
      if(GlobalVariableCheck(bc)) g_basketAccumCount[d] = (int)GlobalVariableGet(bc);
      string bt = GVKey(dirs[d] + "_batime");
      if(GlobalVariableCheck(bt)) g_basketAccumTime[d] = (datetime)(long)GlobalVariableGet(bt);
   }
   string st = GVKey("score_trend");    if(GlobalVariableCheck(st))  g_scoreTrend    = GlobalVariableGet(st);
   string sm = GVKey("score_meanrev");  if(GlobalVariableCheck(sm))  g_scoreMeanRev  = GlobalVariableGet(sm);
   string sb = GVKey("score_breakout"); if(GlobalVariableCheck(sb))  g_scoreBreakout = GlobalVariableGet(sb);
   string sp = GVKey("score_pullback"); if(GlobalVariableCheck(sp))  g_scorePullback = GlobalVariableGet(sp);

   string pe = GVKey("peak_equity");
   if(GlobalVariableCheck(pe)) { double sv = GlobalVariableGet(pe); if(sv > 0.0) g_peakEquity = sv; }

   string tt = GVKey("total_trades");   if(GlobalVariableCheck(tt)) g_totalTrades   = (int)GlobalVariableGet(tt);
   string tp = GVKey("total_profit");   if(GlobalVariableCheck(tp)) g_totalProfit   = GlobalVariableGet(tp);
   string tw = GVKey("winning_trades"); if(GlobalVariableCheck(tw)) g_winningTrades = (int)GlobalVariableGet(tw);
   // [v17.00] Load gross profit/loss
   string gp = GVKey("gross_profit");   if(GlobalVariableCheck(gp)) g_grossProfit   = GlobalVariableGet(gp);
   string gl = GVKey("gross_loss");     if(GlobalVariableCheck(gl)) g_grossLoss     = GlobalVariableGet(gl);

   string lrb = GVKey("lastRecBuy");  if(GlobalVariableCheck(lrb)) g_lastRecBuy  = (datetime)(long)GlobalVariableGet(lrb);
   string lrs = GVKey("lastRecSell"); if(GlobalVariableCheck(lrs)) g_lastRecSell = (datetime)(long)GlobalVariableGet(lrs);

   string cu = GVKey("cooldown_until");
   if(GlobalVariableCheck(cu)) { datetime sc = (datetime)(long)GlobalVariableGet(cu); if(sc > TimeCurrent()) g_cooldownUntil = sc; }

   string lct = GVKey("last_close_time");
   if(GlobalVariableCheck(lct)) g_lastCloseTime = (datetime)(long)GlobalVariableGet(lct);

   string ds = GVKey("day_start");
   if(GlobalVariableCheck(ds))
   {
      datetime savedDay = (datetime)(long)GlobalVariableGet(ds);
      MqlDateTime n, s;
      TimeToStruct(TimeCurrent(), n);
      TimeToStruct(savedDay, s);
      if((n.day != s.day || n.mon != s.mon || n.year != s.year) && PositionsTotal() == 0)
      {
         PrintFmt("LoadState: day rolled over with no open positions - resetting stale basket flags");
         for(int d = 0; d < 2; d++) FinaliseBasket(d);
      }
      else
      {
         string dse = GVKey("day_start_eq");
         if(GlobalVariableCheck(dse)) { double sv = GlobalVariableGet(dse); if(sv > 0.0) g_dayStartEquity = sv; }
      }
   }
}

void FinaliseBasket(int direction)
{
   g_peakProfit[direction]          = 0.0;
   g_trailingActive[direction]      = false;
   g_partialStage[direction]        = 0;
   g_pendingPartialClose[direction] = false;
   g_recoveryMode[direction]        = false;
   g_maxBasketLoss[direction]       = 0.0;
}

//=====================================================================
// INDICATORS
//=====================================================================
void CalcEMA(const double &src[], double &out[], int period, int count)
{
   if(count < 1) return;
   double alpha = 2.0 / (period + 1.0);
   out[0] = src[0];
   for(int i = 1; i < count; i++)
      out[i] = alpha * src[i] + (1.0 - alpha) * out[i-1];
}

double CalcRSI(const double &close[], int count, int period)
{
   if(count < period + 1 || period <= 0) return 50.0;
   double ag = 0.0, al = 0.0;
   for(int i = 1; i <= period; i++)
   {
      double d = close[i] - close[i-1];
      if(d > 0) ag += d; else al -= d;
   }
   ag /= period; al /= period;
   double alpha = 1.0 / period;
   for(int i = period + 1; i < count; i++)
   {
      double d = close[i] - close[i-1];
      ag = alpha*(d>0?d:0.0)  + (1.0-alpha)*ag;
      al = alpha*(d<0?-d:0.0) + (1.0-alpha)*al;
   }
   if(al == 0.0) return 100.0;
   return 100.0 - 100.0/(1.0 + ag/al);
}

double CalcATR(const double &high[], const double &low[], const double &close[], int count, int period)
{
   if(count < period + 1) return 0.0;
   double atr_val = 0.0;
   for(int i = 1; i <= period; i++)
   {
      double tr = MathMax(high[i]-low[i], MathMax(MathAbs(high[i]-close[i-1]), MathAbs(low[i]-close[i-1])));
      atr_val += tr;
   }
   atr_val /= period;
   double alpha = 1.0/period;
   for(int i = period+1; i < count; i++)
   {
      double tr = MathMax(high[i]-low[i], MathMax(MathAbs(high[i]-close[i-1]), MathAbs(low[i]-close[i-1])));
      atr_val = alpha*tr + (1.0-alpha)*atr_val;
   }
   return atr_val;
}

void CalcADX(const double &high[], const double &low[], const double &close[], int count, int period,
             double &adx_out, double &pdi_out, double &mdi_out)
{
   adx_out = pdi_out = mdi_out = 0.0;
   if(count < period + 2) return;
   double alpha = 1.0/period;
   double atr_s=0, pdm_s=0, mdm_s=0;
   for(int i=1;i<=period;i++)
   {
      double up=high[i]-high[i-1], dn=low[i-1]-low[i];
      double pdm=(up>dn&&up>0)?up:0.0, mdm=(dn>up&&dn>0)?dn:0.0;
      double tr=MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));
      atr_s+=tr; pdm_s+=pdm; mdm_s+=mdm;
   }
   atr_s/=period; pdm_s/=period; mdm_s/=period;
   double pdi=(atr_s>0)?100.0*pdm_s/atr_s:0.0, mdi=(atr_s>0)?100.0*mdm_s/atr_s:0.0;
   double dxs=(pdi+mdi>0)?100.0*MathAbs(pdi-mdi)/(pdi+mdi):0.0, adxs=dxs;
   for(int i=period+1;i<count;i++)
   {
      double up=high[i]-high[i-1],dn=low[i-1]-low[i];
      double pdm=(up>dn&&up>0)?up:0.0,mdm=(dn>up&&dn>0)?dn:0.0;
      double tr=MathMax(high[i]-low[i],MathMax(MathAbs(high[i]-close[i-1]),MathAbs(low[i]-close[i-1])));
      atr_s=alpha*tr+(1-alpha)*atr_s; pdm_s=alpha*pdm+(1-alpha)*pdm_s; mdm_s=alpha*mdm+(1-alpha)*mdm_s;
      pdi=(atr_s>0)?100.0*pdm_s/atr_s:0.0; mdi=(atr_s>0)?100.0*mdm_s/atr_s:0.0;
      double dx=(pdi+mdi>0)?100.0*MathAbs(pdi-mdi)/(pdi+mdi):0.0;
      adxs=alpha*dx+(1-alpha)*adxs;
   }
   adx_out=adxs; pdi_out=pdi; mdi_out=mdi;
}

double CalcBBWidth(const double &close[], int count, int period)
{
   if(count < period) return 0.0;
   int start = count-period;
   double sum=0.0;
   for(int i=start;i<count;i++) sum+=close[i];
   double mean=sum/period, var=0.0;
   for(int i=start;i<count;i++) var+=(close[i]-mean)*(close[i]-mean);
   double sd=MathSqrt(var/period);
   return (mean>0)?(4.0*sd)/mean:0.0;
}

void CalcMACDArr(const double &close[], double &out[], int count, int fast=12, int slow=26, int signal_p=9)
{
   if(ArraySize(out) < count) ArrayResize(out, count);
   if(count < slow+signal_p+2) { ArrayInitialize(out, 0.0); return; }
   double af=2.0/(fast+1.0), as_=2.0/(slow+1.0), ag=2.0/(signal_p+1.0);
   double ef=close[0], es=close[0], ml=0.0, sig=0.0;
   out[0] = 0.0;
   for(int i=1;i<count;i++)
   { 
      ef=af*close[i]+(1-af)*ef; 
      es=as_*close[i]+(1-as_)*es; 
      ml=ef-es; 
      sig=ag*ml+(1-ag)*sig; 
      out[i] = ml-sig; 
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
   if(CopyHigh(Symbol(),tf,0,n_bars,high_arr) < 80) return false;
   if(CopyLow (Symbol(),tf,0,n_bars,low_arr ) < 80) return false;
   int cnt = ArraySize(close_arr);
   static double ema_f[], ema_s[];
   if(ArraySize(ema_f) < cnt) ArrayResize(ema_f, cnt);
   if(ArraySize(ema_s) < cnt) ArrayResize(ema_s, cnt);
   CalcEMA(close_arr,ema_f,20,cnt);
   CalcEMA(close_arr,ema_s,50,cnt);
   double lc=close_arr[cnt-1], ef=ema_f[cnt-1], es=ema_s[cnt-1];
   int trend=0;
   if(ef>es && lc>ef) trend=1; else if(ef<es && lc<ef) trend=-1;
   double adx_v,pdi_v,mdi_v;
   CalcADX(high_arr,low_arr,close_arr,cnt,14,adx_v,pdi_v,mdi_v);

   static double macd_arr[];
   CalcMACDArr(close_arr, macd_arr, cnt, 12, 26, 9);

   v.tf_name      = tf_name;
   v.trend        = trend;
   v.adx_val      = adx_v;
   v.atr_val      = CalcATR(high_arr,low_arr,close_arr,cnt,14);
   v.rsi_val      = CalcRSI(close_arr,cnt,14);
   v.bb_width     = (cnt >= 20) ? CalcBBWidth(close_arr,cnt,20) : 0.0;
   v.macd_hist     = macd_arr[cnt-1];
   v.macd_hist_prev = macd_arr[cnt-2];
   v.last_close = lc;
   v.ema_fast   = ef;
   v.ema_slow   = es;
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
   ArraySetAsSeries(low_arr, true);
   if(CopyHigh(Symbol(), PERIOD_H1, 1, 100, high_arr) < 100) return;
   if(CopyLow (Symbol(), PERIOD_H1, 1, 100, low_arr) < 100) return;
   double maxHigh = high_arr[0];
   double minLow  = low_arr[0];
   for(int i=1; i<100; i++) {
      if(high_arr[i] > maxHigh) maxHigh = high_arr[i];
      if(low_arr[i] < minLow)  minLow  = low_arr[i];
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
   if(m5.atr_val > 0 && m1.atr_val > m5.atr_val * 1.5) return "VOLATILE";
   if(g_atrM1Pts > InpVolatilityAtrPts) return "VOLATILE";
   if(m15.trend > 0 && h1.trend < 0) return "CHOPPY";
   if(m15.trend < 0 && h1.trend > 0) return "CHOPPY";
   if(h1.adx_val > InpTrendAdx && m15.adx_val > 20 && h1.trend != 0) return "TREND_STRONG";
   if(h1.adx_val < InpRangeAdx) return "RANGE";
   return "NORMAL";
}

//=====================================================================
// SIGNAL DECISION
//=====================================================================
void DecideSignal(TFView &views[], bool &viewsOk[], Signal &out)
{
   out.action="WAIT"; out.strategy="-"; out.confidence=0.0; out.reason="no setup"; out.tp_points=InpTpPointsBase;
   TFView m1=views[0], m5=views[1], m15=views[2], h1=views[3];

   if(g_regime == "TREND_STRONG") {
      if(h1.trend>0 && m1.rsi_val<40 && m1.macd_hist>m1.macd_hist_prev) {
         out.action="BUY"; out.strategy="PULLBACK"; out.confidence=0.8; out.reason="Trend UP, M1 dip"; out.tp_points=(int)(InpTpPointsBase*1.1);
      } else if(h1.trend<0 && m1.rsi_val>60 && m1.macd_hist<m1.macd_hist_prev) {
         out.action="SELL"; out.strategy="PULLBACK"; out.confidence=0.8; out.reason="Trend DN, M1 pop"; out.tp_points=(int)(InpTpPointsBase*1.1);
      }
   }
   else if(g_regime == "RANGE") {
      if(m1.rsi_val<=28 && m5.rsi_val<=40) {
         out.action="BUY"; out.strategy="MEAN_REV"; out.confidence=0.7; out.reason="RSI oversold in Range"; out.tp_points=(int)(InpTpPointsBase*0.9);
      } else if(m1.rsi_val>=72 && m5.rsi_val>=60) {
         out.action="SELL"; out.strategy="MEAN_REV"; out.confidence=0.7; out.reason="RSI overbought in Range"; out.tp_points=(int)(InpTpPointsBase*0.9);
      }
   }
   else if(g_regime == "VOLATILE") {
      if(m1.trend>0 && m1.macd_hist>0) {
         out.action="BUY"; out.strategy="BREAKOUT"; out.confidence=0.6; out.reason="Volatility BUY"; out.tp_points=(int)(InpTpPointsBase*1.2);
      } else if(m1.trend<0 && m1.macd_hist<0) {
         out.action="SELL"; out.strategy="BREAKOUT"; out.confidence=0.6; out.reason="Volatility SELL"; out.tp_points=(int)(InpTpPointsBase*1.2);
      }
   }
   else if(g_regime == "CHOPPY") {
      out.reason = "Choppy Market - Stay Out";
   }
   else if(g_regime == "NORMAL") {
      if(m1.rsi_val<=35 && m5.rsi_val<=45 && m1.macd_hist>m1.macd_hist_prev) {
         out.action="BUY"; out.strategy="MEAN_REV"; out.confidence=0.65; out.reason="Normal regime, mild oversold"; out.tp_points=InpTpPointsBase;
      } else if(m1.rsi_val>=65 && m5.rsi_val>=55 && m1.macd_hist<m1.macd_hist_prev) {
         out.action="SELL"; out.strategy="MEAN_REV"; out.confidence=0.65; out.reason="Normal regime, mild overbought"; out.tp_points=InpTpPointsBase;
      } else {
         out.reason = "Normal regime - waiting for setup";
      }
   }

   out.confidence *= (0.7 + 0.6*GetStratScore(out.strategy));

   if(out.confidence < 0.60 && out.action != "WAIT") {
      out.reason = StringFormat("conf=%.2f<0.60 (gate)", out.confidence);
      out.action = "WAIT";
   }
}

//=====================================================================
// ADAPTIVE SCORE HELPERS
//=====================================================================
double GetStratScore(const string strat)
{
   if(strat=="TREND")    return g_scoreTrend;
   if(strat=="MEAN_REV") return g_scoreMeanRev;
   if(strat=="BREAKOUT") return g_scoreBreakout;
   if(strat=="PULLBACK") return g_scorePullback;
   return 0.5;
}

void RecordOutcome(const string strat, double pnl)
{
   double val=(pnl>0)?1.0:0.0;
   if(strat=="TREND" || strat=="PULLBACK")
   { g_perfPullback[g_perfPullbackIdx%PERF_BUF]=val; g_perfPullbackIdx++; if(g_perfPullbackN<PERF_BUF)g_perfPullbackN++;
     int sz=MathMin(g_perfPullbackN,PERF_BUF); double s=0; for(int i=0;i<sz;i++)s+=g_perfPullback[i];
     g_scorePullback=0.7*g_scorePullback+0.3*(sz>0?s/sz:0.5); }
   else if(strat=="MEAN_REV")
   { g_perfMeanRev[g_perfMeanRevIdx%PERF_BUF]=val; g_perfMeanRevIdx++; if(g_perfMeanRevN<PERF_BUF)g_perfMeanRevN++;
     int sz=MathMin(g_perfMeanRevN,PERF_BUF); double s=0; for(int i=0;i<sz;i++)s+=g_perfMeanRev[i];
     g_scoreMeanRev=0.7*g_scoreMeanRev+0.3*(sz>0?s/sz:0.5); }
   else if(strat=="BREAKOUT")
   { g_perfBreakout[g_perfBreakoutIdx%PERF_BUF]=val; g_perfBreakoutIdx++; if(g_perfBreakoutN<PERF_BUF)g_perfBreakoutN++;
     int sz=MathMin(g_perfBreakoutN,PERF_BUF); double s=0; for(int i=0;i<sz;i++)s+=g_perfBreakout[i];
     g_scoreBreakout=0.7*g_scoreBreakout+0.3*(sz>0?s/sz:0.5); }
}

//=====================================================================
// STATUS DECISION
//=====================================================================
string DecideStatus(double bal, double eq, double fm)
{
   double fm_pct = (eq>0) ? fm/eq*100.0 : 0.0;
   if(InpUseMaxEquityDdPct && g_drawdownPct >= InpMaxEquityDdPct) return "HALT";
   if(g_dailyPl     >= InpDailyTargetUsd)                       return "RECOVERY_ONLY";
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
   double ask = g_sym.Ask();
   double bid = g_sym.Bid();
   double one_pt = g_point * g_pointFactor;
   if(one_pt <= 0.0) return 0.0;
   return (ask - bid) / one_pt;
}

bool SpreadAcceptable()
{
   return (CurrentSpreadPts() <= (double)InpMaxSpreadPts);
}

//=====================================================================
// BASKET CACHE & HELPERS (O(1) Ultra-Fast Lookups)
//=====================================================================
void UpdateBasketCache()
{
   g_bStats[0].count = 0; g_bStats[0].lots = 0.0; g_bStats[0].profit = 0.0;
   g_bStats[0].last_price = 0.0; g_bStats[0].last_time = 0; g_bStats[0].last_ticket = 0;
   g_bStats[0].last_lot = InpInitialLot; g_bStats[0].oldest_time = 0;
   double buyWeightSum = 0.0;

   g_bStats[1].count = 0; g_bStats[1].lots = 0.0; g_bStats[1].profit = 0.0;
   g_bStats[1].last_price = 0.0; g_bStats[1].last_time = 0; g_bStats[1].last_ticket = 0;
   g_bStats[1].last_lot = InpInitialLot; g_bStats[1].oldest_time = 0;
   double sellWeightSum = 0.0;

   int total = PositionsTotal();
   if(total == 0)
   {
      g_bStats[0].avg_price = 0.0;
      g_bStats[1].avg_price = 0.0;
      return;
   }

   for(int i = 0; i < total; i++)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;

      int d = (g_pos.PositionType() == POSITION_TYPE_BUY) ? 0 : 1;
      double vol = g_pos.Volume();
      double px  = g_pos.PriceOpen();
      datetime pt = (datetime)g_pos.Time();
      ulong ticket = g_pos.Ticket();

      g_bStats[d].count++;
      g_bStats[d].lots += vol;
      g_bStats[d].profit += g_pos.Profit() + g_pos.Swap();
      if(d == 0) buyWeightSum += px * vol;
      else       sellWeightSum += px * vol;

      if(g_bStats[d].oldest_time == 0 || pt < g_bStats[d].oldest_time)
         g_bStats[d].oldest_time = pt;

      if(pt > g_bStats[d].last_time || (pt == g_bStats[d].last_time && ticket > g_bStats[d].last_ticket))
      {
         g_bStats[d].last_time   = pt;
         g_bStats[d].last_ticket = ticket;
         g_bStats[d].last_price  = px;
         g_bStats[d].last_lot    = vol;
      }
   }

   g_bStats[0].avg_price = (g_bStats[0].lots > 0.0) ? (buyWeightSum / g_bStats[0].lots) : 0.0;
   g_bStats[1].avg_price = (g_bStats[1].lots > 0.0) ? (sellWeightSum / g_bStats[1].lots) : 0.0;
}

int      BasketCount(int direction)         { return g_bStats[direction].count; }
double   BasketAvgPrice(int direction)      { return g_bStats[direction].avg_price; }
double   BasketLastOpenPrice(int direction) { return g_bStats[direction].last_price; }
double   BasketProfit(int direction)        { return g_bStats[direction].profit; }
datetime BasketOldestTime(int direction)    { return g_bStats[direction].oldest_time; }

int BasketCalcTpPoints(int direction, int n)
{
   int minTpPts   = MathMax(g_stopsLevel + 2, InpTpPointsMin);
   if(InpRecoveryModeEnable && g_recoveryMode[direction] && InpRecoveryReducedTp > 0)
      return MathMax(minTpPts, InpRecoveryReducedTp);
   int base_pts;
   if(n <= 1)      base_pts = InpTpPointsBase;
   else if(n <= 3) base_pts = MathMax(minTpPts, InpTpPointsBase - 5*n);
   else            base_pts = minTpPts;
   if(InpTpAtrMult <= 0.0 || g_atrM1Pts <= 0.0) return base_pts;
   int atr_pts = (int)MathRound(g_atrM1Pts * InpTpAtrMult);
   atr_pts = (int)MathMax((double)minTpPts, MathMin((double)(InpTpPointsBase*2), (double)atr_pts));
   return MathMax(base_pts, atr_pts);
}

double BasketTargetPrice(int direction)
{
   int n = BasketCount(direction);
   if(n == 0) return 0.0;
   double avg    = BasketAvgPrice(direction);
   int    tp_pts = BasketCalcTpPoints(direction, n);
   double raw_target = (direction==0)
                       ? avg + tp_pts * g_point * g_pointFactor
                       : avg - tp_pts * g_point * g_pointFactor;
   if(InpRecoveryModeEnable && g_recoveryMode[direction])
   {
      double bid = g_sym.Bid();
      double ask = g_sym.Ask();
      double min_dist = (g_stopsLevel + 2) * g_point * g_pointFactor;
      if(direction==0 && raw_target < bid + min_dist)
         raw_target = NormPrice(bid + min_dist);
      if(direction==1 && raw_target > ask - min_dist)
         raw_target = NormPrice(ask - min_dist);
   }
   return NormPrice(raw_target);
}

double GetBasketFinalTarget(int direction)
{
   int n = BasketCount(direction);
   if(n == 0) return 0.0;
   double target = NormPrice(BasketTargetPrice(direction));
   if(target <= 0.0) return 0.0;
   if(n <= 1) return target;

   double avg     = BasketAvgPrice(direction);
   double bpnl    = BasketProfit(direction);
   double tp_dist = MathAbs(target - avg);

   if(bpnl > 0.0 && tp_dist > 0.0)
   {
      double cur_price = (direction==0) ? g_sym.Bid() : g_sym.Ask();
      double progress  = (direction==0) ? (cur_price - avg) : (avg - cur_price);
      if(progress > tp_dist * 0.50)
      {
         double lock_px = tp_dist * 0.60;
         double buffer_px = InpBreakevenBufferPts * g_point * g_pointFactor;
         return NormPrice((direction==0) ? avg + lock_px + buffer_px : avg - lock_px - buffer_px);
      }
   }
   return target;
}

//=====================================================================
// ADAPTIVE LOT SIZING
//=====================================================================
double NextRecoveryLot(int direction)
{
   int n = g_bStats[direction].count;
   if(n == 0) return NormLot(InpInitialLot);

   double lastVol = g_bStats[direction].last_lot;
   if(lastVol <= 0.0) lastVol = InpInitialLot;

   double mult;
   if(n < 3)      mult = InpLotMultEarly;
   else if(n < 6) mult = InpLotMultMid;
   else if(InpAntiMartingaleDeep) mult = InpDeepLotMult;
   else           mult = InpLotMultLate;

   if(g_regime == "VOLATILE") mult *= 0.8;

   double base_lot = lastVol * mult;

   double vol_scale = 1.0;
   if(g_atrM1Pts > 0.0 && InpVolNeutralAtr > 0.0)
   {
      vol_scale = InpVolNeutralAtr / g_atrM1Pts;
      vol_scale = MathMax(0.5, MathMin(1.5, vol_scale));
   }

   double nxt = base_lot * vol_scale;
   nxt = MathMin(nxt, InpRecoveryMaxLot);
   nxt = MathMax(nxt, g_volMin);

   return NormLot(nxt);
}

//=====================================================================
// CLOSE ALL / CLOSE BASKET
//=====================================================================
void CloseAllPositions(const string reason)
{
   PrintFmt(StringFormat("CloseAll: %s", reason));
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=Symbol()||g_pos.Magic()!=(ulong)InpMagic) continue;
      if(!g_trade.PositionClose(g_pos.Ticket(), InpDeviation))
         PrintFmt(StringFormat("CloseAll fail #%llu err=%d", g_pos.Ticket(), GetLastError()));
   }
   for(int d=0; d<2; d++) FinaliseBasket(d);
   UpdateBasketCache();
}

void CloseBasket(int direction, const string reason)
{
   PrintFmt(StringFormat("CloseBasket %s: %s", direction==0?"BUY":"SELL", reason));
   double basketPl = BasketProfit(direction);
   for(int attempt=0; attempt<3; attempt++)
   {
      bool any_remaining = false;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(!g_pos.SelectByIndex(i)) continue;
         if(g_pos.Symbol()!=Symbol() || g_pos.Magic()!=(ulong)InpMagic) continue;
         if((g_pos.PositionType()==POSITION_TYPE_BUY ? 0 : 1) != direction) continue;
         if(!g_trade.PositionClose(g_pos.Ticket(), InpDeviation))
         {
            PrintFmt(StringFormat("CloseBasket fail #%llu err=%d (attempt %d)", g_pos.Ticket(), GetLastError(), attempt+1));
            any_remaining = true;
         }
      }
      if(!any_remaining) break;
      Sleep(50);
   }
   FinaliseBasket(direction);
   UpdateBasketCache();
   int cdMult = (basketPl >= 0.0) ? 1 : 6;
   g_cooldownUntil = TimeCurrent() + InpCooldownSec * cdMult;
   g_lastCloseTime = TimeCurrent();
}

//=====================================================================
// UpdateMaxBasketLoss
//=====================================================================
void UpdateMaxBasketLoss(int direction)
{
   if(BasketCount(direction) == 0)
   {
      if(g_maxBasketLoss[direction] != 0.0) g_maxBasketLoss[direction] = 0.0;
      return;
   }
   double pl = BasketProfit(direction);
   if(pl < g_maxBasketLoss[direction]) g_maxBasketLoss[direction] = pl;
}

//=====================================================================
// ManageBasketRisk
//=====================================================================
void ManageBasketRisk(int direction)
{
   int n = BasketCount(direction);
   if(n == 0) return;

   double basket_pl = BasketProfit(direction);

   // [BASKET TAKE-PROFIT EXIT (ปิดรวบ) FOR n >= 2]
   if(n >= 2)
   {
      double final_target = GetBasketFinalTarget(direction);
      if(final_target > 0.0)
      {
         double cur_px = (direction==0) ? g_sym.Bid() : g_sym.Ask();
         bool reached  = (direction==0) ? (cur_px >= final_target) : (cur_px <= final_target);
         if(reached && basket_pl >= 0.0)
         {
            PrintFmt(StringFormat("BASKET TP REACHED %s: n=%d Px=%.*f Target=%.*f BasketPL=$%.2f — Closing all layers (ปิดรวบ)",
                     direction==0?"BUY":"SELL", n, g_digits, cur_px, g_digits, final_target, basket_pl));
            CloseBasket(direction, StringFormat("Basket TP reached pl=%.2f", basket_pl));
            return;
         }
      }
   }

   if(InpUseBasketStopLoss && basket_pl <= -InpMaxBasketLossUsd)
   {
      PrintFmt(StringFormat("BASKET STOP-LOSS %s: pl=$%.2f <= -$%.2f — closing",
               direction==0?"BUY":"SELL", basket_pl, InpMaxBasketLossUsd));
      CloseBasket(direction, StringFormat("Basket stop-loss pl=%.2f", basket_pl));
      return;
   }

   datetime oldest = BasketOldestTime(direction);
   if(oldest > 0)
   {
      int ageHours = (int)((TimeCurrent() - oldest) / 3600);
      if(ageHours >= InpBasketMaxAgeHours)
      {
         PrintFmt(StringFormat("BASKET TIME-STOP %s: age=%dh >= %dh — closing",
                  direction==0?"BUY":"SELL", ageHours, InpBasketMaxAgeHours));
         CloseBasket(direction, StringFormat("Basket time-stop age=%dh", ageHours));
         return;
      }
   }

   if(InpBreakevenExit)
      ManageBreakevenExit(direction);
}

void ManageBreakevenExit(int direction)
{
   int n = BasketCount(direction);
   if(n < 2) return;

   if(g_maxBasketLoss[direction] > -InpBreakevenTriggerUsd * 3.0) return;

   double pl = BasketProfit(direction);
   if(pl >= 0.0)
   {
      PrintFmt(StringFormat("BREAKEVEN EXIT %s: pl=$%.2f (was $%.2f) — closing",
               direction==0?"BUY":"SELL", pl, g_maxBasketLoss[direction]));
      CloseBasket(direction, StringFormat("BE exit pl=%.2f maxloss=%.2f", pl, g_maxBasketLoss[direction]));
   }
}

//=====================================================================
// TRAILING STOP BASKET
//=====================================================================
void ManageTrailing(int direction)
{
   int    n      = BasketCount(direction);
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
                     g_peakProfit[direction], g_peakProfit[direction]-profit));
      }
   }
}

//=====================================================================
// PARTIAL CLOSE
//=====================================================================
void ManagePartialClose(int direction)
{
   int maxStage = InpStagedPartialClose ? InpPartialCloseLevels : 1;
   if(g_partialStage[direction] >= maxStage) return;

   int    n      = BasketCount(direction);
   double profit = BasketProfit(direction);
   double triggerUsd = InpPartialCloseAtUsd * (g_partialStage[direction] + 1);
   
   if(n <= 1 || profit < triggerUsd) return;

   ENUM_POSITION_TYPE want = (direction==0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   SPosEntry entries[];
   int cnt = 0;
   for(int i=0; i<PositionsTotal(); i++)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=Symbol()||g_pos.Magic()!=(ulong)InpMagic) continue;
      if(g_pos.PositionType()!=want) continue;
      double p = g_pos.Profit() + g_pos.Swap();
      if(p > 0.0)
      {
         ArrayResize(entries, cnt+1);
         entries[cnt].ticket = g_pos.Ticket();
         entries[cnt].profit = p;
         entries[cnt].time   = (datetime)g_pos.Time(); 
         cnt++;
      }
   }
   if(cnt == 0) return;

   for(int i=0; i<cnt-1; i++)
      for(int j=0; j<cnt-1-i; j++)
         if(entries[j].time < entries[j+1].time) 
         { SPosEntry tmp=entries[j]; entries[j]=entries[j+1]; entries[j+1]=tmp; }

   int toClose = (int)MathMax(1.0, MathRound(cnt * InpPartialClosePct / 100.0));
   toClose = MathMin(toClose, cnt);
   int closed = 0;
   for(int i=0; i<toClose; i++)
   {
      if(g_trade.PositionClose(entries[i].ticket, InpDeviation)) closed++;
      else PrintFmt(StringFormat("PC fail #%llu err=%d", entries[i].ticket, GetLastError()));
   }

   if(closed >= toClose)
   {
      g_partialStage[direction]          += 1;
      g_pendingPartialClose[direction]    = false;
      g_peakProfit[direction]             = 0.0;
      g_trailingActive[direction]         = false;
      UpdateBasketCache();
      PrintFmt(StringFormat("PartialClose %s stage %d/%d done: %d/%d @ basket $%.2f",
               direction==0?"BUY":"SELL", g_partialStage[direction], maxStage, closed, cnt, profit));
   }
   else if(closed > 0)
   {
      g_pendingPartialClose[direction] = true;
      PrintFmt(StringFormat("PartialClose %s incomplete %d/%d — retry",
               direction==0?"BUY":"SELL", closed, toClose));
   }
}

void RetryPartialClose(int direction)
{
   if(!g_pendingPartialClose[direction]) return;
   g_pendingPartialClose[direction] = false;
   ManagePartialClose(direction);
}

//+------------------------------------------------------------------+
//| Dynamic Swing-Grid Calculation Helpers                           |
//+------------------------------------------------------------------+
double GetYesterdaySwingPts()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(Symbol(), PERIOD_D1, 1, 1, rates) > 0)
   {
      double swingPrice = rates[0].high - rates[0].low;
      if(g_point > 0.0 && g_pointFactor > 0.0 && swingPrice > 0.0)
         return swingPrice / (g_point * g_pointFactor);
   }
   
   double yh = iHigh(Symbol(), PERIOD_D1, 1);
   double yl = iLow(Symbol(), PERIOD_D1, 1);
   if(yh > yl && yl > 0.0)
   {
      if(g_point > 0.0 && g_pointFactor > 0.0)
         return (yh - yl) / (g_point * g_pointFactor);
   }
   return 0.0;
}

double GetGridAtrPts()
{
   if(g_atrGridHandle != INVALID_HANDLE)
   {
      double atr[1];
      if(CopyBuffer(g_atrGridHandle, 0, 0, 1, atr) > 0 && atr[0] > 0.0)
      {
         if(g_point > 0.0 && g_pointFactor > 0.0)
            return atr[0] / (g_point * g_pointFactor);
      }
   }
   
   int n_bars = InpGridAtrPeriod + 30;
   double h_arr[], l_arr[], c_arr[];
   ArraySetAsSeries(h_arr, false);
   ArraySetAsSeries(l_arr, false);
   ArraySetAsSeries(c_arr, false);
   if(CopyHigh (Symbol(), InpGridAtrTf, 0, n_bars, h_arr) >= n_bars &&
      CopyLow  (Symbol(), InpGridAtrTf, 0, n_bars, l_arr) >= n_bars &&
      CopyClose(Symbol(), InpGridAtrTf, 0, n_bars, c_arr) >= n_bars)
   {
      double atr_val = CalcATR(h_arr, l_arr, c_arr, n_bars, InpGridAtrPeriod);
      if(g_point > 0.0 && g_pointFactor > 0.0)
         return atr_val / (g_point * g_pointFactor);
   }
   
   return (g_atrM1Pts > 0.0) ? g_atrM1Pts : (double)InpRecoveryMinGap;
}

//=====================================================================
// ADAPTIVE MULTI-LAYER RECOVERY
//=====================================================================
void ManageRecovery(TFView &views[], bool &viewsOk[])
{
   if(g_status == "HALT") return;
   if(!SpreadAcceptable()) return;

   for(int direction=0; direction<=1; direction++)
   {
      int n = BasketCount(direction);
      if(n == 0 || n >= InpRecoveryMaxLayers) continue;
      if(n >= InpMaxRecoveryAttempts) continue;

      if(InpRecoveryModeEnable && !g_recoveryMode[direction] && n >= InpRecoveryModeAtLayer)
      {
         g_recoveryMode[direction] = true;
         PrintFmt(StringFormat("RecoveryMode ON %s at layer %d (TP→%d pts)",
                  direction==0?"BUY":"SELL", n, InpRecoveryReducedTp));
      }

      double wait_atr_part = (g_atrM1Pts > 0) ? g_atrM1Pts / 10.0 * n : 5.0 * n;
      int    min_wait      = (int)(30.0 + wait_atr_part);
      datetime lastRecDir  = (direction==0) ? g_lastRecBuy : g_lastRecSell;
      if(TimeCurrent() - lastRecDir < min_wait) continue;

      double lastPx = BasketLastOpenPrice(direction);
      if(lastPx == 0.0) continue;
      double curPrice = (direction==0) ? g_sym.Bid() : g_sym.Ask();
      double adv_px = (direction==0) ? (lastPx - curPrice) : (curPrice - lastPx);
      double adv_pts = (g_point>0 && g_pointFactor>0) ? adv_px / (g_point*g_pointFactor) : 0.0;

      // Dynamic Swing-Grid Recovery: (Yesterday D1 Full Swing / InpSwingDivisor) + ATR(InpGridAtrTf) * InpGridAtrMult
      double swingPts  = GetYesterdaySwingPts();
      double swingPart = (InpSwingDivisor > 0.0) ? (swingPts / InpSwingDivisor) : 0.0;
      double atrPart   = GetGridAtrPts() * InpGridAtrMult;
      double base_gap  = swingPart + atrPart;
      double min_gap   = MathMax((double)InpRecoveryMinGap, base_gap);
      min_gap += min_gap * 0.10 * n;

      if(adv_pts < min_gap) continue;

      if(viewsOk[0]) {
         TFView m1=views[0];
         if(direction == 0 && m1.macd_hist < m1.macd_hist_prev && m1.rsi_val < 25) continue;
         if(direction == 1 && m1.macd_hist > m1.macd_hist_prev && m1.rsi_val > 75) continue;
      }

      if(viewsOk[3] && viewsOk[4]) {
         TFView h1=views[3], h4=views[4];
         if(direction==0 && h1.trend<0 && h4.trend<0 && h1.adx_val>25) continue;
         if(direction==1 && h1.trend>0 && h4.trend>0 && h1.adx_val>25) continue;
      }

      double eq_r = AccountInfoDouble(ACCOUNT_EQUITY);
      double fm   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(InpUseMinFreeMarginPct && eq_r > 0 && fm/eq_r*100.0 < InpMinFreeMarginPct) continue;

      double lot   = NextRecoveryLot(direction);
      string cmt   = StringFormat("ZXREC_%s_%d", direction==0?"BUY":"SELL", n+1);

      // In Basket Recovery (n >= 2), orders are opened with TP=0.0 so the broker cannot prematurely close
      // a single layer alone. The entire basket is closed simultaneously (ปิดรวบ) by the EA at final_target.
      bool ok = false;
      if(direction==0) ok = g_trade.Buy (lot, Symbol(), 0.0, 0.0, 0.0, cmt);
      else             ok = g_trade.Sell(lot, Symbol(), 0.0, 0.0, 0.0, cmt);

      if(ok) {
         if(direction==0) g_lastRecBuy=TimeCurrent(); else g_lastRecSell=TimeCurrent();
         UpdateBasketCache();
         PrintFmt(StringFormat("ADAPTIVE REC %s lot=%.2f layer=%d gap=%.1f/%.1f (S/R adj) [Regime:%s]",
                  direction==0?"BUY":"SELL", lot, n+1, adv_pts, min_gap, g_regime));
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
   for(int direction=0; direction<=1; direction++)
   {
      int n = g_bStats[direction].count;
      if(n == 0) continue;

      double final_target = GetBasketFinalTarget(direction);
      if(final_target <= 0.0) continue;

      if(n >= 2)
      {
         // 1. Check if price already reached target with positive profit (instant basket close)
         double cur_px = (direction==0) ? g_sym.Bid() : g_sym.Ask();
         double bpnl   = BasketProfit(direction);
         bool reached  = (direction==0) ? (cur_px >= final_target) : (cur_px <= final_target);
         if(reached && bpnl >= 0.0)
         {
            PrintFmt(StringFormat("BASKET TP REACHED %s: n=%d Px=%.*f Target=%.*f Profit=$%.2f — Closing all layers (ปิดรวบ)",
                     direction==0?"BUY":"SELL", n, g_digits, cur_px, g_digits, final_target, bpnl));
            CloseBasket(direction, StringFormat("Basket TP reached pl=%.2f", bpnl));
            continue;
         }

         // 2. Clear broker-side TP on all individual positions so the broker cannot close orders separately!
         for(int i=0; i<PositionsTotal(); i++)
         {
            if(!g_pos.SelectByIndex(i)) continue;
            if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;
            if((g_pos.PositionType() == POSITION_TYPE_BUY ? 0 : 1) != direction) continue;
            if(g_pos.TakeProfit() > 0.0)
            {
               g_trade.PositionModify(g_pos.Ticket(), g_pos.StopLoss(), 0.0);
            }
         }
      }
      else // Single position (n == 1): Maintain broker-side TP on the individual position
      {
         for(int i=0; i<PositionsTotal(); i++)
         {
            if(!g_pos.SelectByIndex(i)) continue;
            if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;
            if((g_pos.PositionType() == POSITION_TYPE_BUY ? 0 : 1) != direction) continue;
            double cur_tp = g_pos.TakeProfit();
            datetime posTime = (datetime)g_pos.Time();
            bool justOpened = (TimeCurrent() - posTime < 3);
            bool should_update = (MathAbs(final_target - cur_tp) > 2.0 * one_pt) || (cur_tp == 0.0 && final_target > one_pt);
            if(should_update && !justOpened)
               g_trade.PositionModify(g_pos.Ticket(), g_pos.StopLoss(), final_target);
         }
      }
   }
}

//=====================================================================
// OPEN NEW TRADE
//=====================================================================
void TryOpenNew(const Signal &sig)
{
   int direction = (sig.action=="BUY") ? 0 : 1;

   if(sig.confidence < 0.60) return;
   if(BasketCount(0) > 0 || BasketCount(1) > 0) return;

   // [v17.00] Record any pending basket trades before opening new
   for(int d=0; d<2; d++) TryRecordBasketTrade(d);

   if(InpWaitNextBarAfterClose && g_lastCloseTime > 0)
   {
      datetime currentBarTime = (datetime)SeriesInfoInteger(Symbol(), PERIOD_M1, SERIES_LASTBAR_DATE);
      if(currentBarTime == 0) currentBarTime = TimeCurrent();
      if(currentBarTime <= g_lastCloseTime) {
         if(InpPrintDebug) PrintFmt("Skip new: waiting for next M1 bar after last close.");
         return;
      }
   }

   if(!SpreadAcceptable())
   {
      if(InpPrintDebug) PrintFmt(StringFormat("Skip new: spread=%.1f > %d", CurrentSpreadPts(), InpMaxSpreadPts));
      return;
   }

   datetime lastTs = (direction==0) ? g_lastOpenBuy : g_lastOpenSell;
   if(TimeCurrent() - lastTs < 30) return;

   double entry, tp_px;
   int tp_pts = (int)MathMax((double)sig.tp_points, (double)BasketCalcTpPoints(direction, 1));
   if(direction==0)
   { entry=SymbolInfoDouble(Symbol(),SYMBOL_ASK); tp_px=NormPrice(entry+tp_pts*g_point*g_pointFactor); }
   else
   { entry=SymbolInfoDouble(Symbol(),SYMBOL_BID); tp_px=NormPrice(entry-tp_pts*g_point*g_pointFactor); }

   string cmt      = StringFormat("%s_%s_%d", InpTradeCommentPrefix, sig.strategy, (int)(sig.confidence*100));
   double open_lot = NormLot(InpInitialLot);
   bool ok;
   if(direction==0) ok=g_trade.Buy (open_lot, Symbol(), 0.0, 0.0, tp_px, cmt);
   else             ok=g_trade.Sell(open_lot, Symbol(), 0.0, 0.0, tp_px, cmt);

   if(ok)
   {
      if(direction==0) g_lastOpenBuy=TimeCurrent(); else g_lastOpenSell=TimeCurrent();
      UpdateBasketCache();
      PrintFmt(StringFormat("NEW %s %s lot=%.2f [Regime:%s] %s",
               sig.action, sig.strategy, open_lot, g_regime, sig.reason));
   }
}

//=====================================================================
// [v17.00] BASKET-LEVEL TRADE RECORDING
// Instead of counting each position close individually, we accumulate
// profits by direction and record as a single basket trade when the
// basket is fully closed. This gives Win Rate = 100% for profitable baskets.
//=====================================================================

bool HasPendingForDirection(int direction)
{
   for(int i=0; i<g_pendingHistCount; i++)
   {
      if(g_pendingHistIds[i] != 0 && g_pendingHistDirs[i] == direction) return true;
   }
   return false;
}

void TryRecordBasketTrade(int direction)
{
   if(g_basketAccumCount[direction] == 0) return;

   int currentCount = BasketCount(direction);
   bool hasPending  = HasPendingForDirection(direction);

   // If basket still open and no new basket forced, wait
   if(currentCount > 0)
   {
      // New basket opened before old one fully processed — force record
      // This handles the edge case where history was delayed
   }
   else if(hasPending)
   {
      // Basket empty but pending history exists — wait (with timeout)
      if(g_basketAccumTime[direction] > 0 && 
         TimeCurrent() - g_basketAccumTime[direction] < 60)
         return; // Wait up to 60 seconds for pending history
      // Force record after timeout
   }

   // Record the basket trade
   double profit = g_basketAccumProfit[direction];
   string strat = g_basketAccumStrategy[direction];
   if(strat == "") strat = "TREND";

   // Record strategy outcome (basket-level, not per-position)
   RecordOutcome(strat, profit);

   // Cooldown only for losing baskets (not per-position)
   if(profit < 0)
   {
      datetime new_cd = TimeCurrent() + InpCooldownSec * 6;
      if(new_cd > g_cooldownUntil) g_cooldownUntil = new_cd;
   }

   // Update gross profit/loss for profit factor
   if(profit > 0) g_grossProfit += profit;
   else if(profit < 0) g_grossLoss += (-profit);

   // Update statistics
   g_totalTrades++;
   g_totalProfit += profit;
   if(profit > 0) g_winningTrades++;

   double wr = (g_totalTrades > 0) ? (double)g_winningTrades / g_totalTrades * 100.0 : 0.0;
   PrintFmt(StringFormat("Basket %s CLOSED: %d positions, net=$%.2f [T:%d WR:%.1f%% Net:$%.2f GP:$%.2f GL:$%.2f]",
            direction==0?"BUY":"SELL", g_basketAccumCount[direction], profit,
            g_totalTrades, wr, g_totalProfit, g_grossProfit, g_grossLoss));

   g_lastCloseTime = TimeCurrent();

   // Reset accumulators
   g_basketAccumProfit[direction]     = 0.0;
   g_basketAccumCount[direction]      = 0;
   g_basketAccumStrategy[direction]   = "";
   g_basketAccumHasRecovery[direction]= false;
   g_basketAccumTime[direction]       = 0;
}

//=====================================================================
// RECORD CLOSES — [v17.00] Modified for basket-level tracking
//=====================================================================
void RecordCloses()
{
   int curTotal = PositionsTotal();
   if(curTotal == 0 && g_trackedCount == 0)
   {
      if(g_basketAccumCount[0] > 0 || g_basketAccumCount[1] > 0)
      {
         for(int d=0; d<2; d++) TryRecordBasketTrade(d);
      }
      return;
   }

   int cur_count=0;
   ulong cur_tickets[MAX_TRACKED];
   for(int i=0;i<curTotal;i++)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=Symbol()||g_pos.Magic()!=(ulong)InpMagic) continue;
      if(cur_count<MAX_TRACKED) cur_tickets[cur_count++]=g_pos.Ticket();
   }

   for(int i=0;i<g_trackedCount;i++)
   {
      bool found=false;
      for(int j=0;j<cur_count;j++)
         if(cur_tickets[j]==g_trackedTickets[i]){found=true;break;}
      if(!found)
      {
         ulong pos_id = g_trackedPosIds[i];
         double profit = g_trackedProfits[i];
         int dir = g_trackedDir[i];

         if(pos_id > 0 && HistorySelectByPosition(pos_id))
         {
            int dealCount = HistoryDealsTotal();
            if(dealCount == 0)
            {
               if(g_pendingHistCount < MAX_TRACKED)
               {
                  g_pendingHistIds    [g_pendingHistCount] = pos_id;
                  g_pendingHistProfits[g_pendingHistCount] = g_trackedProfits[i];
                  g_pendingHistCmts   [g_pendingHistCount] = g_trackedComments[i];
                  g_pendingHistVols   [g_pendingHistCount] = g_trackedVols[i];
                  g_pendingHistDirs   [g_pendingHistCount] = dir;
                  g_pendingHistCount++;
               }
               continue;
            }
            double dp=0.0;
            for(int dj=0;dj<dealCount;dj++)
            {
               ulong dt=HistoryDealGetTicket(dj);
               if(dt==0) continue;
               if((ulong)HistoryDealGetInteger(dt,DEAL_POSITION_ID)!=pos_id) continue;
               long entry_type = HistoryDealGetInteger(dt, DEAL_ENTRY);
               if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_INOUT) continue;
               dp += HistoryDealGetDouble(dt,DEAL_PROFIT)
                   + HistoryDealGetDouble(dt,DEAL_SWAP)
                   + HistoryDealGetDouble(dt,DEAL_COMMISSION);
            }
            profit = dp;
         }

         // [v17.00] Accumulate by direction instead of recording individually
         if(g_basketAccumCount[dir] == 0)
            g_basketAccumTime[dir] = TimeCurrent();
         g_basketAccumProfit[dir] += profit;
         g_basketAccumCount[dir]++;

         // Track strategy from initial (non-recovery) position
         string cm = g_trackedComments[i];
         if(StringFind(cm, "ZXREC_") >= 0 || StringFind(cm, "AREC_") >= 0)
            g_basketAccumHasRecovery[dir] = true;
         else if(g_basketAccumStrategy[dir] == "")
         {
            string strat = "TREND";
            string keys[4] = {"MEAN_REV", "BREAKOUT", "PULLBACK", "TREND"};
            for(int k=0;k<4;k++) if(StringFind(cm,keys[k])>=0){strat=keys[k];break;}
            g_basketAccumStrategy[dir] = strat;
         }

         g_lastCloseTime = TimeCurrent();

         if(InpPrintDebug)
            PrintFmt(StringFormat("Close detected #%llu %s vol=%.2f profit=$%.2f → accum[%s]=$%.2f (%d)",
               g_trackedTickets[i], dir==0?"BUY":"SELL", g_trackedVols[i], profit,
               dir==0?"BUY":"SELL", g_basketAccumProfit[dir], g_basketAccumCount[dir]));
      }
   }

   // [v17.00] Try to record completed basket trades
   for(int d=0; d<2; d++) TryRecordBasketTrade(d);

   // Finalise empty baskets
   for(int d=0; d<2; d++)
   {
      if(BasketCount(d)==0 && (g_trailingActive[d] || g_partialStage[d]>0 || g_recoveryMode[d]))
      {
         FinaliseBasket(d);
      }
   }

   // Rebuild tracked positions
   g_trackedCount=0;
   if(curTotal == 0) return;
   for(int i=0;i<curTotal&&g_trackedCount<MAX_TRACKED;i++)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol()!=Symbol()||g_pos.Magic()!=(ulong)InpMagic) continue;
      g_trackedTickets [g_trackedCount] = g_pos.Ticket();
      g_trackedPosIds  [g_trackedCount] = (ulong)g_pos.Identifier();
      g_trackedProfits [g_trackedCount] = g_pos.Profit()+g_pos.Swap();
      g_trackedComments[g_trackedCount] = g_pos.Comment();
      g_trackedVols    [g_trackedCount] = g_pos.Volume();
      g_trackedOpen    [g_trackedCount] = g_pos.PriceOpen();
      g_trackedDir     [g_trackedCount] = (g_pos.PositionType()==POSITION_TYPE_BUY)?0:1;
      g_trackedCount++;
   }
}

//=====================================================================
// [v17.00] PROCESS PENDING HISTORY — Modified for basket-level tracking
//=====================================================================
void ProcessPendingHistory()
{
   if(g_pendingHistCount == 0)
   {
      // Still try to record basket trades (in case accumulators have data)
      for(int d=0; d<2; d++) TryRecordBasketTrade(d);
      return;
   }

   int remaining = 0;
   for(int i=0; i<g_pendingHistCount; i++)
   {
      ulong pos_id = g_pendingHistIds[i];
      if(pos_id == 0) continue;

      if(!HistorySelectByPosition(pos_id))
      {
         if(remaining != i)
         {
            g_pendingHistIds    [remaining] = g_pendingHistIds    [i];
            g_pendingHistProfits[remaining] = g_pendingHistProfits[i];
            g_pendingHistCmts   [remaining] = g_pendingHistCmts   [i];
            g_pendingHistVols   [remaining] = g_pendingHistVols   [i];
            g_pendingHistDirs   [remaining] = g_pendingHistDirs   [i];
         }
         remaining++;
         continue;
      }

      int dealCount = HistoryDealsTotal();
      if(dealCount == 0)
      {
         if(remaining != i)
         {
            g_pendingHistIds    [remaining] = g_pendingHistIds    [i];
            g_pendingHistProfits[remaining] = g_pendingHistProfits[i];
            g_pendingHistCmts   [remaining] = g_pendingHistCmts   [i];
            g_pendingHistVols   [remaining] = g_pendingHistVols   [i];
            g_pendingHistDirs   [remaining] = g_pendingHistDirs   [i];
         }
         remaining++;
         continue;
      }

      double dp=0.0;
      for(int dj=0;dj<dealCount;dj++)
      {
         ulong dt=HistoryDealGetTicket(dj);
         if(dt==0) continue;
         if((ulong)HistoryDealGetInteger(dt,DEAL_POSITION_ID)!=pos_id) continue;
         long entry_type = HistoryDealGetInteger(dt, DEAL_ENTRY);
         if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_INOUT) continue;
         dp += HistoryDealGetDouble(dt,DEAL_PROFIT)
             + HistoryDealGetDouble(dt,DEAL_SWAP)
             + HistoryDealGetDouble(dt,DEAL_COMMISSION);
      }

      // [v17.00] Accumulate by direction
      int dir = g_pendingHistDirs[i];
      if(g_basketAccumCount[dir] == 0)
         g_basketAccumTime[dir] = TimeCurrent();
      g_basketAccumProfit[dir] += dp;
      g_basketAccumCount[dir]++;

      string cm = g_pendingHistCmts[i];
      if(StringFind(cm, "ZXREC_") >= 0 || StringFind(cm, "AREC_") >= 0)
         g_basketAccumHasRecovery[dir] = true;
      else if(g_basketAccumStrategy[dir] == "")
      {
         string strat = "TREND";
         string keys[4] = {"MEAN_REV", "BREAKOUT", "PULLBACK", "TREND"};
         for(int k=0;k<4;k++) if(StringFind(cm,keys[k])>=0){strat=keys[k];break;}
         g_basketAccumStrategy[dir] = strat;
      }

      g_lastCloseTime = TimeCurrent();

      if(InpPrintDebug)
         PrintFmt(StringFormat("Pending resolved #%llu %s profit=$%.2f → accum[%s]=$%.2f (%d)",
            pos_id, dir==0?"BUY":"SELL", dp, dir==0?"BUY":"SELL",
            g_basketAccumProfit[dir], g_basketAccumCount[dir]));
   }

   g_pendingHistCount = remaining;
   if(g_pendingHistCount > 50) g_pendingHistCount = 0;

   // [v17.00] Try to record completed basket trades
   for(int d=0; d<2; d++) TryRecordBasketTrade(d);
}

//=====================================================================
// DAILY PL / DD / ROLLOVER
//=====================================================================
void ResetDay()
{
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartTime   = TimeCurrent();
   g_dailyPl        = 0.0;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   PrintFmt(StringFormat("Day reset. Eq=%.2f  %04d-%02d-%02d", g_dayStartEquity,dt.year,dt.mon,dt.day));
}

void CheckDayRollover()
{
   MqlDateTime n,s;
   TimeToStruct(TimeCurrent(),n);
   TimeToStruct(g_dayStartTime,s);
   if(n.day!=s.day || n.mon!=s.mon || n.year!=s.year) ResetDay();
}

void UpdateDailyPL(double eq) { g_dailyPl = eq - g_dayStartEquity; }

void UpdateDD(double eq)
{
   if(eq > g_peakEquity) g_peakEquity = eq;
   if(g_peakEquity > 0.0) g_drawdownPct = MathMax(0.0, (g_peakEquity-eq)/g_peakEquity*100.0);
}

//=====================================================================
// UTILITIES
//=====================================================================
ENUM_ORDER_TYPE_FILLING PickFilling()
{
   uint fill=(uint)SymbolInfoInteger(Symbol(),SYMBOL_FILLING_MODE);
   if((fill&(uint)SYMBOL_FILLING_FOK)!=0) return ORDER_FILLING_FOK;
   if((fill&(uint)SYMBOL_FILLING_IOC)!=0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

double NormLot(double lot)
{
   lot = MathMax(g_volMin, MathMin(g_volMax, lot));
   lot = NormalizeDouble(MathRound(lot / g_volStep) * g_volStep, 2);
   return MathMax(g_volMin, lot);
}

double NormPrice(double p) { return NormalizeDouble(p, g_digits); }
void   PrintFmt(const string msg) { Print(msg); }

//=====================================================================
// DASHBOARD THROTTLING (Fast Backtest Guard)
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

#define DASH_COL_W   280
#define DASH_GAP       8
#define DASH_W        (DASH_COL_W*2+DASH_GAP)
#define DASH_FONT     "Consolas"
#define DASH_FONT_BOLD "Arial Bold"
#define ROW_H    14
#define SEC_GAP   4
#define BAR_H     6

color CLR_TITLE   = C'52,152,219';
color CLR_WHITE   = C'220,230,242';
color CLR_LABEL   = C'120,140,170';
color CLR_GREEN   = C'39,174,96';
color CLR_RED     = C'231,76,60';
color CLR_YELLOW  = C'241,196,15';
color CLR_ORANGE  = C'230,126,34';
color CLR_CYAN    = C'26,188,156';
color CLR_PURPLE  = C'155,89,182';
color CLR_DIVIDER = C'40,55,75';
color CLR_BARGB   = C'30,40,55';

void ObjDel(const string name) { ObjectDelete(0,name); }
void ObjRect(const string name,int x,int y,int w,int h,color bg,color border,int bw=1)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);      ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border); ObjectSetInteger(0,name,OBJPROP_WIDTH,bw);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
}
void ObjLabel(const string name,int x,int y,const string txt,color clr,int fs=9,const string font=DASH_FONT,int anchor=0)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetString (0,name,OBJPROP_TEXT,txt);     ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);  ObjectSetString (0,name,OBJPROP_FONT,font);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,anchor);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,1);
}
void ObjDivider(const string name,int x,int y,int w){ObjRect(name,x,y,w,1,CLR_DIVIDER,CLR_DIVIDER,0);}
void ObjRow(const string lname,const string rname,int x,int y,int panelW,
            const string lbl,const string val,color lclr=0,color vclr=0)
{
   if(lclr==0)lclr=CLR_LABEL; if(vclr==0)vclr=CLR_WHITE;
   ObjLabel(lname,x+10,y,lbl,lclr,9,DASH_FONT);
   ObjLabel(rname,x+panelW-12,y,val,vclr,9,DASH_FONT,ANCHOR_RIGHT);
}
void ObjBar(const string name,int x,int y,int maxW,double pct,color clr)
{
   int bw=(int)MathMax(2,MathRound(maxW*MathMax(0.0,MathMin(1.0,pct))));
   ObjRect(name+"_bg",x,y,maxW,BAR_H,CLR_BARGB,CLR_BARGB,0);
   ObjRect(name+"_fg",x,y,bw,  BAR_H,clr,clr,0);
}
void DashDelete() { ObjectsDeleteAll(0,DASH_PFX); }
void DashInit()
{
   if(!InpShowDashboard) return;
   DashDelete();
   int x=InpDashX, y=InpDashY;
   ObjRect(DASH_PFX+"bg",  x,y,DASH_W,30, g_dashBg, g_dashBorder, 2);
   ObjRect(DASH_PFX+"hdr", x,y,DASH_W,26, C'30,45,72', g_dashBorder, 0);
   ObjLabel(DASH_PFX+"title", x+12,y+5,  "ZERITH XAU SWING-GRID v1.00",   CLR_TITLE, 10, DASH_FONT_BOLD);
   ObjLabel(DASH_PFX+"sub",   x+DASH_W-12,y+6, Symbol()+"  MT5", CLR_LABEL, 8, DASH_FONT, ANCHOR_RIGHT);
   ChartRedraw();
}

void DashUpdate(double bal, double eq, double fm, TFView &views[], bool &viewsOk[])
{
   if(!InpShowDashboard) return;
   if(InpDashAutoColor) RefreshDashColors();
   int XL=InpDashX, XR=InpDashX+DASH_COL_W+DASH_GAP;
   int CW=DASH_COL_W;
   int cyL=InpDashY+32, cyR=InpDashY+32;

   double fm_pct=(eq>0)?fm/eq*100.0:0.0;
   int cd_left=(int)MathMax(0.0,(double)(g_cooldownUntil-TimeCurrent()));
   double spread_pts = CurrentSpreadPts();

   ObjLabel(DASH_PFX+"s1hdr",XL+8,cyL,"▌ ACCOUNT",CLR_TITLE,9,DASH_FONT_BOLD); cyL+=ROW_H+2;
   color pl_clr=(g_dailyPl>=0)?CLR_GREEN:CLR_RED;
   ObjRow(DASH_PFX+"r_bal_l",DASH_PFX+"r_bal_v",XL,cyL,CW,"Balance",   StringFormat("$%.2f",bal),   CLR_LABEL,CLR_WHITE); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_eq_l", DASH_PFX+"r_eq_v", XL,cyL,CW,"Equity",    StringFormat("$%.2f",eq),    CLR_LABEL,CLR_WHITE); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_fm_l", DASH_PFX+"r_fm_v", XL,cyL,CW,"FreeMgn",   StringFormat("%.1f%%",fm_pct),CLR_LABEL,fm_pct<InpMinFreeMarginPct?CLR_RED:CLR_GREEN); cyL+=ROW_H-1;
   ObjBar(DASH_PFX+"fmbar",XL+8,cyL,CW-16,fm_pct/100.0,fm_pct<InpMinFreeMarginPct?CLR_RED:CLR_CYAN); cyL+=BAR_H+2;
   ObjRow(DASH_PFX+"r_dpl_l",DASH_PFX+"r_dpl_v",XL,cyL,CW,"Day P&L",   StringFormat("%s$%.2f",g_dailyPl>=0?"+":"",g_dailyPl),CLR_LABEL,pl_clr); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_sp_l", DASH_PFX+"r_sp_v", XL,cyL,CW,"Spread",    StringFormat("%.1f pts",spread_pts),CLR_LABEL,spread_pts>InpMaxSpreadPts?CLR_RED:CLR_GREEN); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_dd_l", DASH_PFX+"r_dd_v", XL,cyL,CW,"DrawDn",    StringFormat("%.2f%%",g_drawdownPct),CLR_LABEL,g_drawdownPct>10?CLR_RED:CLR_YELLOW); cyL+=ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div1",XL+6,cyL,CW-12); cyL+=3;
   ObjLabel(DASH_PFX+"s2hdr",XL+8,cyL,"▌ DECISION MATRIX",CLR_TITLE,9,DASH_FONT_BOLD); cyL+=ROW_H+2;
   color reg_clr = CLR_CYAN;
   if(g_regime=="TREND_STRONG") reg_clr = CLR_GREEN;
   else if(g_regime=="VOLATILE") reg_clr = CLR_RED;
   else if(g_regime=="CHOPPY") reg_clr = CLR_ORANGE;
   ObjRow(DASH_PFX+"r_reg_l",DASH_PFX+"r_reg_v",XL,cyL,CW,"Regime",    g_regime, CLR_LABEL, reg_clr); cyL+=ROW_H;
   color sig_clr=(g_lastSigAction=="BUY")?CLR_GREEN:(g_lastSigAction=="SELL"?CLR_RED:CLR_LABEL);
   ObjRow(DASH_PFX+"r_sig_l",DASH_PFX+"r_sig_v",XL,cyL,CW,"Action",    g_lastSigAction,    CLR_LABEL,sig_clr); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_str_l",DASH_PFX+"r_str_v",XL,cyL,CW,"Strategy",  g_lastSigStrategy,  CLR_LABEL,CLR_CYAN); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_con_l",DASH_PFX+"r_con_v",XL,cyL,CW,"Conf",      StringFormat("%.0f%%",g_lastSigConfidence*100),CLR_LABEL,CLR_WHITE); cyL+=ROW_H-1;
   ObjBar(DASH_PFX+"confbar",XL+8,cyL,CW-16,g_lastSigConfidence,sig_clr); cyL+=BAR_H+2;
   
   bool daily_hit = (g_dailyPl >= InpDailyTargetUsd && InpDailyTargetUsd > 0);
   string status_disp = g_status;
   if(g_status == "RECOVERY_ONLY" && daily_hit) status_disp = "DAILY TGT HIT";
   color status_clr = (g_status=="HALT") ? CLR_RED : (g_status=="ACTIVE") ? CLR_GREEN : CLR_YELLOW;
   ObjRow(DASH_PFX+"r_sta_l",DASH_PFX+"r_sta_v",XL,cyL,CW,"Status",    status_disp, CLR_LABEL,status_clr); cyL+=ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div2",XL+6,cyL,CW-12); cyL+=3;
   ObjLabel(DASH_PFX+"s3hdr",XL+8,cyL,"▌ S/R & VOLATILITY",CLR_TITLE,9,DASH_FONT_BOLD); cyL+=ROW_H+2;
   ObjRow(DASH_PFX+"r_sup_l",DASH_PFX+"r_sup_v",XL,cyL,CW,"Support",   StringFormat("%.*f",g_digits,g_supportPx), CLR_LABEL,CLR_GREEN); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_res_l",DASH_PFX+"r_res_v",XL,cyL,CW,"Resistance",StringFormat("%.*f",g_digits,g_resistPx),  CLR_LABEL,CLR_RED); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_atr_l",DASH_PFX+"r_atr_v",XL,cyL,CW,"M1 ATR(pts)",StringFormat("%.1f",g_atrM1Pts), CLR_LABEL,CLR_CYAN); cyL+=ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div3",XL+6,cyL,CW-12); cyL+=3;
   ObjLabel(DASH_PFX+"s4hdr",XL+8,cyL,"▌ BASKETS",CLR_TITLE,9,DASH_FONT_BOLD); cyL+=ROW_H+2;
   int buy_n=BasketCount(0), sell_n=BasketCount(1);
   double buy_pl=BasketProfit(0), sell_pl=BasketProfit(1);
   
   string buy_flags = "";
   if(g_trailingActive[0]) buy_flags += " TR";
   if(g_partialStage[0]>0) buy_flags += StringFormat(" PC%d", g_partialStage[0]);
   if(g_recoveryMode[0])   buy_flags += " RM";
   ObjRow(DASH_PFX+"r_bb_l",DASH_PFX+"r_bb_v",XL,cyL,CW,
          StringFormat("BUY %d/%d%s",buy_n,InpRecoveryMaxLayers,buy_flags),
          StringFormat("%s$%.2f",buy_pl>=0?"+":"",buy_pl),
          CLR_GREEN,(buy_pl>=0)?CLR_GREEN:CLR_RED); cyL+=ROW_H;
   if(buy_n > 0)
   {
      ObjRow(DASH_PFX+"r_bavg_l",DASH_PFX+"r_bavg_v",XL,cyL,CW,
             "  Avg→TP",StringFormat("%.*f→%.*f",g_digits,BasketAvgPrice(0),g_digits,BasketTargetPrice(0)),CLR_LABEL,CLR_CYAN); cyL+=ROW_H;
      ObjRow(DASH_PFX+"r_bnl_l",DASH_PFX+"r_bnl_v",XL,cyL,CW,
             "  Next lot",StringFormat("%.2f",NextRecoveryLot(0)),CLR_LABEL,CLR_YELLOW); cyL+=ROW_H;
      ObjRow(DASH_PFX+"r_bml_l",DASH_PFX+"r_bml_v",XL,cyL,CW,
             "  MaxLoss",StringFormat("$%.2f",g_maxBasketLoss[0]),CLR_LABEL,g_maxBasketLoss[0]<-5?CLR_RED:CLR_LABEL); cyL+=ROW_H;
      if(g_trailingActive[0]) {
         ObjRow(DASH_PFX+"r_btr_l",DASH_PFX+"r_btr_v",XL,cyL,CW,"  Trail peak",StringFormat("$%.2f",g_peakProfit[0]),CLR_LABEL,CLR_PURPLE); cyL+=ROW_H;
      } else {
         ObjDel(DASH_PFX+"r_btr_l"); ObjDel(DASH_PFX+"r_btr_v");
      }
   } else {
      ObjDel(DASH_PFX+"r_bavg_l"); ObjDel(DASH_PFX+"r_bavg_v");
      ObjDel(DASH_PFX+"r_bnl_l");  ObjDel(DASH_PFX+"r_bnl_v");
      ObjDel(DASH_PFX+"r_btr_l");  ObjDel(DASH_PFX+"r_btr_v");
      ObjDel(DASH_PFX+"r_bml_l");  ObjDel(DASH_PFX+"r_bml_v");
   }

   string sell_flags = "";
   if(g_trailingActive[1]) sell_flags += " TR";
   if(g_partialStage[1]>0) sell_flags += StringFormat(" PC%d", g_partialStage[1]);
   if(g_recoveryMode[1])   sell_flags += " RM";
   ObjRow(DASH_PFX+"r_sb_l",DASH_PFX+"r_sb_v",XL,cyL,CW,
          StringFormat("SELL %d/%d%s",sell_n,InpRecoveryMaxLayers,sell_flags),
          StringFormat("%s$%.2f",sell_pl>=0?"+":"",sell_pl),
          CLR_RED,(sell_pl>=0)?CLR_GREEN:CLR_RED); cyL+=ROW_H;
   if(sell_n > 0)
   {
      ObjRow(DASH_PFX+"r_savg_l",DASH_PFX+"r_savg_v",XL,cyL,CW,
             "  Avg→TP",StringFormat("%.*f→%.*f",g_digits,BasketAvgPrice(1),g_digits,BasketTargetPrice(1)),CLR_LABEL,CLR_CYAN); cyL+=ROW_H;
      ObjRow(DASH_PFX+"r_snl_l",DASH_PFX+"r_snl_v",XL,cyL,CW,
             "  Next lot",StringFormat("%.2f",NextRecoveryLot(1)),CLR_LABEL,CLR_YELLOW); cyL+=ROW_H;
      ObjRow(DASH_PFX+"r_sml_l",DASH_PFX+"r_sml_v",XL,cyL,CW,
             "  MaxLoss",StringFormat("$%.2f",g_maxBasketLoss[1]),CLR_LABEL,g_maxBasketLoss[1]<-5?CLR_RED:CLR_LABEL); cyL+=ROW_H;
      if(g_trailingActive[1]) {
         ObjRow(DASH_PFX+"r_str2_l",DASH_PFX+"r_str2_v",XL,cyL,CW,"  Trail peak",StringFormat("$%.2f",g_peakProfit[1]),CLR_LABEL,CLR_PURPLE); cyL+=ROW_H;
      } else {
         ObjDel(DASH_PFX+"r_str2_l"); ObjDel(DASH_PFX+"r_str2_v");
      }
   } else {
      ObjDel(DASH_PFX+"r_savg_l"); ObjDel(DASH_PFX+"r_savg_v");
      ObjDel(DASH_PFX+"r_snl_l");  ObjDel(DASH_PFX+"r_snl_v");
      ObjDel(DASH_PFX+"r_str2_l"); ObjDel(DASH_PFX+"r_str2_v");
      ObjDel(DASH_PFX+"r_sml_l");  ObjDel(DASH_PFX+"r_sml_v");
   }

   double total_float=buy_pl+sell_pl;
   ObjRow(DASH_PFX+"r_flt_l",DASH_PFX+"r_flt_v",XL,cyL,CW,
          "Float Total",StringFormat("%s$%.2f",total_float>=0?"+":"",total_float),
          CLR_LABEL,total_float>=0?CLR_GREEN:CLR_RED); cyL+=ROW_H+SEC_GAP;

   ObjLabel(DASH_PFX+"s5hdr",XR+8,cyR,"▌ AI SCORES",CLR_TITLE,9,DASH_FONT_BOLD); cyR+=ROW_H+2;
   string strats[4]={"TREND","MEAN_REV","BREAKOUT","PULLBACK"};
   double scores[4]; scores[0]=g_scoreTrend;scores[1]=g_scoreMeanRev;scores[2]=g_scoreBreakout;scores[3]=g_scorePullback;
   color  scols[4];  scols[0]=CLR_CYAN;scols[1]=CLR_PURPLE;scols[2]=CLR_ORANGE;scols[3]=CLR_GREEN;
   string sicons[4]={"◆","◈","▶","◀"};
   for(int i=0;i<4;i++)
   {
      bool active=(strats[i]==g_lastSigStrategy);
      color lc=active?CLR_WHITE:CLR_LABEL;
      ObjRow(DASH_PFX+"r_ai_l"+strats[i],DASH_PFX+"r_ai_v"+strats[i],XR,cyR,CW,
             StringFormat("%s %s%s",sicons[i],strats[i],active?" ◄":""),
             StringFormat("%.0f%%",scores[i]*100.0),lc,scols[i]); cyR+=ROW_H-1;
      ObjBar(DASH_PFX+"aibar"+strats[i],XR+8,cyR,CW-16,scores[i],scols[i]); cyR+=BAR_H+2;
   }
   cyR+=SEC_GAP;

   ObjDivider(DASH_PFX+"div5",XR+6,cyR,CW-12); cyR+=3;
   ObjLabel(DASH_PFX+"s6hdr",XR+8,cyR,"▌ TF CONFLUENCE",CLR_TITLE,9,DASH_FONT_BOLD); cyR+=ROW_H+2;
   string tfnms[5]={"M1","M5","M15","H1","H4"};
   for(int i=0;i<5;i++)
   {
      if(!viewsOk[i]){ObjRow(DASH_PFX+"r_tf_l"+tfnms[i],DASH_PFX+"r_tf_v"+tfnms[i],XR,cyR,CW,tfnms[i],"…",CLR_LABEL,CLR_LABEL);cyR+=ROW_H;continue;}
      TFView v=views[i];
      string tdir; color tclr;
      if(v.trend>0){tdir="▲";tclr=CLR_GREEN;}else if(v.trend<0){tdir="▼";tclr=CLR_RED;}else{tdir="—";tclr=CLR_LABEL;}
      ObjRow(DASH_PFX+"r_tf_l"+tfnms[i],DASH_PFX+"r_tf_v"+tfnms[i],XR,cyR,CW,
             StringFormat("%-3s R:%.0f A:%.0f",tfnms[i],v.rsi_val,v.adx_val),tdir,CLR_LABEL,tclr); cyR+=ROW_H;
   }
   cyR+=SEC_GAP;

   ObjDivider(DASH_PFX+"div6",XR+6,cyR,CW-12); cyR+=3;
   ObjLabel(DASH_PFX+"s7hdr",XR+8,cyR,"▌ STATISTICS",CLR_TITLE,9,DASH_FONT_BOLD); cyR+=ROW_H+2;
   double wr=(g_totalTrades>0)?(double)g_winningTrades/g_totalTrades*100.0:0.0;
   color wr_clr=(wr>=60)?CLR_GREEN:(wr>=45?CLR_YELLOW:CLR_RED);
   double dtpct=(InpDailyTargetUsd>0)?MathMax(0.0,MathMin(1.0,g_dailyPl/InpDailyTargetUsd)):0.0;
   
   // [v17.00] Profit Factor calculation
   double pf = (g_grossLoss > 0.0) ? g_grossProfit / g_grossLoss : 0.0;
   string pfStr = (g_grossLoss == 0.0 && g_grossProfit > 0.0) ? "∞" : StringFormat("%.2f", pf);
   color pf_clr = (pf >= 2.0 || g_grossLoss == 0.0) ? CLR_GREEN : (pf >= 1.0 ? CLR_YELLOW : CLR_RED);
   
   ObjRow(DASH_PFX+"r_trd_l",DASH_PFX+"r_trd_v",XR,cyR,CW,"Trades",    IntegerToString(g_totalTrades),  CLR_LABEL,CLR_WHITE);  cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_wr_l", DASH_PFX+"r_wr_v", XR,cyR,CW,"Win Rate",  StringFormat("%.1f%% (%d/%d)",wr,g_winningTrades,g_totalTrades),CLR_LABEL,wr_clr); cyR+=ROW_H-1;
   ObjBar(DASH_PFX+"wrbar",XR+8,cyR,CW-16,wr/100.0,wr_clr); cyR+=BAR_H+2;
   ObjRow(DASH_PFX+"r_pf_l", DASH_PFX+"r_pf_v", XR,cyR,CW,"Profit Factor", pfStr, CLR_LABEL, pf_clr); cyR+=ROW_H;  // [v17.00]
   ObjRow(DASH_PFX+"r_net_l",DASH_PFX+"r_net_v",XR,cyR,CW,"Net P&L",   StringFormat("%s$%.2f",g_totalProfit>=0?"+":"",g_totalProfit),CLR_LABEL,g_totalProfit>=0?CLR_GREEN:CLR_RED); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_dtg_l",DASH_PFX+"r_dtg_v",XR,cyR,CW,"Daily Tgt", StringFormat("$%.2f/$%.0f",g_dailyPl,InpDailyTargetUsd),CLR_LABEL,dtpct>=1.0?CLR_GREEN:CLR_YELLOW); cyR+=ROW_H-1;
   ObjBar(DASH_PFX+"dtgbar",XR+8,cyR,CW-16,dtpct,dtpct>=1.0?CLR_GREEN:CLR_CYAN); cyR+=BAR_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div7",XR+6,cyR,CW-12); cyR+=3;
   ObjLabel(DASH_PFX+"s8hdr",XR+8,cyR,"▌ RISK LIMITS",CLR_TITLE,9,DASH_FONT_BOLD); cyR+=ROW_H+2;
   bool lm_halt = InpUseMaxEquityDdPct && (g_drawdownPct>=InpMaxEquityDdPct);
   bool lm_dtgt = daily_hit;
   bool lm_fm   = InpUseMinFreeMarginPct && (fm_pct<InpMinFreeMarginPct);
   bool lm_time = (InpUseTimeFilter&&!AllowedHour());
   bool lm_cd   = (TimeCurrent()<g_cooldownUntil);
   bool lm_sprd = (spread_pts>InpMaxSpreadPts);
   
   ObjRow(DASH_PFX+"r_g1_l",DASH_PFX+"r_g1_v",XR,cyR,CW,
          StringFormat("MaxDD %s %.0f%%", InpUseMaxEquityDdPct?"ON":"OFF", InpMaxEquityDdPct), 
          !InpUseMaxEquityDdPct?"OFF":(lm_halt?"✗ HIT":"✓ OK"),  
          CLR_LABEL, !InpUseMaxEquityDdPct?CLR_LABEL:(lm_halt?CLR_RED:CLR_GREEN));    cyR+=ROW_H;
          
   ObjRow(DASH_PFX+"r_g3_l",DASH_PFX+"r_g3_v",XR,cyR,CW,StringFormat("DlyTgt $%.0f",InpDailyTargetUsd),     lm_dtgt?"✓ HIT":"OK",    CLR_LABEL,lm_dtgt?CLR_YELLOW:CLR_GREEN); cyR+=ROW_H;
   
   ObjRow(DASH_PFX+"r_g4_l",DASH_PFX+"r_g4_v",XR,cyR,CW,
          StringFormat("FreeMgn %s %.0f%%", InpUseMinFreeMarginPct?"ON":"OFF", InpMinFreeMarginPct), 
          !InpUseMinFreeMarginPct?"OFF":(lm_fm?"✗ LOW":"✓ OK"),   
          CLR_LABEL, !InpUseMinFreeMarginPct?CLR_LABEL:(lm_fm?CLR_RED:CLR_GREEN));      cyR+=ROW_H;
          
   ObjRow(DASH_PFX+"r_g5_l",DASH_PFX+"r_g5_v",XR,cyR,CW,"Time Filter",                                      lm_time?"BLOCKED":"OPEN",CLR_LABEL,lm_time?CLR_YELLOW:CLR_GREEN); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g6_l",DASH_PFX+"r_g6_v",XR,cyR,CW,"Cooldown",    lm_cd?StringFormat("WAIT %ds",cd_left):"Ready",CLR_LABEL,lm_cd?CLR_ORANGE:CLR_GREEN); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g7_l",DASH_PFX+"r_g7_v",XR,cyR,CW,StringFormat("Spread %dpts",InpMaxSpreadPts),      lm_sprd?"✗ HIGH":"✓ OK", CLR_LABEL,lm_sprd?CLR_RED:CLR_GREEN);      cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g8_l",DASH_PFX+"r_g8_v",XR,cyR,CW,StringFormat("BasketSL %s $%.0f",InpUseBasketStopLoss?"ON":"OFF",InpMaxBasketLossUsd), "OK", CLR_LABEL, InpUseBasketStopLoss?CLR_CYAN:CLR_LABEL); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g9_l",DASH_PFX+"r_g9_v",XR,cyR,CW,"Trailing",
          InpTrailingEnable?StringFormat("ON trig=$%.1f",InpTrailingTriggerUsd):"OFF",
          CLR_LABEL,InpTrailingEnable?CLR_CYAN:CLR_LABEL); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_ga_l",DASH_PFX+"r_ga_v",XR,cyR,CW,"PartialClose",
          InpPartialCloseEnable?StringFormat("ON @$%.1f×%d",InpPartialCloseAtUsd,InpStagedPartialClose?InpPartialCloseLevels:1):"OFF",
          CLR_LABEL,InpPartialCloseEnable?CLR_CYAN:CLR_LABEL); cyR+=ROW_H+SEC_GAP;

   int cyBot = MathMax(cyL, cyR);
   ObjDivider(DASH_PFX+"divF",XL+6,cyBot,DASH_W-12); cyBot+=4;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   ObjLabel(DASH_PFX+"footer",XL+DASH_W/2,cyBot,
            StringFormat("%04d-%02d-%02d  %02d:%02d:%02d",dt.year,dt.mon,dt.day,dt.hour,dt.min,dt.sec),
            CLR_LABEL,8,DASH_FONT,ANCHOR_CENTER);
   cyBot+=ROW_H+4;

   int totalH = cyBot - InpDashY + 6;
   ObjRect(DASH_PFX+"bg",    InpDashX, InpDashY, DASH_W, totalH, g_dashBg, g_dashBorder, 2);
   ObjRect(DASH_PFX+"coldiv",InpDashX+DASH_COL_W+(DASH_GAP/2)-1, InpDashY+30, 2, totalH-30, CLR_DIVIDER, CLR_DIVIDER, 0);
   ObjRect(DASH_PFX+"hdr",InpDashX,InpDashY,DASH_W,26,C'30,45,72',g_dashBorder,0);
   ObjLabel(DASH_PFX+"title",InpDashX+12,InpDashY+5,"ZERITH XAU SCALPING v17.00",CLR_TITLE,10,DASH_FONT_BOLD);
   ObjLabel(DASH_PFX+"sub",  InpDashX+DASH_W-12,InpDashY+6,Symbol()+"  MT5",CLR_LABEL,8,DASH_FONT,ANCHOR_RIGHT);
   ChartRedraw();
}
//+------------------------------------------------------------------+