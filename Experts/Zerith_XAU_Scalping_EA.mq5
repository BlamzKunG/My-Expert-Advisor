//+------------------------------------------------------------------+
//|                                     Zerith_XAU_Scalping_EA.mq5   |
//|                 Zerith Series / BlamzKunG                        |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//|  v18.00 - Pure One-Shot Momentum Breakout Engine (XAUUSD)        |
//|  Features: M1 Breakout, ATR TP, Hard SL, Basket Trailing, OneShot|
//+------------------------------------------------------------------+
#property copyright   "Zerith Series / BlamzKunG"
#property link        "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version     "18.00"
#property description "Zerith XAU Scalping MT5 v18.00 - One-Shot Breakout Engine with Dynamic TP, Hard SL & Trailing Stop"
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
   int    sl_points;
};

//=====================================================================
// INPUT PARAMETERS - Zerith XAU Scalping v18.00 (Breakout One-Shot)
//=====================================================================

input group ">>>> 1. Zerith Breakout: Trading Basics"
input double   InpInitialLot          = 0.01;         // Trading Lot Size
input int      InpDeviation           = 30;           // Max Deviation / Slippage (Points)
input long     InpMagic               = 20260520;     // EA Magic Number
input string   InpTradeCommentPrefix  = "Zerith XAU";  // Trade Comment Prefix

input group ">>>> 2. Zerith Breakout: Entry & Filters"
input bool     InpUseHtfFilter        = false;        // Require H1 Trend Alignment (Optional)
input int      InpTrendAdx            = 25;           // Min H1 ADX for Trend Filter
input double   InpMinAtrPoints        = 50.0;         // Minimum M1 ATR Points to Trade

input group ">>>> 3. Zerith Breakout: Take-Profit & Stop-Loss"
input int      InpTpPointsBase        = 300;          // Base Take-Profit (Points, 100pts = $1)
input int      InpTpPointsMin         = 50;           // Minimum Take-Profit (Points)
input double   InpTpAtrMult           = 1.5;          // Dynamic ATR TP Multiplier (0 = Fixed Base TP)
input int      InpStopLossPoints      = 300;          // Ticket Stop-Loss in Points (0 = Disabled)
input double   InpStopLossUsd         = 5.0;          // Emergency Hard SL in USD (0 = Disabled)

input group ">>>> 4. Zerith Breakout: Trailing Stop"
input bool     InpTrailingEnable      = true;         // Enable Trailing Stop Engine
input double   InpTrailingTriggerUsd  = 2.0;          // Trailing Activation Profit ($)
input double   InpTrailingStepUsd     = 1.0;          // Trailing Callback / Step ($)

input group ">>>> 5. Zerith Breakout: Capital & Risk Guards"
input double   InpDailyTargetUsd      = 50.0;         // Daily Profit Target ($)
input bool     InpUseMaxEquityDdPct   = false;        // Enable Max Equity Drawdown Guard
input double   InpMaxEquityDdPct      = 15.0;         // Max Equity Drawdown Allowed (%)
input bool     InpUseMinFreeMarginPct = false;        // Enable Min Free Margin Guard
input double   InpMinFreeMarginPct    = 30.0;         // Min Free Margin Allowed (%)
input int      InpCooldownSec         = 30;           // Cooldown After Close (Seconds)
input bool     InpWaitNextBarAfterClose = true;       // Wait for Next M1 Bar After Close
input int      InpMaxTradeAgeHours    = 4;            // Max Holding Time (Hours, 0 = Disabled)
input int      InpMaxSpreadPts        = 50;           // Max Allowed Spread (Points)

input group ">>>> 6. Zerith Breakout: Session & Time Filters"
input bool     InpUseTimeFilter       = false;        // Enable Trading Session Filter
input int      InpAllowHourFrom       = 6;            // Trading Start Hour (UTC)
input int      InpAllowHourTo         = 20;           // Trading End Hour (UTC)
input int      InpServerGMTOffset     = 2;            // Broker Server GMT Offset

input group ">>>> 7. Zerith Breakout: Indicator Bars & Debug"
input int      InpBarsM1              = 150;          // M1 History Bars to Load
input int      InpBarsHTF             = 100;          // Higher TF History Bars to Load
input bool     InpPrintDebug          = false;        // Print Detailed Diagnostic Logs

input group ">>>> 8. Zerith Breakout: Visual Dashboard"
input bool     InpShowDashboard       = true;         // Display On-Chart Dashboard
input int      InpDashX               = 20;           // Dashboard X Coordinate
input int      InpDashY               = 30;           // Dashboard Y Coordinate
input bool     InpDashAutoColor       = true;         // Auto Detect Dark/Light Background
input color    InpDashBgColor         = C'18,24,38';  // Dashboard Background Color
input color    InpDashBorderColor     = C'52,152,219';// Dashboard Border Color

