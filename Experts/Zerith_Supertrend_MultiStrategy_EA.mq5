//+------------------------------------------------------------------+
//|                                   Quantum_Queen_Supertrend_EA.mq5 |
//|        Quantum Queen X Core + Supertrend Trend Filter + Grid Pro |
//|                                       https://www.mql5.com       |
//+------------------------------------------------------------------+
#property copyright "Quantum Queen X (Supertrend & Smart Grid Edition)"
#property version   "4.50"
#property description "Quantum Queen X Core with Supertrend Trend Filter & Smart ATR Recovery Grid"
#property strict 

#include <Trade/Trade.mqh>

//--- Enums
enum QQ_LOT_MODE
  {
   QQ_LOT_AUTOMATIC=0,         // Automatic
   QQ_LOT_FIXED=1,             // Fixed
   QQ_LOT_FIXED_PER_BALANCE=2  // Fixed per balance
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
   QQ_PRESET_CUSTOM=6          // Custom
  };

enum QQ_GRID_MODE
  {
   QQ_GRID_SMART_ATR=0,        // Smart Recovery Grid (Dynamic ATR Spacing & Basket TP)
   QQ_GRID_ORIGINAL=1          // Original Source Portfolio Grid (Concurrent Multi-Strategy)
  };

enum QQ_TP_MODE
  {
   QQ_TP_ORIGINAL_HARD=0,      // Original Hard TP (Broker Server TP - Standard)
   QQ_TP_VISUAL_CANDLE=1,      // Visual TP (Candle Close Beyond TP Level)
   QQ_TP_BASKET_AVERAGE=2,     // Basket Average TP (Combined Weighted Average)
   QQ_TP_HYBRID=3              // Hybrid (Hard TP on single, Basket TP on grid)
  };

enum QQ_DD_MODE
  {
   QQ_DD_OFF=0,               // Off
   QQ_DD_PERCENT_CONTINUE=1,  // [Percent] Close then continue
   QQ_DD_PERCENT_REMOVE=2,    // [Percent] Close then remove
   QQ_DD_PERCENT_ALERT=3,     // [Percent] Terminal alert
   QQ_DD_MONEY_CONTINUE=4,    // [Money] Close then continue
   QQ_DD_MONEY_REMOVE=5,      // [Money] Close then remove
   QQ_DD_MONEY_ALERT=6        // [Money] Terminal alert
  };

enum QQ_DIRECTION_MODE
  {
   QQ_DIRECTION_BUY_ONLY=0,     // Buy only
   QQ_DIRECTION_SELL_ONLY=1,    // Sell only
   QQ_DIRECTION_PER_STRATEGY=2, // Both directions (per strategy)
   QQ_DIRECTION_DYNAMIC_ST=3    // Dynamic (Strictly Follows Supertrend Direction)
  };

enum QQ_BINARY_OPTION
  {
   QQ_OPTION_ON=0,   // On
   QQ_OPTION_OFF=1   // Off
  };

enum QQ_HOUR_OF_DAY
  {
   QQ_HOUR_00=0, QQ_HOUR_01=1, QQ_HOUR_02=2, QQ_HOUR_03=3, QQ_HOUR_04=4, QQ_HOUR_05=5,
   QQ_HOUR_06=6, QQ_HOUR_07=7, QQ_HOUR_08=8, QQ_HOUR_09=9, QQ_HOUR_10=10, QQ_HOUR_11=11,
   QQ_HOUR_12=12, QQ_HOUR_13=13, QQ_HOUR_14=14, QQ_HOUR_15=15, QQ_HOUR_16=16, QQ_HOUR_17=17,
   QQ_HOUR_18=18, QQ_HOUR_19=19, QQ_HOUR_20=20, QQ_HOUR_21=21, QQ_HOUR_22=22, QQ_HOUR_23=23
  };

//--- Input Parameters
input string            InpNoteName="Quantum Queen MT5 v4.5 (Supertrend + Grid Pro)"; // Name:
input string            InpNoteOverview="Quantum Queen Core + Supertrend & Advanced Risk Control"; // Overview:

input group ">>>> 1. Supertrend Trend Filter"
input bool              InpUseSupertrend=true; // Enable Supertrend Trend Filter
input int               InpST_AtrPeriod=10; // Supertrend ATR Period
input double            InpST_Multiplier=3.0; // Supertrend Multiplier
input ENUM_TIMEFRAMES   InpST_Timeframe=PERIOD_CURRENT; // Supertrend Timeframe
input bool              InpCloseOnSTFlip=false; // Close positions on Supertrend Flip

input group ">>>> 2. Grid Management & Recovery"
input QQ_GRID_MODE      InpGridMode=QQ_GRID_SMART_ATR; // Grid Mode (Smart ATR vs Original)
input int               InpMaxOrders=100; // Max Orders Allowed per Basket (e.g. 100)
input double            InpGridAtrMultiplier=1.0; // Grid Step ATR Multiplier
input double            InpGridBaseDistance=200.0; // Grid Step Base Distance (Points)
input double            InpGridLotMultiplier=1.2; // Lot Multiplier for Recovery Orders
input bool              InpCutLossOnMaxStep=true; // Hard Cut-Loss on (MaxOrders + 1) Step

input group ">>>> 3. Profit & Take Profit Modes"
input QQ_TP_MODE        InpTPMode=QQ_TP_ORIGINAL_HARD; // Take Profit Mode (Original / Visual / Basket)
input int               InpTakeProfit=500; // Take Profit (Points, 0=off)
input int               InpBasketTakeProfit=250; // Basket Take Profit (Points above Avg Price, 0=off)
input ENUM_TIMEFRAMES   InpVisualTP_TF=PERIOD_CURRENT; // Visual TP Evaluation Timeframe

input group ">>>> 4. Stop Loss, Break-Even & Trailing Stop"
input int               InpStopLoss=0; // Stop Loss (Points, 0=off)
input int               InpBreakEvenStart=0; // Break-even activation (Points profit, 0=off)
input int               InpBreakEvenOffset=10; // Break-even offset (Points above entry)
input int               InpTrailingStart=0; // Trailing Stop activation (Points profit, 0=off)
input int               InpTrailingStep=100; // Trailing Stop distance (Points)

input group ">>>> 5. General Settings"
input QQ_BINARY_OPTION  InpPause=QQ_OPTION_OFF; // Start paused
input QQ_LOT_MODE       InpLotsCalc=QQ_LOT_AUTOMATIC; // Lot sizing mode
input QQ_RISK_LEVEL     InpAutoLotsValue=QQ_RISK_MEDIUM; // Automatic lot risk level
input double            InpLotsFixed=0.01; // Fixed Lot
input double            InpLotsFixedBalance=500.0; // Fixed per balance unit
input int               InpOrdersMaxTotal=100; // Max Total Orders Across Entire Account
input QQ_DD_MODE        InpDDMode=QQ_DD_OFF; // Drawdown control mode
input double            InpDDValue=0.0; // Drawdown threshold
input QQ_BINARY_OPTION  InpMQID=QQ_OPTION_OFF; // MQID push notifications
input long              InpMagicNumber=1234; // Magic number
input int               InpSpread=100; // Max spread (points)
input int               InpSlippage=100; // Max slippage (points)
input string            InpTradeCommentRaw="QQ_ST_"; // Trade comment
input QQ_DIRECTION_MODE InpTradingDirectionType=QQ_DIRECTION_PER_STRATEGY; // Trading direction type