//=====================================================================
// GLOBALS
//=====================================================================
CTrade         g_trade;
CPositionInfo  g_pos;
CSymbolInfo    g_sym;

double   g_point;
int      g_digits;
double   g_pointFactor;

// Tester & Optimization environment flags
bool     g_isTester       = false;
bool     g_isOptimization = false;
bool     g_isVisual       = false;

// Cached symbol trading properties
double   g_volStep        = 0.01;
double   g_volMin         = 0.01;
double   g_volMax         = 100.0;
int      g_stopsLevel     = 0;

// Daily tracking
double   g_dayStartEquity   = 0.0;
datetime g_dayStartTime     = 0;
double   g_peakEquity       = 0.0;
double   g_dailyPl          = 0.0;
double   g_drawdownPct      = 0.0;

datetime g_cooldownUntil    = 0;
datetime g_lastOpenTime     = 0;
datetime g_lastCloseTime    = 0;

double   g_atrM1            = 0.0;
double   g_atrM1Pts         = 0.0;

// Adaptive AI score for Breakout (rolling 30 trades)
double   g_scoreBreakout    = 0.5;
#define PERF_BUF 30
double   g_perfBreakout[PERF_BUF];
int      g_perfBreakoutIdx  = 0;
int      g_perfBreakoutN    = 0;

// Performance statistics
int      g_totalTrades      = 0;
int      g_winningTrades    = 0;
double   g_totalProfit      = 0.0;
double   g_grossProfit      = 0.0;
double   g_grossLoss        = 0.0;

// Active Position Tracking (One-Shot Single Position)
bool     g_hasPosition      = false;
ulong    g_posTicket        = 0;
ulong    g_posId            = 0;
int      g_posType          = -1; // 0: BUY, 1: SELL
double   g_posVolume        = 0.0;
double   g_posPriceOpen     = 0.0;
double   g_posPriceCurrent  = 0.0;
double   g_posSl            = 0.0;
double   g_posTp            = 0.0;
double   g_posProfit        = 0.0;
datetime g_posTime          = 0;
string   g_posComment       = "";

// Trailing State
bool     g_trailingActive   = false;
double   g_peakProfit       = 0.0;

// Status & Signals
string   g_status           = "INIT";
string   g_lastSigAction    = "WAIT";
string   g_lastSigStrategy  = "BREAKOUT";
double   g_lastSigConfidence= 0.0;
string   g_lastSigReason    = "";

// Dashboard styling
#define DASH_PFX   "ZERITH_DASH_"
int      g_saveCounter      = 0;
string   g_gvPrefix         = "";
color    g_dashBg;
color    g_dashBorder;

// HTF Caching
datetime g_lastHtfBarM5     = 0;
datetime g_lastHtfBarM15    = 0;
datetime g_lastHtfBarH1     = 0;
datetime g_lastHtfBarH4     = 0;
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
bool   ShouldUpdateDashboard();
void   DecideSignal(TFView &views[], bool &viewsOk[], Signal &out);
void   RecordOutcome(double pnl);
string DecideStatus(double bal, double eq, double fm);
bool   AllowedHour();
double CurrentSpreadPts();
bool   SpreadAcceptable();
int    CalcTpPoints(int direction);
void   UpdateActivePosition();
void   ManagePositionRisk();
void   CloseActivePosition(const string reason);
void   TryOpenBreakout(const Signal &sig);
void   CheckPositionClose();
void   ResetDay();
void   CheckDayRollover();
void   UpdateDailyPL(double eq);
void   UpdateDD(double eq);
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
   if(g_point <= 0.0) g_point = 0.01;
   
   g_pointFactor = (g_digits == 3 || g_digits == 5) ? 10.0 : 1.0;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviation);
   g_trade.SetTypeFilling(PickFilling());
   g_trade.SetAsyncMode(false);

   g_gvPrefix = StringFormat("ZXAU18_%I64d_%s_", InpMagic, Symbol());

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

   if(InpInitialLot <= 0)
      { Print("ERROR: InpInitialLot must be > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpTrailingEnable && InpTrailingStepUsd >= InpTrailingTriggerUsd)
      PrintFmt("WARN: TrailingStep >= TrailingTrigger.");

   ArrayInitialize(g_perfBreakout, 0.5);

   ResetDay();
   if(g_peakEquity <= 0.0) g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!g_isTester) LoadState();

   UpdateActivePosition();

   PrintFmt(StringFormat("Zerith XAU Scalping v18.00 BREAKOUT ONE-SHOT | %s digits=%d point=%.5f factor=%.0f",
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
   DashDelete();
}

//=====================================================================
// OnTick
//=====================================================================
void OnTick()
{
   g_sym.RefreshRates();
   CheckDayRollover();
   UpdateActivePosition();

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   UpdateDailyPL(eq);
   UpdateDD(eq);

   // Check if previously open position closed on this tick
   CheckPositionClose();

   // Manage Risk & Trailing for active position
   ManagePositionRisk();

   // Multi-Timeframe Analysis
   TFView views[5];
   bool   viewsOk[5];
   ENUM_TIMEFRAMES tfs[5] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1, PERIOD_H4};
   string  tfNames[5]     = {"M1","M5","M15","H1","H4"};
   int     tfBars[5]      = {InpBarsM1, InpBarsHTF, InpBarsHTF, InpBarsHTF, InpBarsHTF};

   // Fast M1 cache on zero-movement ticks
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

   if(!viewsOk[0])
   { g_status = "INIT"; return; }

   g_atrM1 = views[0].atr_val;
   double one_pt = g_point * g_pointFactor;
   if(one_pt > 0.0) g_atrM1Pts = g_atrM1 / one_pt;
   else g_atrM1Pts = InpMinAtrPoints;

   g_status = DecideStatus(bal, eq, fm);

   Signal sig;
   DecideSignal(views, viewsOk, sig);
   g_lastSigAction     = sig.action;
   g_lastSigStrategy   = sig.strategy;
   g_lastSigConfidence = sig.confidence;
   g_lastSigReason     = sig.reason;

   if(g_status == "HALT")
   {
      if(g_hasPosition) CloseActivePosition("HALT: equity DD limit");
      if(ShouldUpdateDashboard()) DashUpdate(bal, eq, fm, views, viewsOk);
      return;
   }

   // Open New Trade (Only when flat)
   if(g_status == "ACTIVE" && !g_hasPosition && (sig.action == "BUY" || sig.action == "SELL") && SpreadAcceptable())
   {
      TryOpenBreakout(sig);
   }

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
   GlobalVariableSet(GVKey("score_breakout"), g_scoreBreakout);
   GlobalVariableSet(GVKey("peak_equity"),    g_peakEquity);
   GlobalVariableSet(GVKey("total_trades"),   (double)g_totalTrades);
   GlobalVariableSet(GVKey("winning_trades"), (double)g_winningTrades);
   GlobalVariableSet(GVKey("total_profit"),   g_totalProfit);
   GlobalVariableSet(GVKey("gross_profit"),   g_grossProfit);
   GlobalVariableSet(GVKey("gross_loss"),     g_grossLoss);
   GlobalVariableSet(GVKey("cooldown_until"), (double)(long)g_cooldownUntil);
   GlobalVariableSet(GVKey("last_close_time"),(double)(long)g_lastCloseTime);
}

void LoadState()
{
   string sb = GVKey("score_breakout"); if(GlobalVariableCheck(sb)) g_scoreBreakout = GlobalVariableGet(sb);
   string pe = GVKey("peak_equity");    if(GlobalVariableCheck(pe)) { double sv = GlobalVariableGet(pe); if(sv > 0.0) g_peakEquity = sv; }
   string tt = GVKey("total_trades");   if(GlobalVariableCheck(tt)) g_totalTrades   = (int)GlobalVariableGet(tt);
   string tw = GVKey("winning_trades"); if(GlobalVariableCheck(tw)) g_winningTrades = (int)GlobalVariableGet(tw);
   string tp = GVKey("total_profit");   if(GlobalVariableCheck(tp)) g_totalProfit   = GlobalVariableGet(tp);
   string gp = GVKey("gross_profit");   if(GlobalVariableCheck(gp)) g_grossProfit   = GlobalVariableGet(gp);
   string gl = GVKey("gross_loss");     if(GlobalVariableCheck(gl)) g_grossLoss     = GlobalVariableGet(gl);

   string cu = GVKey("cooldown_until");
   if(GlobalVariableCheck(cu)) { datetime sc = (datetime)(long)GlobalVariableGet(cu); if(sc > TimeCurrent()) g_cooldownUntil = sc; }

   string lct = GVKey("last_close_time");
   if(GlobalVariableCheck(lct)) g_lastCloseTime = (datetime)(long)GlobalVariableGet(lct);
}

//=====================================================================
// INDICATORS (No-Handle Zero Allocation Math Engine)
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

   v.tf_name        = tf_name;
   v.trend          = trend;
   v.adx_val        = adx_v;
   v.atr_val        = CalcATR(high_arr,low_arr,close_arr,cnt,14);
   v.rsi_val        = CalcRSI(close_arr,cnt,14);
   v.bb_width       = (cnt >= 20) ? CalcBBWidth(close_arr,cnt,20) : 0.0;
   v.macd_hist      = macd_arr[cnt-1];
   v.macd_hist_prev = macd_arr[cnt-2];
   v.last_close     = lc;
   v.ema_fast       = ef;
   v.ema_slow       = es;
   return true;
}