input group ">>>> 6. Presets & Strategies"
input QQ_PRESET         InpSets=QQ_PRESET_ICVT_HIGH; // Preset selection
input QQ_BINARY_OPTION  InpS01Strategy=QQ_OPTION_ON; // Strategy 1
input QQ_BINARY_OPTION  InpS02Strategy=QQ_OPTION_ON; // Strategy 2
input QQ_BINARY_OPTION  InpS03Strategy=QQ_OPTION_ON; // Strategy 3
input QQ_BINARY_OPTION  InpS04Strategy=QQ_OPTION_ON; // Strategy 4
input QQ_BINARY_OPTION  InpS05Strategy=QQ_OPTION_ON; // Strategy 5
input QQ_BINARY_OPTION  InpS06Strategy=QQ_OPTION_ON; // Strategy 6
input QQ_BINARY_OPTION  InpS07Strategy=QQ_OPTION_OFF; // Strategy 7
input QQ_BINARY_OPTION  InpS08Strategy=QQ_OPTION_ON; // Strategy 8
input QQ_BINARY_OPTION  InpS09Strategy=QQ_OPTION_ON; // Strategy 9
input QQ_BINARY_OPTION  InpS10Strategy=QQ_OPTION_ON; // Strategy 10
input QQ_BINARY_OPTION  InpS11Strategy=QQ_OPTION_OFF; // Strategy 11
input QQ_BINARY_OPTION  InpS12Strategy=QQ_OPTION_ON; // Strategy 12

input group ">>>> 7. Trading Schedule & Hours"
input bool              InpUseHourFilter=false; // Use Original Hour Window Filter (False = Supertrend Controls)
input bool              InpUseNfpFridayFilter=true; // No entries on NFP Friday
input bool              InpTradingFridayNight=true; // Close trading Friday night
input QQ_HOUR_OF_DAY    InpTradingFridayNightHour=QQ_HOUR_22; // Friday night close hour
input bool              InpUseYearEndPause=false; // Year-end pause (Dec 15 - Jan 15)
input bool              InpTradeOnMonday=true; // Trade on Monday
input bool              InpTradeOnTuesday=true; // Trade on Tuesday
input bool              InpTradeOnWednesday=true; // Trade on Wednesday
input bool              InpTradeOnThursday=true; // Trade on Thursday
input bool              InpTradeOnFriday=true; // Trade on Friday
input bool              InpTradeOnSaturday=true; // Trade on Saturday
input bool              InpTradeOnSunday=true; // Trade on Sunday

input group ">>>> 8. Panel & Display Settings"
input QQ_BINARY_OPTION  InpPanel=QQ_OPTION_ON; // Show panel
input string            InpFont="Trebuchet MS"; // Panel font
input int               InpFontSize=8; // Font size
input string            InpComment="Quantum Queen ST v4.5"; // Panel comment

//--- Constants & Variables
static const string QQ_NAME="Quantum Queen ST v4.5";
static const string QQ_OVERVIEW="Supertrend & Smart Grid Enhanced Core";
static const string QQ_PANEL_PREFIX="QQX_";
#define QQ_STRATEGY_COUNT 12

CTrade   g_trade;
bool     g_paused=false;
bool     g_remove_after_risk=false;
bool     g_panel_collapsed=false;
string   g_dialog_prefix="";
bool     g_drawdown_triggered=false;
datetime g_last_panel_update=0;
datetime g_last_visual_tp_bar=0;
long     g_last_bar_time[QQ_STRATEGY_COUNT];
int      g_demarker_a[QQ_STRATEGY_COUNT];
int      g_demarker_b[QQ_STRATEGY_COUNT];
int      g_handle_atr=INVALID_HANDLE;
int      g_current_st_trend=0; // 1 = Bullish, -1 = Bearish
double   g_st_line=0.0;

//+------------------------------------------------------------------+
//| Strategy Tag Name                                                |
//+------------------------------------------------------------------+
string StrategyTag(const int slot)
  {
   static string tags[12]=
     {
      "[T1/Strategy1]","[T1/Strategy2]","[T2/Strategy3]","[T2/Strategy4]",
      "[T3/Strategy5]","[T3/Strategy6]","[T4/Strategy7]","[T4/Strategy8]",
      "[T5/Strategy9]","[T5/Strategy10]","[T6/Strategy11]","[T6/Strategy12]"
     };
   if(slot<0 || slot>=QQ_STRATEGY_COUNT)
      return "[Strategy ?]";
   return tags[slot];
  }

//+------------------------------------------------------------------+
//| Strategy Enabled Check                                           |
//+------------------------------------------------------------------+
bool StrategyEnabled(const int slot)
  {
   if(InpSets==QQ_PRESET_CUSTOM)
     {
      switch(slot)
        {
         case 0:  return InpS01Strategy==QQ_OPTION_ON;
         case 1:  return InpS02Strategy==QQ_OPTION_ON;
         case 2:  return InpS03Strategy==QQ_OPTION_ON;
         case 3:  return InpS04Strategy==QQ_OPTION_ON;
         case 4:  return InpS05Strategy==QQ_OPTION_ON;
         case 5:  return InpS06Strategy==QQ_OPTION_ON;
         case 6:  return InpS07Strategy==QQ_OPTION_ON;
         case 7:  return InpS08Strategy==QQ_OPTION_ON;
         case 8:  return InpS09Strategy==QQ_OPTION_ON;
         case 9:  return InpS10Strategy==QQ_OPTION_ON;
         case 10: return InpS11Strategy==QQ_OPTION_ON;
         case 11: return InpS12Strategy==QQ_OPTION_ON;
        }
     }
   if(InpSets==QQ_PRESET_ICVT_HIGH)
      return slot==0 || slot==1 || slot==2 || slot==4 || slot==5 ||
             slot==7 || slot==8 || slot==9 || slot==11;
   if(InpSets==QQ_PRESET_ICVT_MEDIUM)
      return slot==0 || slot==2 || slot==7 || slot==8 || slot==11;
   if(InpSets==QQ_PRESET_ICVT_LOW)
      return slot==0 || slot==3 || slot==4 || slot==6 || slot==7 ||
             slot==8 || slot==9;
   if(InpSets==QQ_PRESET_ROBO_ECN)
      return slot==0 || slot==2 || slot==3 || slot==4 || slot==5 ||
             slot==7 || slot==8 || slot==9 || slot==11;
   if(InpSets==QQ_PRESET_FUSION_ZERO)
      return slot==0 || slot==2 || slot==3 || slot==4 || slot==7 ||
             slot==8 || slot==11;
   if(InpSets==QQ_PRESET_ALL_STRATEGIES)
      return true;
   return false;
  }