//=====================================================================
// SIGNAL DECISION (Breakout Engine)
//=====================================================================
void DecideSignal(TFView &views[], bool &viewsOk[], Signal &out)
{
   out.action     = "WAIT";
   out.strategy   = "BREAKOUT";
   out.confidence = 0.0;
   out.reason     = "Searching Breakout Setup";
   out.tp_points  = InpTpPointsBase;
   out.sl_points  = InpStopLossPoints;

   if(!viewsOk[0]) return;
   TFView m1 = views[0];

   // Volatility floor guard (avoid dead flat consolidation)
   if(g_atrM1Pts < InpMinAtrPoints)
   {
      out.reason = StringFormat("M1 ATR (%.1f pts) < Min (%.1f pts)", g_atrM1Pts, InpMinAtrPoints);
      return;
   }

   // Breakout Trigger: M1 Trend Alignment + Positive MACD Acceleration
   if(m1.trend > 0 && m1.macd_hist > 0 && m1.macd_hist > m1.macd_hist_prev)
   {
      if(!InpUseHtfFilter || (viewsOk[3] && views[3].trend >= 0))
      {
         out.action     = "BUY";
         out.confidence = 0.70;
         out.reason     = "M1 Trend UP + Rising MACD";
         out.tp_points  = CalcTpPoints(0);
         out.sl_points  = InpStopLossPoints;
      }
      else
      {
         out.reason = "Filtered: H1 Trend opposes BUY";
      }
   }
   else if(m1.trend < 0 && m1.macd_hist < 0 && m1.macd_hist < m1.macd_hist_prev)
   {
      if(!InpUseHtfFilter || (viewsOk[3] && views[3].trend <= 0))
      {
         out.action     = "SELL";
         out.confidence = 0.70;
         out.reason     = "M1 Trend DN + Falling MACD";
         out.tp_points  = CalcTpPoints(1);
         out.sl_points  = InpStopLossPoints;
      }
      else
      {
         out.reason = "Filtered: H1 Trend opposes SELL";
      }
   }

   // Dynamic AI weight adjustment based on rolling 30 trades
   out.confidence *= (0.7 + 0.6 * g_scoreBreakout);

   if(out.confidence < 0.60 && out.action != "WAIT")
   {
      out.reason = StringFormat("Conf %.2f < 0.60 (Confidence Gate)", out.confidence);
      out.action = "WAIT";
   }
}

//=====================================================================
// ADAPTIVE SCORE HELPER
//=====================================================================
void RecordOutcome(double pnl)
{
   double val = (pnl > 0) ? 1.0 : 0.0;
   g_perfBreakout[g_perfBreakoutIdx % PERF_BUF] = val;
   g_perfBreakoutIdx++;
   if(g_perfBreakoutN < PERF_BUF) g_perfBreakoutN++;
   int sz = MathMin(g_perfBreakoutN, PERF_BUF);
   double s = 0;
   for(int i=0; i<sz; i++) s += g_perfBreakout[i];
   g_scoreBreakout = 0.7 * g_scoreBreakout + 0.3 * (sz > 0 ? s / sz : 0.5);
}

//=====================================================================
// STATUS & RISK GUARDS
//=====================================================================
string DecideStatus(double bal, double eq, double fm)
{
   double fm_pct = (eq > 0) ? fm / eq * 100.0 : 0.0;
   if(InpUseMaxEquityDdPct && g_drawdownPct >= InpMaxEquityDdPct) return "HALT";
   if(g_dailyPl >= InpDailyTargetUsd && InpDailyTargetUsd > 0)    return "DAILY_HIT";
   if(InpUseTimeFilter && !AllowedHour())                        return "TIME_BLOCKED";
   if(InpUseMinFreeMarginPct && fm_pct < InpMinFreeMarginPct)    return "LOW_MARGIN";
   if(TimeCurrent() < g_cooldownUntil)                          return "COOLDOWN";
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
// TAKE-PROFIT CALCULATION
//=====================================================================
int CalcTpPoints(int direction)
{
   int minTpPts = MathMax(g_stopsLevel + 2, InpTpPointsMin);
   int base_pts = InpTpPointsBase;
   if(InpTpAtrMult <= 0.0 || g_atrM1Pts <= 0.0) return MathMax(minTpPts, base_pts);
   int atr_pts = (int)MathRound(g_atrM1Pts * InpTpAtrMult);
   atr_pts = (int)MathMax((double)minTpPts, MathMin((double)(InpTpPointsBase * 3), (double)atr_pts));
   return MathMax(base_pts, atr_pts);
}

//=====================================================================
// ACTIVE POSITION MANAGEMENT (One-Shot Single Position Engine)
//=====================================================================
void UpdateActivePosition()
{
   g_hasPosition = false;
   int total = PositionsTotal();
   if(total == 0)
   {
      g_posTicket = 0;
      g_posId     = 0;
      g_posProfit = 0.0;
      return;
   }

   for(int i = 0; i < total; i++)
   {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Symbol() != Symbol() || g_pos.Magic() != (ulong)InpMagic) continue;

      g_hasPosition     = true;
      g_posTicket       = g_pos.Ticket();
      g_posId           = (ulong)g_pos.Identifier();
      g_posType         = (g_pos.PositionType() == POSITION_TYPE_BUY) ? 0 : 1;
      g_posVolume       = g_pos.Volume();
      g_posPriceOpen    = g_pos.PriceOpen();
      g_posPriceCurrent = g_pos.PriceCurrent();
      g_posSl           = g_pos.StopLoss();
      g_posTp           = g_pos.TakeProfit();
      g_posProfit       = g_pos.Profit() + g_pos.Swap();
      g_posTime         = (datetime)g_pos.Time();
      g_posComment      = g_pos.Comment();
      return; // One-Shot: only 1 position tracked
   }
}

void ManagePositionRisk()
{
   if(!g_hasPosition) return;

   // 1. Emergency Hard USD Stop Loss
   if(InpStopLossUsd > 0.0 && g_posProfit <= -InpStopLossUsd)
   {
      PrintFmt(StringFormat("HARD STOP-LOSS: P&L=$%.2f <= -$%.2f — Closing #%llu",
               g_posProfit, InpStopLossUsd, g_posTicket));
      CloseActivePosition(StringFormat("Hard SL -$%.2f", InpStopLossUsd));
      return;
   }

   // 2. Maximum Holding Time (Time Stop)
   if(InpMaxTradeAgeHours > 0 && g_posTime > 0)
   {
      int ageHours = (int)((TimeCurrent() - g_posTime) / 3600);
      if(ageHours >= InpMaxTradeAgeHours)
      {
         PrintFmt(StringFormat("TIME-STOP: Holding age %dh >= %dh — Closing #%llu",
                  ageHours, InpMaxTradeAgeHours, g_posTicket));
         CloseActivePosition(StringFormat("Time-Stop %dh", ageHours));
         return;
      }
   }

   // 3. Trailing Stop Engine
   if(InpTrailingEnable)
   {
      if(!g_trailingActive)
      {
         if(g_posProfit >= InpTrailingTriggerUsd)
         {
            g_trailingActive = true;
            g_peakProfit     = g_posProfit;
            PrintFmt(StringFormat("Trailing ARMED: Peak P&L=$%.2f", g_posProfit));
         }
      }
      else
      {
         if(g_posProfit > g_peakProfit)
            g_peakProfit = g_posProfit;

         if(g_peakProfit - g_posProfit >= InpTrailingStepUsd)
         {
            PrintFmt(StringFormat("Trailing EXIT: Peak=$%.2f, Now=$%.2f, Drop=$%.2f — Closing #%llu",
                     g_peakProfit, g_posProfit, g_peakProfit - g_posProfit, g_posTicket));
            CloseActivePosition(StringFormat("Trailing Exit (Peak $%.2f)", g_peakProfit));
            return;
         }
      }
   }
}

void CloseActivePosition(const string reason)
{
   if(!g_hasPosition || g_posTicket == 0) return;
   PrintFmt(StringFormat("CloseActivePosition #%llu: %s", g_posTicket, reason));
   if(!g_trade.PositionClose(g_posTicket, InpDeviation))
      PrintFmt(StringFormat("PositionClose fail #%llu err=%d", g_posTicket, GetLastError()));

   g_trailingActive = false;
   g_peakProfit     = 0.0;
   g_lastCloseTime  = TimeCurrent();
   UpdateActivePosition();
}