//+------------------------------------------------------------------+
//| Strategy Direction Bias                                          |
//+------------------------------------------------------------------+
int StrategyDirection(const int slot)
  {
   if(InpTradingDirectionType==QQ_DIRECTION_BUY_ONLY)
      return 1;
   if(InpTradingDirectionType==QQ_DIRECTION_SELL_ONLY)
      return -1;
   if(InpTradingDirectionType==QQ_DIRECTION_DYNAMIC_ST)
      return g_current_st_trend;
   if(slot==4 || slot==5 || slot==10 || slot==11)
      return -1;
   return 1;
  }

long StrategyMagic(const int slot)
  {
   return InpMagicNumber;
  }

string SafeComment(const int slot, const int order_idx=0)
  {
   string base=StringSubstr(InpTradeCommentRaw,0,15);
   if(order_idx==0)
      return base+StrategyTag(slot);
   return base+StringFormat("[S%d_R%d]", slot+1, order_idx);
  }

//+------------------------------------------------------------------+
//| Dynamic Grid Step Points: (ATR * Mult) + Base Dist               |
//+------------------------------------------------------------------+
double GetGridStepPoints()
  {
   if(g_handle_atr==INVALID_HANDLE)
      return InpGridBaseDistance;

   double atr[];
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(g_handle_atr,0,0,1,atr)<1)
      return InpGridBaseDistance;

   double point=_Point;
   if(point<=0.0) point=0.01;

   double atr_pts=atr[0]/point;
   double step=(atr_pts*InpGridAtrMultiplier)+InpGridBaseDistance;
   return MathMax(step, InpGridBaseDistance);
  }

//+------------------------------------------------------------------+
//| Trading Environment Check                                        |
//+------------------------------------------------------------------+
bool TradingEnvironmentReady()
  {
   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;
   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) return false;
   return true;
  }

double NormalizeVolume(const double volume)
  {
   double min_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_lot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) step=0.01;
   double value=MathFloor(volume/step)*step;
   if(value<min_lot) value=min_lot;
   if(value>max_lot) value=max_lot;
   return NormalizeDouble(value,2);
  }

double NormalizeRecoveredPrice(const double price)
  {
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(price,digits);
  }

//+------------------------------------------------------------------+
//| Calculate Volume with optional recovery level multiplier         |
//+------------------------------------------------------------------+
double CalculateVolume(const int order_level=0)
  {
   double base_lot=InpLotsFixed;
   if(InpLotsCalc==QQ_LOT_FIXED_PER_BALANCE)
     {
      double unit=MathMax(1.0,InpLotsFixedBalance);
      base_lot=AccountInfoDouble(ACCOUNT_BALANCE)/unit*InpLotsFixed;
     }
   else if(InpLotsCalc==QQ_LOT_AUTOMATIC)
     {
      static double divisor_high[7]={2000.0,1200.0,800.0,600.0,500.0,400.0,300.0};
      static double divisor_other[7]={2000.0,1500.0,1000.0,800.0,600.0,550.0,400.0};
      int level=(int)InpAutoLotsValue;
      if(level<0 || level>6) level=3;
      double divisor=divisor_high[level];
      if(InpSets>=QQ_PRESET_ICVT_LOW)
         divisor=divisor_other[level];
      if(InpSets==QQ_PRESET_FUSION_ZERO && level==6)
         divisor=300.0;
      base_lot=AccountInfoDouble(ACCOUNT_BALANCE)/divisor*0.01;
     }

   if(order_level>0 && InpGridLotMultiplier>1.0)
      base_lot=base_lot*MathPow(InpGridLotMultiplier, order_level);

   return NormalizeVolume(base_lot);
  }

//+------------------------------------------------------------------+
//| Check Position Ownership                                         |
//+------------------------------------------------------------------+
bool IsOurPosition(const ulong ticket,const int slot=-1)
  {
   if(ticket==0 || !PositionSelectByTicket(ticket))
      return false;
   long magic=PositionGetInteger(POSITION_MAGIC);
   if(magic!=InpMagicNumber || PositionGetString(POSITION_SYMBOL)!=_Symbol)
      return false;
   if(slot>=0)
     {
      string comment=PositionGetString(POSITION_COMMENT);
      string tag=StrategyTag(slot);
      string slot_prefix=StringFormat("S%d", slot+1);
      return (StringFind(comment,tag)>=0 || StringFind(comment,slot_prefix)>=0);
     }
   return true;
  }

int StrategyPositionCount(const int slot)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(IsOurPosition(ticket,slot))
         count++;
     }
   return count;
  }

int TotalOpenOrdersCount()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(IsOurPosition(ticket))
         count++;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Get Strategy Basket Stats                                        |
//+------------------------------------------------------------------+
int GetStrategyBasketStats(const int slot, double &avg_price, double &total_vol, double &latest_price, long &pos_type)
  {
   int count=0;
   double weighted_sum=0.0;
   total_vol=0.0;
   avg_price=0.0;
   latest_price=0.0;
   datetime latest_time=0;
   pos_type=-1;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPosition(ticket,slot))
         continue;

      count++;
      double vol=PositionGetDouble(POSITION_VOLUME);
      double price=PositionGetDouble(POSITION_PRICE_OPEN);
      pos_type=PositionGetInteger(POSITION_TYPE);

      weighted_sum+=price*vol;
      total_vol+=vol;

      datetime op_time=(datetime)PositionGetInteger(POSITION_TIME);
      if(op_time>=latest_time)
        {
         latest_time=op_time;
         latest_price=price;
        }
     }

   if(total_vol>0.0)
      avg_price=weighted_sum/total_vol;

   return count;
  }

double StrategyProfit(const int slot)
  {
   double value=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPosition(ticket,slot))
         continue;
      value+=PositionGetDouble(POSITION_PROFIT);
      value+=PositionGetDouble(POSITION_SWAP);
     }
   return value;
  }

double TotalStrategyProfit()
  {
   double value=0.0;
   for(int slot=0;slot<QQ_STRATEGY_COUNT;slot++)
      value+=StrategyProfit(slot);
   return value;
  }

bool CloseStrategy(const int slot,const string reason)
  {
   bool selected=false;
   bool closed=true;
   g_trade.SetExpertMagicNumber(StrategyMagic(slot));
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPosition(ticket,slot))
         continue;
      selected=true;
      int size=ArraySize(tickets);
      ArrayResize(tickets,size+1);
      tickets[size]=ticket;
     }
   ArraySort(tickets);
   for(int i=0;i<ArraySize(tickets);i++)
     {
      ulong ticket=tickets[i];
      if(!g_trade.PositionClose(ticket))
        {
         closed=false;
         PrintFormat("%s close failed ticket=%I64u retcode=%u err=%d",
                     reason,ticket,g_trade.ResultRetcode(),GetLastError());
        }
     }
   PrintFormat("[CloseStrategy] slot=%d reason=%s success=%s",
               slot+1,reason,(closed ? "yes" : "no"));
   return selected && closed;
  }

bool CloseAllStrategies(const string reason)
  {
   bool result=true;
   for(int slot=0;slot<QQ_STRATEGY_COUNT;slot++)
     {
      if(StrategyPositionCount(slot)>0 && !CloseStrategy(slot,reason))
         result=false;
     }
   return result;
  }

void NotifyRisk(const string text)
  {
   Print(text);
   if(InpMQID==QQ_OPTION_ON && !SendNotification(text))
      PrintFormat("Quantum Queen: notification not sent (%d)",GetLastError());
  }

void ApplyDrawdownControl()
  {
   if(InpDDMode==QQ_DD_OFF || InpDDValue<=0.0)
     {
      g_drawdown_triggered=false;
      return;
     }
   double floating=TotalStrategyProfit();
   if(floating>=0.0)
     {
      g_drawdown_triggered=false;
      return;
     }
   bool percent_mode=((int)InpDDMode>=1 && (int)InpDDMode<=3);
   double measured=-floating;
   string unit=AccountInfoString(ACCOUNT_CURRENCY);
   if(percent_mode)
     {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance<=0.0) return;
      measured=(-floating/balance)*100.0;
      unit="%";
     }
   if(measured<InpDDValue)
     {
      g_drawdown_triggered=false;
      return;
     }
   string text=StringFormat("Drawdown threshold reached: %.2f%s (floating P/L %.2f %s)",
                            InpDDValue,unit,floating,AccountInfoString(ACCOUNT_CURRENCY));
   bool first_trigger=!g_drawdown_triggered;
   if(first_trigger)
     {
      Print("Drawdown alert: threshold breached");
      NotifyRisk(text);
     }
   g_drawdown_triggered=true;
   if(InpDDMode==QQ_DD_PERCENT_ALERT || InpDDMode==QQ_DD_MONEY_ALERT)
     {
      if(first_trigger && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION))
         Alert(text);
      return;
     }
   CloseAllStrategies("Drawdown");
   if(InpDDMode==QQ_DD_PERCENT_REMOVE || InpDDMode==QQ_DD_MONEY_REMOVE)
      g_remove_after_risk=true;
  }

bool RecoveredSpreadAllowsEntry()
  {
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double point=SymbolInfoDouble(_Symbol,SYMBOL_POINT);
   if(point<=0.0) return false;
   return ((double)InpSpread >= (ask-bid)/point);
  }

bool RecoveredMarginAllowsEntry(const int direction,const double volume)
  {
   double free_margin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free_margin<0.0) return false;
   double price=SymbolInfoDouble(_Symbol, direction>0 ? SYMBOL_ASK : SYMBOL_BID);
   double required_margin=0.0;
   ENUM_ORDER_TYPE order_type=(direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   if(!OrderCalcMargin(order_type,_Symbol,volume,price,required_margin))
      return false;
   return (required_margin<=free_margin);
  }

//+------------------------------------------------------------------+
//| Update Supertrend Direction                                      |
//+------------------------------------------------------------------+
void UpdateSupertrend()
  {
   if(!InpUseSupertrend)
     {
      g_current_st_trend=1;
      return;
     }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, InpST_Timeframe, 0, 50, rates) < 50)
      return;

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_handle_atr, 0, 0, 50, atr) < 50)
      return;

   double upper_band = 0.0, lower_band = 0.0;
   int trend = 1;
   double prev_st = 0.0;

   for(int i = 40; i >= 0; i--)
     {
      double median = (rates[i].high + rates[i].low) / 2.0;
      double basic_upper = median + InpST_Multiplier * atr[i];
      double basic_lower = median - InpST_Multiplier * atr[i];

      if(i == 40)
        {
         upper_band = basic_upper;
         lower_band = basic_lower;
         trend = (rates[i].close > upper_band) ? 1 : -1;
         prev_st = (trend == 1) ? lower_band : upper_band;
         continue;
        }

      if(basic_lower > lower_band || rates[i + 1].close < lower_band)
         lower_band = basic_lower;

      if(basic_upper < upper_band || rates[i + 1].close > upper_band)
         upper_band = basic_upper;

      if(trend == 1 && rates[i].close < lower_band)
         trend = -1;
      else if(trend == -1 && rates[i].close > upper_band)
         trend = 1;

      prev_st = (trend == 1) ? lower_band : upper_band;
     }

   if(InpCloseOnSTFlip && g_current_st_trend != 0 && g_current_st_trend != trend)
     {
      PrintFormat("[ST Flip] Trend changed from %s to %s -> Closing opposing positions",
                  (g_current_st_trend == 1 ? "BULL" : "BEAR"), (trend == 1 ? "BULL" : "BEAR"));
      for(int slot=0; slot<QQ_STRATEGY_COUNT; slot++)
        {
         double avg_p, tot_v, lat_p; long p_type;
         if(GetStrategyBasketStats(slot, avg_p, tot_v, lat_p, p_type)>0)
           {
            if((g_current_st_trend==1 && p_type==POSITION_TYPE_BUY) ||
               (g_current_st_trend==-1 && p_type==POSITION_TYPE_SELL))
               CloseStrategy(slot, "Supertrend Flip");
           }
        }
     }

   g_current_st_trend = trend;
   g_st_line = prev_st;
  }