void CheckPositionClose()
{
   static ulong lastTrackedId = 0;
   if(g_hasPosition)
   {
      lastTrackedId = g_posId;
      return;
   }

   // Position was just closed
   if(!g_hasPosition && lastTrackedId != 0)
   {
      ulong closedId = lastTrackedId;
      lastTrackedId  = 0;

      double profit = 0.0;
      if(HistorySelectByPosition(closedId))
      {
         int deals = HistoryDealsTotal();
         for(int i = 0; i < deals; i++)
         {
            ulong dt = HistoryDealGetTicket(i);
            if(dt == 0) continue;
            if((ulong)HistoryDealGetInteger(dt, DEAL_POSITION_ID) != closedId) continue;
            long entry_type = HistoryDealGetInteger(dt, DEAL_ENTRY);
            if(entry_type != DEAL_ENTRY_OUT && entry_type != DEAL_ENTRY_INOUT) continue;
            profit += HistoryDealGetDouble(dt, DEAL_PROFIT)
                    + HistoryDealGetDouble(dt, DEAL_SWAP)
                    + HistoryDealGetDouble(dt, DEAL_COMMISSION);
         }
      }

      // Update AI score
      RecordOutcome(profit);

      // Cooldown: 1x on win, 3x on loss
      int cdMult = (profit >= 0.0) ? 1 : 3;
      g_cooldownUntil = TimeCurrent() + InpCooldownSec * cdMult;
      g_lastCloseTime = TimeCurrent();

      // Update stats
      g_totalTrades++;
      g_totalProfit += profit;
      if(profit > 0)
      {
         g_winningTrades++;
         g_grossProfit += profit;
      }
      else
      {
         g_grossLoss += (-profit);
      }

      double wr = (g_totalTrades > 0) ? (double)g_winningTrades / g_totalTrades * 100.0 : 0.0;
      PrintFmt(StringFormat("Trade CLOSED #%llu | Net P&L=$%.2f | [Trades:%d, WR:%.1f%%, TotalP&L:$%.2f]",
               closedId, profit, g_totalTrades, wr, g_totalProfit));

      g_trailingActive = false;
      g_peakProfit     = 0.0;
   }
}

//=====================================================================
// OPEN BREAKOUT TRADE
//=====================================================================
void TryOpenBreakout(const Signal &sig)
{
   if(sig.confidence < 0.60) return;
   if(g_hasPosition) return;

   // Wait for next M1 bar after last close
   if(InpWaitNextBarAfterClose && g_lastCloseTime > 0)
   {
      datetime currentBarTime = (datetime)SeriesInfoInteger(Symbol(), PERIOD_M1, SERIES_LASTBAR_DATE);
      if(currentBarTime == 0) currentBarTime = TimeCurrent();
      if(currentBarTime <= g_lastCloseTime) return;
   }

   if(!SpreadAcceptable()) return;
   if(TimeCurrent() < g_cooldownUntil) return;

   int direction = (sig.action == "BUY") ? 0 : 1;
   double one_pt = g_point * g_pointFactor;
   double entry  = (direction == 0) ? g_sym.Ask() : g_sym.Bid();
   int    tp_pts = sig.tp_points;
   int    sl_pts = sig.sl_points;

   double tp_px = 0.0;
   double sl_px = 0.0;

   if(direction == 0)
   {
      tp_px = NormPrice(entry + tp_pts * one_pt);
      sl_px = (sl_pts > 0) ? NormPrice(entry - sl_pts * one_pt) : 0.0;
   }
   else
   {
      tp_px = NormPrice(entry - tp_pts * one_pt);
      sl_px = (sl_pts > 0) ? NormPrice(entry + sl_pts * one_pt) : 0.0;
   }

   string cmt      = StringFormat("%s_BRK_%d", InpTradeCommentPrefix, (int)(sig.confidence * 100));
   double open_lot = NormLot(InpInitialLot);
   bool ok = false;

   if(direction == 0) ok = g_trade.Buy (open_lot, Symbol(), entry, sl_px, tp_px, cmt);
   else               ok = g_trade.Sell(open_lot, Symbol(), entry, sl_px, tp_px, cmt);

   if(ok)
   {
      g_lastOpenTime   = TimeCurrent();
      g_trailingActive = false;
      g_peakProfit     = 0.0;
      UpdateActivePosition();
      PrintFmt(StringFormat("NEW BREAKOUT %s lot=%.2f @ %.5f [SL:%.5f, TP:%.5f] (Conf:%.0f%%) %s",
               sig.action, open_lot, entry, sl_px, tp_px, sig.confidence * 100, sig.reason));
   }
}

//=====================================================================
// DAILY PL / DD / ROLLOVER
//=====================================================================
void ResetDay()
{
   g_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartTime   = TimeCurrent();
   g_dailyPl        = 0.0;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   PrintFmt(StringFormat("Day reset. Eq=%.2f  %04d-%02d-%02d", g_dayStartEquity, dt.year, dt.mon, dt.day));
}

void CheckDayRollover()
{
   MqlDateTime n, s;
   TimeToStruct(TimeCurrent(), n);
   TimeToStruct(g_dayStartTime, s);
   if(n.day != s.day || n.mon != s.mon || n.year != s.year) ResetDay();
}

void UpdateDailyPL(double eq) { g_dailyPl = eq - g_dayStartEquity; }

void UpdateDD(double eq)
{
   if(eq > g_peakEquity) g_peakEquity = eq;
   if(g_peakEquity > 0.0) g_drawdownPct = MathMax(0.0, (g_peakEquity - eq) / g_peakEquity * 100.0);
}