//+------------------------------------------------------------------+
//| Apply BreakEven and Trailing Stop                                |
//+------------------------------------------------------------------+
void ApplyBreakEvenAndTrailing(const int slot)
  {
   if(InpBreakEvenStart<=0 && InpTrailingStart<=0)
      return;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurPosition(ticket,slot))
         continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open_price=PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl=PositionGetDouble(POSITION_SL);
      double current_tp=PositionGetDouble(POSITION_TP);
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick)) return;

      double new_sl=current_sl;
      if(type==POSITION_TYPE_BUY)
        {
         double profit_pts=(tick.bid-open_price)/_Point;
         if(InpBreakEvenStart>0 && profit_pts>=InpBreakEvenStart)
           {
            double be_level=NormalizeRecoveredPrice(open_price+InpBreakEvenOffset*_Point);
            if(new_sl<be_level || new_sl==0.0) new_sl=be_level;
           }
         if(InpTrailingStart>0 && InpTrailingStep>0 && profit_pts>=InpTrailingStart)
           {
            double trail_level=NormalizeRecoveredPrice(tick.bid-InpTrailingStep*_Point);
            if(trail_level>new_sl) new_sl=trail_level;
           }
        }
      else if(type==POSITION_TYPE_SELL)
        {
         double profit_pts=(open_price-tick.ask)/_Point;
         if(InpBreakEvenStart>0 && profit_pts>=InpBreakEvenStart)
           {
            double be_level=NormalizeRecoveredPrice(open_price-InpBreakEvenOffset*_Point);
            if(current_sl<=0.0 || new_sl>be_level) new_sl=be_level;
           }
         if(InpTrailingStart>0 && InpTrailingStep>0 && profit_pts>=InpTrailingStart)
           {
            double trail_level=NormalizeRecoveredPrice(tick.ask+InpTrailingStep*_Point);
            if(current_sl<=0.0 || trail_level<new_sl) new_sl=trail_level;
           }
        }

      if(new_sl!=current_sl && new_sl>0.0)
        {
         g_trade.SetExpertMagicNumber(StrategyMagic(slot));
         g_trade.PositionModify(ticket,new_sl,current_tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Check Visual Take Profit on Candle Close                         |
//+------------------------------------------------------------------+
void CheckVisualTakeProfit(const int slot, const double avg_price, const long pos_type, const int count)
  {
   if(InpTPMode!=QQ_TP_VISUAL_CANDLE && (InpTPMode!=QQ_TP_HYBRID && InpTPMode!=QQ_TP_BASKET_AVERAGE))
      return;

   datetime current_bar=iTime(_Symbol,InpVisualTP_TF,0);
   if(current_bar==g_last_visual_tp_bar)
      return;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,InpVisualTP_TF,1,1,rates)<1)
      return;

   double last_close=rates[0].close;
   double target_pts=(count>=2 && InpBasketTakeProfit>0) ? InpBasketTakeProfit : InpTakeProfit;
   if(target_pts<=0) return;

   double target_tp=(pos_type==POSITION_TYPE_BUY) ?
                    NormalizeRecoveredPrice(avg_price + target_pts * _Point) :
                    NormalizeRecoveredPrice(avg_price - target_pts * _Point);

   bool visual_hit=(pos_type==POSITION_TYPE_BUY && last_close>=target_tp) ||
                   (pos_type==POSITION_TYPE_SELL && last_close<=target_tp);

   if(visual_hit)
     {
      PrintFormat("🎯 [Visual TP Hit] Strategy %d closed on bar close (Close: %.2f | Target TP: %.2f)",
                  slot+1, last_close, target_tp);
      CloseStrategy(slot, "Visual Candle-Close TP");
      g_last_visual_tp_bar=current_bar;
     }
  }

//+------------------------------------------------------------------+
//| Manage Strategy Positions (Grid Execution & Precise Cut-Loss)    |
//+------------------------------------------------------------------+
void ManageStrategy(const int slot)
  {
   if(!StrategyEnabled(slot)) return;

   double avg_price=0.0, total_vol=0.0, latest_price=0.0;
   long pos_type=-1;
   int count=GetStrategyBasketStats(slot, avg_price, total_vol, latest_price, pos_type);
   if(count<=0) return;

   double grid_step_pts = GetGridStepPoints();
   double step_dist = grid_step_pts * _Point;

   // -------------------------------------------------------------
   // 1. Take Profit Management (Basket / Visual / Hard)
   // -------------------------------------------------------------
   // A. Basket Average TP
   if(count>=2 && InpBasketTakeProfit>0 && (InpTPMode==QQ_TP_BASKET_AVERAGE || InpTPMode==QQ_TP_HYBRID || InpTPMode==QQ_TP_ORIGINAL_HARD))
     {
      double basket_tp = (pos_type==POSITION_TYPE_BUY) ?
                         NormalizeRecoveredPrice(avg_price + InpBasketTakeProfit * _Point) :
                         NormalizeRecoveredPrice(avg_price - InpBasketTakeProfit * _Point);

      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      bool basket_tp_hit = (pos_type==POSITION_TYPE_BUY && bid>=basket_tp) ||
                           (pos_type==POSITION_TYPE_SELL && ask<=basket_tp);

      if(basket_tp_hit)
        {
         PrintFormat("🎯 [Basket TP] Strategy %d closed %d positions at target %.2f (Avg: %.2f)",
                     slot+1, count, basket_tp, avg_price);
         CloseStrategy(slot, "Basket Take Profit");
         return;
        }
     }

   // B. Visual Candle-Close TP
   if(InpTPMode==QQ_TP_VISUAL_CANDLE)
     {
      CheckVisualTakeProfit(slot, avg_price, pos_type, count);
     }

   // -------------------------------------------------------------
   // 2. Smart Recovery Grid & Accurate (MaxOrders + 1) Step Cut-Loss
   // -------------------------------------------------------------
   if(InpGridMode==QQ_GRID_SMART_ATR)
     {
      if(pos_type==POSITION_TYPE_BUY)
        {
         double next_trigger_price = latest_price - step_dist;
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

         if(bid <= next_trigger_price)
           {
            // Case A: Still within allowed MaxOrders -> Open Recovery Order #count
            if(count < InpMaxOrders)
              {
               double rec_vol = CalculateVolume(count);
               double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
               g_trade.SetExpertMagicNumber(StrategyMagic(slot));
               
               double sl_price = (InpStopLoss > 0) ? NormalizeRecoveredPrice(ask - InpStopLoss * _Point) : 0.0;
               double tp_price = (InpTakeProfit > 0 && InpTPMode == QQ_TP_ORIGINAL_HARD) ? NormalizeRecoveredPrice(ask + InpTakeProfit * _Point) : 0.0;

               if(g_trade.Buy(rec_vol, _Symbol, ask, sl_price, tp_price, SafeComment(slot, count)))
                 {
                  PrintFormat("🛡️ [Smart Grid] Opened Recovery BUY #%d for Strategy %d at %.2f (Step: %.1f pts)",
                              count, slot+1, ask, grid_step_pts);
                 }
              }
            // Case B: Already opened ALL InpMaxOrders -> Price dropped another step (MaxOrders + 1) -> CUT LOSS!
            else if(count >= InpMaxOrders)
              {
               if(InpCutLossOnMaxStep)
                 {
                  PrintFormat("🚨 [Grid Cut-Loss] Strategy %d reached MaxOrders (%d) + 1 step distance (%.2f <= %.2f) -> Closing all %d positions!",
                              slot+1, InpMaxOrders, bid, next_trigger_price, count);
                  CloseStrategy(slot, "Max Step Cut-Loss");
                  return;
                 }
              }
           }
        }
      else if(pos_type==POSITION_TYPE_SELL)
        {
         double next_trigger_price = latest_price + step_dist;
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

         if(ask >= next_trigger_price)
           {
            // Case A: Still within allowed MaxOrders -> Open Recovery Order #count
            if(count < InpMaxOrders)
              {
               double rec_vol = CalculateVolume(count);
               double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
               g_trade.SetExpertMagicNumber(StrategyMagic(slot));

               double sl_price = (InpStopLoss > 0) ? NormalizeRecoveredPrice(bid + InpStopLoss * _Point) : 0.0;
               double tp_price = (InpTakeProfit > 0 && InpTPMode == QQ_TP_ORIGINAL_HARD) ? NormalizeRecoveredPrice(bid - InpTakeProfit * _Point) : 0.0;

               if(g_trade.Sell(rec_vol, _Symbol, bid, sl_price, tp_price, SafeComment(slot, count)))
                 {
                  PrintFormat("🛡️ [Smart Grid] Opened Recovery SELL #%d for Strategy %d at %.2f (Step: %.1f pts)",
                              count, slot+1, bid, grid_step_pts);
                 }
              }
            // Case B: Already opened ALL InpMaxOrders -> Price rallied another step (MaxOrders + 1) -> CUT LOSS!
            else if(count >= InpMaxOrders)
              {
               if(InpCutLossOnMaxStep)
                 {
                  PrintFormat("🚨 [Grid Cut-Loss] Strategy %d reached MaxOrders (%d) + 1 step distance (%.2f >= %.2f) -> Closing all %d positions!",
                              slot+1, InpMaxOrders, ask, next_trigger_price, count);
                  CloseStrategy(slot, "Max Step Cut-Loss");
                  return;
                 }
              }
           }
        }
     }

   // -------------------------------------------------------------
   // 3. Original Portfolio Mode (Cut-Loss only when count >= InpMaxOrders)
   // -------------------------------------------------------------
   else if(InpGridMode==QQ_GRID_ORIGINAL)
     {
      if(InpCutLossOnMaxStep && count >= InpMaxOrders)
        {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

         if(pos_type==POSITION_TYPE_BUY && bid <= latest_price - step_dist)
           {
            PrintFormat("🚨 [Original Cut-Loss] Strategy %d reached MaxOrders (%d) + 1 step distance -> Closing basket!", slot+1, InpMaxOrders);
            CloseStrategy(slot, "Original Grid Max Step Cut-Loss");
            return;
           }
         if(pos_type==POSITION_TYPE_SELL && ask >= latest_price + step_dist)
           {
            PrintFormat("🚨 [Original Cut-Loss] Strategy %d reached MaxOrders (%d) + 1 step distance -> Closing basket!", slot+1, InpMaxOrders);
            CloseStrategy(slot, "Original Grid Max Step Cut-Loss");
            return;
           }
        }
     }

   // Apply BreakEven and Trailing Stop (Only runs if InpBreakEvenStart > 0 or InpTrailingStart > 0)
   ApplyBreakEvenAndTrailing(slot);
  }

//+------------------------------------------------------------------+
//| Schedule & Hour Filter Check                                     |
//+------------------------------------------------------------------+
bool ScheduleAllowsTrading()
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   bool day_allowed=false;
   switch(now.day_of_week)
     {
      case 0: day_allowed=InpTradeOnSunday; break;
      case 1: day_allowed=InpTradeOnMonday; break;
      case 2: day_allowed=InpTradeOnTuesday; break;
      case 3: day_allowed=InpTradeOnWednesday; break;
      case 4: day_allowed=InpTradeOnThursday; break;
      case 5: day_allowed=InpTradeOnFriday; break;
      case 6: day_allowed=InpTradeOnSaturday; break;
     }
   if(!day_allowed) return false;
   if(InpUseNfpFridayFilter && now.day_of_week==5 && now.day<8) return false;
   if(InpTradingFridayNight && now.day_of_week==5 && now.hour>=InpTradingFridayNightHour) return false;
   int mmdd=now.mon*100+now.day;
   if(InpUseYearEndPause && (mmdd<=115 || mmdd>=1215)) return false;
   return true;
  }

ENUM_TIMEFRAMES PrimaryTimeframe(const int slot)
  {
   static ENUM_TIMEFRAMES values[12]=
     {
      PERIOD_M6,PERIOD_M15,PERIOD_M15,PERIOD_M15,
      PERIOD_M5,PERIOD_M10,PERIOD_M5,PERIOD_M5,
      PERIOD_M12,PERIOD_M10,PERIOD_M10,PERIOD_M12
     };
   if(slot<0 || slot>=QQ_STRATEGY_COUNT) return PERIOD_CURRENT;
   return values[slot];
  }

bool StrategyHourAllowed(const int slot,const int hour)
  {
   if(!InpUseHourFilter)
      return true;

   switch(slot)
     {
      case 0:  return hour==22 || hour==23;
      case 1:  return hour==3;
      case 2:  return hour==22;
      case 3:  return hour==19;
      case 4:  return hour==0;
      case 5:  return hour==23;
      case 6:  return hour>=8 && hour<=10;
      case 7:  return hour>=6 && hour<=11;
      case 8:  return hour>=10 && hour<=13;
      case 9:  return hour==22;
      case 10: return hour>=4 && hour<=8;
      case 11: return hour==8 || hour==9;
     }
   return false;
  }

bool IsNewEligibleBar(const int slot)
  {
   MqlDateTime now;
   TimeToStruct(TimeCurrent(),now);
   if(!StrategyHourAllowed(slot,now.hour))
      return false;
   datetime bar=iTime(_Symbol,PrimaryTimeframe(slot),0);
   if(bar<=0 || bar==g_last_bar_time[slot])
      return false;
   g_last_bar_time[slot]=bar;
   return true;
  }

int DeMarkerDirection(const double value,const double upper,const double lower)
  {
   if(value>upper) return 1;
   if(value<lower) return -1;
   return 0;
  }

int RecoveredSignalProvider(const int slot)
  {
   if(slot<0 || slot>=QQ_STRATEGY_COUNT ||
      g_demarker_a[slot]==INVALID_HANDLE || g_demarker_b[slot]==INVALID_HANDLE)
      return 0;
   double a[2],b[2];
   if(CopyBuffer(g_demarker_a[slot],0,0,2,a)!=2) return 0;
   if(CopyBuffer(g_demarker_b[slot],0,0,2,b)!=2) return 0;

   static double upper_a[12]={0.7,0.7,0.7,0.7,0.7,0.7,0.9,0.5,0.9,0.7,0.7,0.7};
   static double lower_a[12]={0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.1};
   static double upper_b[12]={0.7,0.7,0.7,0.7,0.7,0.7,0.7,0.9,0.9,0.9,0.7,0.7};
   static double lower_b[12]={0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3,0.3};

   int da=DeMarkerDirection(a[0],upper_a[slot],lower_a[slot]);
   int db=DeMarkerDirection(b[0],upper_b[slot],lower_b[slot]);
   return (da!=0 && da==db ? da : 0);
  }