//=====================================================================
// UTILITIES
//=====================================================================
ENUM_ORDER_TYPE_FILLING PickFilling()
{
   uint fill = (uint)SymbolInfoInteger(Symbol(), SYMBOL_FILLING_MODE);
   if((fill & (uint)SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((fill & (uint)SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
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

#define DASH_COL_W    280
#define DASH_GAP        8
#define DASH_W         (DASH_COL_W*2+DASH_GAP)
#define DASH_FONT      "Consolas"
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
   ObjLabel(DASH_PFX+"title", x+12,y+5,  "ZERITH XAU BREAKOUT v18.00",   CLR_TITLE, 10, DASH_FONT_BOLD);
   ObjLabel(DASH_PFX+"sub",   x+DASH_W-12,y+6, Symbol()+"  ONE-SHOT MT5", CLR_LABEL, 8, DASH_FONT, ANCHOR_RIGHT);
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
   ObjLabel(DASH_PFX+"s2hdr",XL+8,cyL,"▌ BREAKOUT ENGINE",CLR_TITLE,9,DASH_FONT_BOLD); cyL+=ROW_H+2;
   color sig_clr=(g_lastSigAction=="BUY")?CLR_GREEN:(g_lastSigAction=="SELL"?CLR_RED:CLR_LABEL);
   ObjRow(DASH_PFX+"r_sig_l",DASH_PFX+"r_sig_v",XL,cyL,CW,"Action",    g_lastSigAction,    CLR_LABEL,sig_clr); cyL+=ROW_H;
   ObjRow(DASH_PFX+"r_con_l",DASH_PFX+"r_con_v",XL,cyL,CW,"Conf",      StringFormat("%.0f%%",g_lastSigConfidence*100),CLR_LABEL,CLR_WHITE); cyL+=ROW_H-1;
   ObjBar(DASH_PFX+"confbar",XL+8,cyL,CW-16,g_lastSigConfidence,sig_clr); cyL+=BAR_H+2;
   ObjRow(DASH_PFX+"r_atr_l",DASH_PFX+"r_atr_v",XL,cyL,CW,"M1 ATR(pts)",StringFormat("%.1f",g_atrM1Pts), CLR_LABEL,CLR_CYAN); cyL+=ROW_H;

   bool daily_hit = (g_dailyPl >= InpDailyTargetUsd && InpDailyTargetUsd > 0);
   string status_disp = g_status;
   if(status_disp == "DAILY_HIT") status_disp = "DAILY TGT HIT";
   color status_clr = (g_status=="HALT") ? CLR_RED : (g_status=="ACTIVE") ? CLR_GREEN : CLR_YELLOW;
   ObjRow(DASH_PFX+"r_sta_l",DASH_PFX+"r_sta_v",XL,cyL,CW,"Status",    status_disp, CLR_LABEL,status_clr); cyL+=ROW_H+SEC_GAP;

   ObjDivider(DASH_PFX+"div2",XL+6,cyL,CW-12); cyL+=3;
   ObjLabel(DASH_PFX+"s3hdr",XL+8,cyL,"▌ ACTIVE POSITION (ONE-SHOT)",CLR_TITLE,9,DASH_FONT_BOLD); cyL+=ROW_H+2;
   if(g_hasPosition)
   {
      string p_dir = (g_posType == 0) ? "BUY" : "SELL";
      color  p_clr = (g_posType == 0) ? CLR_GREEN : CLR_RED;
      color  pl_clr2 = (g_posProfit >= 0) ? CLR_GREEN : CLR_RED;
      ObjRow(DASH_PFX+"r_pos_l", DASH_PFX+"r_pos_v", XL,cyL,CW,
             StringFormat("%s %.2f #%llu", p_dir, g_posVolume, g_posTicket),
             StringFormat("%s$%.2f", g_posProfit>=0?"+":"", g_posProfit), p_clr, pl_clr2); cyL+=ROW_H;

      ObjRow(DASH_PFX+"r_px_l", DASH_PFX+"r_px_v", XL,cyL,CW,
             "  Open -> Now", StringFormat("%.*f -> %.*f", g_digits, g_posPriceOpen, g_digits, g_posPriceCurrent), CLR_LABEL, CLR_CYAN); cyL+=ROW_H;

      ObjRow(DASH_PFX+"r_sltp_l", DASH_PFX+"r_sltp_v", XL,cyL,CW,
             "  SL | TP", StringFormat("%.*f | %.*f", g_digits, g_posSl, g_digits, g_posTp), CLR_LABEL, CLR_WHITE); cyL+=ROW_H;

      if(g_trailingActive) {
         ObjRow(DASH_PFX+"r_tr_l", DASH_PFX+"r_tr_v", XL,cyL,CW,
                "  Trail Peak", StringFormat("$%.2f", g_peakProfit), CLR_LABEL, CLR_PURPLE); cyL+=ROW_H;
      } else {
         ObjDel(DASH_PFX+"r_tr_l"); ObjDel(DASH_PFX+"r_tr_v");
      }
   }
   else
   {
      ObjRow(DASH_PFX+"r_pos_l", DASH_PFX+"r_pos_v", XL,cyL,CW, "Position", "FLAT (No Open Trades)", CLR_LABEL, CLR_LABEL); cyL+=ROW_H;
      ObjDel(DASH_PFX+"r_px_l");   ObjDel(DASH_PFX+"r_px_v");
      ObjDel(DASH_PFX+"r_sltp_l"); ObjDel(DASH_PFX+"r_sltp_v");
      ObjDel(DASH_PFX+"r_tr_l");   ObjDel(DASH_PFX+"r_tr_v");
   }
   cyL+=SEC_GAP;

   ObjLabel(DASH_PFX+"s5hdr",XR+8,cyR,"▌ AI BREAKOUT SCORE",CLR_TITLE,9,DASH_FONT_BOLD); cyR+=ROW_H+2;
   ObjRow(DASH_PFX+"r_ai_l",DASH_PFX+"r_ai_v",XR,cyR,CW,"▶ BREAKOUT WinRate", StringFormat("%.0f%%", g_scoreBreakout*100.0), CLR_LABEL, CLR_CYAN); cyR+=ROW_H-1;
   ObjBar(DASH_PFX+"aibar",XR+8,cyR,CW-16,g_scoreBreakout,CLR_CYAN); cyR+=BAR_H+SEC_GAP;

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
   
   double pf = (g_grossLoss > 0.0) ? g_grossProfit / g_grossLoss : 0.0;
   string pfStr = (g_grossLoss == 0.0 && g_grossProfit > 0.0) ? "∞" : StringFormat("%.2f", pf);
   color pf_clr = (pf >= 1.5 || g_grossLoss == 0.0) ? CLR_GREEN : (pf >= 1.0 ? CLR_YELLOW : CLR_RED);
   
   ObjRow(DASH_PFX+"r_trd_l",DASH_PFX+"r_trd_v",XR,cyR,CW,"Trades",    IntegerToString(g_totalTrades),  CLR_LABEL,CLR_WHITE);  cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_wr_l", DASH_PFX+"r_wr_v", XR,cyR,CW,"Win Rate",  StringFormat("%.1f%% (%d/%d)",wr,g_winningTrades,g_totalTrades),CLR_LABEL,wr_clr); cyR+=ROW_H-1;
   ObjBar(DASH_PFX+"wrbar",XR+8,cyR,CW-16,wr/100.0,wr_clr); cyR+=BAR_H+2;
   ObjRow(DASH_PFX+"r_pf_l", DASH_PFX+"r_pf_v", XR,cyR,CW,"Profit Factor", pfStr, CLR_LABEL, pf_clr); cyR+=ROW_H;
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
   
   ObjRow(DASH_PFX+"r_g5_l",DASH_PFX+"r_g5_v",XR,cyR,CW,"Time Filter",                                      lm_time?"BLOCKED":"OPEN",CLR_LABEL,lm_time?CLR_YELLOW:CLR_GREEN); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g6_l",DASH_PFX+"r_g6_v",XR,cyR,CW,"Cooldown",    lm_cd?StringFormat("WAIT %ds",cd_left):"Ready",CLR_LABEL,lm_cd?CLR_ORANGE:CLR_GREEN); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g7_l",DASH_PFX+"r_g7_v",XR,cyR,CW,StringFormat("Spread %dpts",InpMaxSpreadPts),      lm_sprd?"✗ HIGH":"✓ OK", CLR_LABEL,lm_sprd?CLR_RED:CLR_GREEN);      cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g8_l",DASH_PFX+"r_g8_v",XR,cyR,CW,StringFormat("Hard SL $%.1f",InpStopLossUsd),      InpStopLossUsd>0?"ON":"OFF", CLR_LABEL, InpStopLossUsd>0?CLR_CYAN:CLR_LABEL); cyR+=ROW_H;
   ObjRow(DASH_PFX+"r_g9_l",DASH_PFX+"r_g9_v",XR,cyR,CW,"Trailing",
          InpTrailingEnable?StringFormat("ON trig=$%.1f",InpTrailingTriggerUsd):"OFF",
          CLR_LABEL,InpTrailingEnable?CLR_CYAN:CLR_LABEL); cyR+=ROW_H+SEC_GAP;

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
   ObjLabel(DASH_PFX+"title",InpDashX+12,InpDashY+5,"ZERITH XAU BREAKOUT v18.00",CLR_TITLE,10,DASH_FONT_BOLD);
   ObjLabel(DASH_PFX+"sub",  InpDashX+DASH_W-12,InpDashY+6,Symbol()+"  ONE-SHOT MT5",CLR_LABEL,8,DASH_FONT,ANCHOR_RIGHT);
   ChartRedraw();
}
//+------------------------------------------------------------------+