//+------------------------------------------------------------------+
//| Process Initial Strategy Signals (Follows Supertrend Exactly)    |
//+------------------------------------------------------------------+
void ProcessStrategy(const int slot)
  {
   if(!StrategyEnabled(slot)) return;
   if(!ScheduleAllowsTrading() || g_paused) return;
   if(!IsNewEligibleBar(slot)) return;

   int signal=RecoveredSignalProvider(slot);
   if(signal==0) return;

   int expected=StrategyDirection(slot);
   if((signal>0 && expected<0) || (signal<0 && expected>0)) return;

   // Strict Supertrend Filter Check
   if(InpUseSupertrend)
     {
      if(signal>0 && g_current_st_trend!=1) return; // Block BUY if ST is Bearish
      if(signal<0 && g_current_st_trend!=-1) return; // Block SELL if ST is Bullish
     }

   if(StrategyPositionCount(slot)>0) return;
   if(TotalOpenOrdersCount()>=InpOrdersMaxTotal) return;

   double volume=CalculateVolume(0);
   if(volume<=0.0) return;

   if(!RecoveredSpreadAllowsEntry() || !RecoveredMarginAllowsEntry(signal,volume))
      return;

   g_trade.SetExpertMagicNumber(StrategyMagic(slot));
   g_trade.SetDeviationInPoints((ulong)MathMax(0,InpSlippage));

   double sl_price=0.0;
   double tp_price=0.0;
   bool opened=false;

   if(signal>0)
     {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(InpStopLoss>0) sl_price=NormalizeRecoveredPrice(ask-InpStopLoss*_Point);
      if(InpTakeProfit>0 && (InpTPMode==QQ_TP_ORIGINAL_HARD || InpTPMode==QQ_TP_HYBRID)) 
         tp_price=NormalizeRecoveredPrice(ask+InpTakeProfit*_Point);
      opened=g_trade.Buy(volume,_Symbol,ask,sl_price,tp_price,SafeComment(slot));
     }
   else
     {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      if(InpStopLoss>0) sl_price=NormalizeRecoveredPrice(bid+InpStopLoss*_Point);
      if(InpTakeProfit>0 && (InpTPMode==QQ_TP_ORIGINAL_HARD || InpTPMode==QQ_TP_HYBRID)) 
         tp_price=NormalizeRecoveredPrice(bid-InpTakeProfit*_Point);
      opened=g_trade.Sell(volume,_Symbol,bid,sl_price,tp_price,SafeComment(slot));
     }

   if(opened)
      PrintFormat("🎯 [QQ Signal] Strategy %d opened %s lot: %.2f (ST: %s)",
                  slot+1, (signal>0 ? "BUY" : "SELL"), volume, (g_current_st_trend==1 ? "BULL" : "BEAR"));
  }

//+------------------------------------------------------------------+
//| Panel UI Creation & Management (Exact Authentic QQ Panel)        |
//+------------------------------------------------------------------+
void ConfigurePanelObject(const string name)
  {
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

bool CreatePanelRectangle(const string name,const int x,const int y,const int width,const int height)
  {
   if(!ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0) && ObjectFind(0,name)<0) return false;
   ConfigurePanelObject(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,clrBlack);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,clrBlack);
   return true;
  }

bool CreatePanelLabel(const string name,const string text,const int x,const int y,
                      const color clr=clrWhite,const string font_name="",const int font_size=-1)
  {
   if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0) && ObjectFind(0,name)<0) return false;
   ConfigurePanelObject(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(font_size<0 ? InpFontSize : font_size));
   ObjectSetString(0,name,OBJPROP_FONT,(font_name=="" ? InpFont : font_name));
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   return true;
  }

bool CreatePanelButton(const string name,const int x,const int y,const int width,const int height)
  {
   if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0) && ObjectFind(0,name)<0) return false;
   ConfigurePanelObject(name);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,C'13,12,82');
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'25,24,130');
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,InpFontSize);
   ObjectSetString(0,name,OBJPROP_FONT,InpFont);
   ObjectSetString(0,name,OBJPROP_TEXT,name);
   return true;
  }

void SetPanelLine(const int index,const string text)
  {
   const int x=(index<24 ? 16 : 330);
   const int row=(index<24 ? index : index-24);
   const color clr=((index==9 || index==11 || index==19 || (index>=25 && (index%2)==1)) ? clrNONE : clrWhite);
   CreatePanelLabel("Panel_Lines"+(string)index,text,x,99+row*16,clr);
  }

void DeletePanelObjects()
  {
   for(int i=0;i<48;i++) ObjectDelete(0,"Panel_Lines"+(string)i);
   ObjectDelete(0,"PAUSE EA");
   ObjectDelete(0,"CLOSE ALL TRADES");
   ObjectDelete(0,"INFORMATION");
   if(g_dialog_prefix!="")
     {
      ObjectDelete(0,g_dialog_prefix+"Back");
      ObjectDelete(0,g_dialog_prefix+"Border");
      ObjectDelete(0,g_dialog_prefix+"Caption");
      ObjectDelete(0,g_dialog_prefix+"ClientBack");
      ObjectDelete(0,g_dialog_prefix+"Close");
      ObjectDelete(0,g_dialog_prefix+"MinMax");
     }
  }

void CreatePanel()
  {
   g_dialog_prefix=StringFormat("%05d",(int)(ChartID()%100000));
   CreatePanelRectangle(g_dialog_prefix+"Back",6,21,643,468);
   CreatePanelRectangle(g_dialog_prefix+"Border",5,20,645,470);
   CreatePanelRectangle(g_dialog_prefix+"ClientBack",9,44,637,442);
   string caption=g_dialog_prefix+"Caption";
   if(ObjectCreate(0,caption,OBJ_EDIT,0,0,0) || ObjectFind(0,caption)>=0)
     {
      ConfigurePanelObject(caption);
      ObjectSetInteger(0,caption,OBJPROP_XDISTANCE,7);
      ObjectSetInteger(0,caption,OBJPROP_YDISTANCE,22);
      ObjectSetInteger(0,caption,OBJPROP_XSIZE,641);
      ObjectSetInteger(0,caption,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,caption,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,caption,OBJPROP_BGCOLOR,C'7,4,47');
      ObjectSetInteger(0,caption,OBJPROP_BORDER_COLOR,C'7,4,47');
      ObjectSetInteger(0,caption,OBJPROP_READONLY,true);
      ObjectSetInteger(0,caption,OBJPROP_FONTSIZE,InpFontSize+1);
      ObjectSetString(0,caption,OBJPROP_FONT,InpFont);
      ObjectSetString(0,caption,OBJPROP_TEXT,"Quantum Queen ST Edition");
     }
   CreatePanelButton("PAUSE EA",16,50,307,19);
   CreatePanelButton("CLOSE ALL TRADES",330,50,311,19);
  }

void UpdatePanel()
  {
   if(InpPanel!=QQ_OPTION_ON) return;
   double grid_step=GetGridStepPoints();
   SetPanelLine(0,StringFormat("Supertrend: %s (%.2f)", (g_current_st_trend==1 ? "BULLISH" : "BEARISH"), g_st_line));
   SetPanelLine(1,StringFormat("Grid: %s | MaxOrders: %d | Step: %.1f pts",
                               (InpGridMode==QQ_GRID_SMART_ATR ? "Smart ATR" : "Original"),
                               InpMaxOrders, grid_step));
   SetPanelLine(2,StringFormat("Balance: %.2f | Equity: %.2f | Open Orders: %d",
                               AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY), TotalOpenOrdersCount()));
   SetPanelLine(3,StringFormat("Floating P/L: %.2f %s", TotalStrategyProfit(), AccountInfoString(ACCOUNT_CURRENCY)));

   for(int slot=0;slot<QQ_STRATEGY_COUNT;slot++)
     {
      int count=StrategyPositionCount(slot);
      string state=(count<=0 ? "Waiting..." : StringFormat("Active orders: %d",count));
      int line=4+slot;
      SetPanelLine(line,StringFormat("[Strategy %d] %s | %s", slot+1, (StrategyEnabled(slot) ? "ON" : "OFF"), state));
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Create Indicator Handles                                         |
//+------------------------------------------------------------------+
bool CreateSignalHandles()
  {
   for(int i=0;i<QQ_STRATEGY_COUNT;i++)
     {
      g_demarker_a[i]=INVALID_HANDLE;
      g_demarker_b[i]=INVALID_HANDLE;
     }

   g_handle_atr = iATR(_Symbol, InpST_Timeframe, InpST_AtrPeriod);
   if(g_handle_atr == INVALID_HANDLE)
     {
      Print("ATR handle creation failed");
      return false;
     }

   g_demarker_a[0]=iDeMarker(_Symbol,PERIOD_M6,18);
   g_demarker_b[0]=iDeMarker(_Symbol,PERIOD_M15,16);
   g_demarker_a[1]=iDeMarker(_Symbol,PERIOD_M15,14);
   g_demarker_b[1]=iDeMarker(_Symbol,PERIOD_M20,20);
   g_demarker_a[2]=iDeMarker(_Symbol,PERIOD_M15,26);
   g_demarker_b[2]=iDeMarker(_Symbol,PERIOD_M15,24);
   g_demarker_a[3]=iDeMarker(_Symbol,PERIOD_M15,20);
   g_demarker_b[3]=iDeMarker(_Symbol,PERIOD_M20,22);
   g_demarker_a[4]=iDeMarker(_Symbol,PERIOD_M1,18);
   g_demarker_b[4]=iDeMarker(_Symbol,PERIOD_M15,18);
   g_demarker_a[5]=iDeMarker(_Symbol,PERIOD_M10,30);
   g_demarker_b[5]=iDeMarker(_Symbol,PERIOD_M30,28);
   g_demarker_a[6]=iDeMarker(_Symbol,PERIOD_M1,20);
   g_demarker_b[6]=iDeMarker(_Symbol,PERIOD_M20,16);
   g_demarker_a[7]=iDeMarker(_Symbol,PERIOD_M1,12);
   g_demarker_b[7]=iDeMarker(_Symbol,PERIOD_H1,20);
   g_demarker_a[8]=iDeMarker(_Symbol,PERIOD_M12,18);
   g_demarker_b[8]=iDeMarker(_Symbol,PERIOD_M15,12);
   g_demarker_a[9]=iDeMarker(_Symbol,PERIOD_M10,20);
   g_demarker_b[9]=iDeMarker(_Symbol,PERIOD_M15,10);
   g_demarker_a[10]=iDeMarker(_Symbol,PERIOD_M10,30);
   g_demarker_b[10]=iDeMarker(_Symbol,PERIOD_M30,28);
   g_demarker_a[11]=iDeMarker(_Symbol,PERIOD_M12,10);
   g_demarker_b[11]=iDeMarker(_Symbol,PERIOD_M15,20);

   for(int i=0;i<QQ_STRATEGY_COUNT;i++)
      if(g_demarker_a[i]==INVALID_HANDLE || g_demarker_b[i]==INVALID_HANDLE)
         return false;

   return true;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayInitialize(g_last_bar_time,0);
   g_paused=(InpPause==QQ_OPTION_ON);
   g_last_visual_tp_bar=0;
   g_trade.SetAsyncMode(false);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!CreateSignalHandles())
     {
      PrintFormat("Quantum Queen: DeMarker indicator handle creation failed (%d)",GetLastError());
      return INIT_FAILED;
     }

   if(InpPanel==QQ_OPTION_ON)
      CreatePanel();

   EventSetTimer(1);
   Print("Quantum Queen Supertrend Edition v4.5 initialized successfully.");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_handle_atr!=INVALID_HANDLE)
      IndicatorRelease(g_handle_atr);

   for(int i=0;i<QQ_STRATEGY_COUNT;i++)
     {
      if(g_demarker_a[i]!=INVALID_HANDLE) IndicatorRelease(g_demarker_a[i]);
      if(g_demarker_b[i]!=INVALID_HANDLE) IndicatorRelease(g_demarker_b[i]);
     }
   DeletePanelObjects();
   ObjectsDeleteAll(0,QQ_PANEL_PREFIX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!TradingEnvironmentReady()) return;

   ApplyDrawdownControl();
   UpdateSupertrend();

   for(int slot=0;slot<QQ_STRATEGY_COUNT;slot++)
      ProcessStrategy(slot);

   for(int slot=0;slot<QQ_STRATEGY_COUNT;slot++)
      ManageStrategy(slot);

   if(g_remove_after_risk)
     {
      g_remove_after_risk=false;
      ExpertRemove();
     }
  }

//+------------------------------------------------------------------+
//| OnTimer                                                          |
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now=TimeCurrent();
   if(InpPanel==QQ_OPTION_ON && now-g_last_panel_update>=1)
     {
      g_last_panel_update=now;
      UpdatePanel();
     }
  }

//+------------------------------------------------------------------+
//| OnChartEvent                                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(sparam=="PAUSE EA")
     {
      g_paused=!g_paused;
      ObjectSetString(0,"PAUSE EA",OBJPROP_TEXT,(g_paused ? "Resume EA" : "Pause EA"));
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdatePanel();
      return;
     }
   if(sparam=="CLOSE ALL TRADES")
     {
      if(MessageBox("Close all strategy positions?","Quantum Queen",MB_YESNO|MB_ICONQUESTION)==IDYES)
         CloseAllStrategies("ChartCloseAll");
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
      UpdatePanel();
      return;
     }
  }
//+------------------------------------------------------------------+
