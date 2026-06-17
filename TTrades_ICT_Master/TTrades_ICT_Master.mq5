//+------------------------------------------------------------------+
//|                                         TTrades_ICT_Master.mq5 |
//|                                      Copyright 2026, BlamzKunG |
//|                                       https://github.com/Blamz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BlamzKunG"
#property link      "https://github.com/Blamz"
#property version   "2.10"
#property description "Advanced ICT & MMXM Automated Framework based on TTrades"

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS (Extreme Flexibility)                           |
//+------------------------------------------------------------------+
sinput string                 sep1 = "--- Timeframe Settings ---";
input ENUM_TIMEFRAMES         Inp_HTF_Bias   = PERIOD_D1;  // Bias & Daily Profile TF
input ENUM_TIMEFRAMES         Inp_ITF_Curve  = PERIOD_H1;  // MMXM Curve & POI TF
input ENUM_TIMEFRAMES         Inp_LTF_Entry  = PERIOD_M5;  // Entry Execution TF

sinput string                 sep2 = "--- Killzone Settings (Broker Time) ---";
input bool                    Inp_UseKillzones = true;     // Enable Time Filtering
input string                  Inp_KZ_Start   = "08:30";    // Session Start
input string                  Inp_KZ_End     = "11:00";    // Session End

sinput string                 sep3 = "--- Strategy & Entry Toggles ---";
input bool                    Inp_Use_Unicorn = true;      // Enable Unicorn Model (Breaker + FVG)
input bool                    Inp_Use_IFVG    = true;      // Enable Inversion FVG
input bool                    Inp_Use_C2C3    = true;      // Enable Candle 2 / Candle 3 Closures
input bool                    Inp_Use_CISD    = true;      // Enable Intracandle CISD

sinput string                 sep4 = "--- Risk & Filters ---";
input bool                    Inp_Filter_SeekDestroy = true; // Avoid trading in Seek & Destroy profile
input bool                    Inp_Filter_SMT = false;        // Require SMT Divergence to enter
input double                  Inp_LotSize    = 0.1;          // Fixed Lot Size
input int                     Inp_SL_Buffer  = 20;           // Stop Loss Buffer (Points)

//--- Global State Variables
int currentBias = 0; // 1 = Long, -1 = Short, 0 = Neutral
datetime lastEntryBarTime = 0; // Prevent multiple trades per bar

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("TTrades ICT Master initialized. HTF: ", EnumToString(Inp_HTF_Bias), ", LTF: ", EnumToString(Inp_LTF_Entry));
    trade.SetExpertMagicNumber(20261337);
    
    // Debug Broker Info
    double stopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL);
    Print("DEBUG: Broker Stop Level for ", Symbol(), " is ", stopLevel, " points.");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("TTrades ICT Master deinitialized. Reason Code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // 1. Time Filter (Killzone)
    if(Inp_UseKillzones && !IsInKillzone()) return;
    
    // 2. Daily Profile Check (Seek & Destroy Filter)
    if(Inp_Filter_SeekDestroy && IsSeekAndDestroyProfile()) return;
    
    // 3. One Trade Per Bar Logic (Prevents Order Spamming)
    datetime currentBarTime = iTime(Symbol(), Inp_LTF_Entry, 0);
    if(currentBarTime == lastEntryBarTime) return; 
    
    // 4. Determine Bias
    currentBias = DetermineBias();
    if(currentBias == 0) return;
    
    // 5. Look for Entries if no open positions
    if(PositionsTotal() == 0) {
        if(currentBias == 1) {
            if(CheckLongEntry()) {
                ExecuteTrade(ORDER_TYPE_BUY);
                lastEntryBarTime = currentBarTime; // Lock this bar after execution
            }
        }
        else if(currentBias == -1) {
            if(CheckShortEntry()) {
                ExecuteTrade(ORDER_TYPE_SELL);
                lastEntryBarTime = currentBarTime; // Lock this bar after execution
            }
        }
    }
}

//+------------------------------------------------------------------+
//| MODULE: Killzone Checker                                         |
//+------------------------------------------------------------------+
bool IsInKillzone() {
    datetime timeCurrent = TimeCurrent();
    MqlDateTime dt;
    TimeToStruct(timeCurrent, dt);
    
    string currentTimeStr = StringFormat("%02d:%02d", dt.hour, dt.min);
    if(currentTimeStr >= Inp_KZ_Start && currentTimeStr <= Inp_KZ_End) return true;
    return false;
}

//+------------------------------------------------------------------+
//| MODULE: Seek & Destroy Filter                                    |
//+------------------------------------------------------------------+
bool IsSeekAndDestroyProfile() {
    // Advanced Logic Placeholder
    return false; 
}

//+------------------------------------------------------------------+
//| MODULE: HTF Bias                                                 |
//+------------------------------------------------------------------+
int DetermineBias() {
    double htfClose1 = iClose(Symbol(), Inp_HTF_Bias, 1);
    double htfClose2 = iClose(Symbol(), Inp_HTF_Bias, 2);
    
    int bias = 0;
    if(htfClose1 > htfClose2) bias = 1;
    else if(htfClose1 < htfClose2) bias = -1;
    
    return bias;
}

//+------------------------------------------------------------------+
//| MODULE: Long Entry Logic (Routing)                               |
//+------------------------------------------------------------------+
bool CheckLongEntry() {
    bool validEntry = false;
    string signalType = "";

    if(Inp_Use_Unicorn && CheckUnicornLong()) { validEntry = true; signalType = "Unicorn"; }
    if(!validEntry && Inp_Use_IFVG && CheckIFVGLong()) { validEntry = true; signalType = "IFVG"; }
    if(!validEntry && Inp_Use_C2C3 && CheckC2C3_Long()) { validEntry = true; signalType = "C2/C3"; }
    if(!validEntry && Inp_Use_CISD && CheckCISD_Long()) { validEntry = true; signalType = "CISD"; }
    
    if(validEntry) Print("SIGNAL: Bullish Entry Found! Type: ", signalType, " at ", TimeToString(TimeCurrent()));
    return validEntry;
}

//+------------------------------------------------------------------+
//| MODULE: Short Entry Logic (Routing)                              |
//+------------------------------------------------------------------+
bool CheckShortEntry() {
    bool validEntry = false;
    string signalType = "";

    if(Inp_Use_C2C3 && CheckC2C3_Short()) { validEntry = true; signalType = "C2/C3"; }
    
    if(validEntry) Print("SIGNAL: Bearish Entry Found! Type: ", signalType, " at ", TimeToString(TimeCurrent()));
    return validEntry;
}

//+------------------------------------------------------------------+
//| LOGIC: C2 / C3 Closures (Long)                                   |
//+------------------------------------------------------------------+
bool CheckC2C3_Long() {
    double c1Low = iLow(Symbol(), Inp_LTF_Entry, 3);
    double c1High = iHigh(Symbol(), Inp_LTF_Entry, 3);
    double c2Close = iClose(Symbol(), Inp_LTF_Entry, 2);
    double c2High = iHigh(Symbol(), Inp_LTF_Entry, 2);
    double c3Close = iClose(Symbol(), Inp_LTF_Entry, 1);
    
    if(c1Low <= iLow(Symbol(), Inp_LTF_Entry, 4) && c1Low <= iLow(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2Close > c1High) return true;
        if(c2Close <= c1High && c3Close > c2High) return true;
    }
    return false;
}

bool CheckC2C3_Short() {
    double c1High = iHigh(Symbol(), Inp_LTF_Entry, 3);
    double c1Low = iLow(Symbol(), Inp_LTF_Entry, 3);
    double c2Close = iClose(Symbol(), Inp_LTF_Entry, 2);
    double c2Low = iLow(Symbol(), Inp_LTF_Entry, 2);
    double c3Close = iClose(Symbol(), Inp_LTF_Entry, 1);
    
    if(c1High >= iHigh(Symbol(), Inp_LTF_Entry, 4) && c1High >= iHigh(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2Close < c1Low) return true;
        if(c2Close >= c1Low && c3Close < c2Low) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| MODULE: Structural Scanning & Visualization (Debugging)          |
//+------------------------------------------------------------------+
void DrawDebugBox(string name, datetime time1, double price1, datetime time2, double price2, color clr) {
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FILL, true);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
    }
}

//+------------------------------------------------------------------+
//| LOGIC: Inversion FVG (Algorithmic Scan)                          |
//+------------------------------------------------------------------+
bool CheckIFVGLong() {
    for(int i = 5; i <= 20; i++) {
        double high3 = iHigh(Symbol(), Inp_LTF_Entry, i);
        double low1  = iLow(Symbol(), Inp_LTF_Entry, i-2);
        
        if(low1 > high3) {
            double fvgTop = low1;
            double fvgBot = high3;
            double recentClose = iClose(Symbol(), Inp_LTF_Entry, 2);
            if(recentClose > fvgTop) {
                DrawDebugBox("IFVG_"+IntegerToString(i), iTime(Symbol(), Inp_LTF_Entry, i), fvgTop, iTime(Symbol(), Inp_LTF_Entry, 0), fvgBot, clrDarkCyan);
                double currentLow = iLow(Symbol(), Inp_LTF_Entry, 1);
                double currentClose = iClose(Symbol(), Inp_LTF_Entry, 1);
                if(currentLow <= fvgTop && currentClose > fvgTop) return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| LOGIC: Intracandle CISD (Algorithmic Scan)                       |
//+------------------------------------------------------------------+
bool CheckCISD_Long() {
    int lastBearishCandleIdx = -1;
    for(int i = 2; i <= 10; i++) {
        if(iClose(Symbol(), Inp_LTF_Entry, i) < iOpen(Symbol(), Inp_LTF_Entry, i)) {
            lastBearishCandleIdx = i;
            break;
        }
    }
    if(lastBearishCandleIdx != -1) {
        double obHigh = iHigh(Symbol(), Inp_LTF_Entry, lastBearishCandleIdx);
        double currentClose = iClose(Symbol(), Inp_LTF_Entry, 1);
        if(currentClose > obHigh) {
            DrawDebugBox("CISD_"+IntegerToString(lastBearishCandleIdx), iTime(Symbol(), Inp_LTF_Entry, lastBearishCandleIdx), obHigh, iTime(Symbol(), Inp_LTF_Entry, 0), iLow(Symbol(), Inp_LTF_Entry, lastBearishCandleIdx), clrDarkGreen);
            return true; 
        }
    }
    return false;
}

bool CheckUnicornLong() { return false; }

//+------------------------------------------------------------------+
//| EXECUTION (With Robust Validation & Logging)                     |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type) {
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double price = (type == ORDER_TYPE_BUY) ? ask : bid;
    double sl = 0.0;
    
    // 1. Calculate Structural SL
    if(type == ORDER_TYPE_BUY) {
        sl = iLow(Symbol(), Inp_LTF_Entry, 1) - (Inp_SL_Buffer * Point());
    } else {
        sl = iHigh(Symbol(), Inp_LTF_Entry, 1) + (Inp_SL_Buffer * Point());
    }
    
    // 2. Validate SL against Broker's StopLevel
    double stopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * Point();
    double minSlDistance = stopLevel + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
    
    if(type == ORDER_TYPE_BUY) {
        if(price - sl < minSlDistance) {
            sl = price - minSlDistance;
            Print("DEBUG: SL too tight (StopLevel/Spread). Adjusted Buy SL to: ", sl);
        }
    } else {
        if(sl - price < minSlDistance) {
            sl = price + minSlDistance;
            Print("DEBUG: SL too tight (StopLevel/Spread). Adjusted Sell SL to: ", sl);
        }
    }

    // 3. Final Execution & Detailed Result Logging
    Print("ATTEMPT: Sending ", EnumToString(type), " Order. Price: ", price, " SL: ", sl, " Lot: ", Inp_LotSize);
    
    ResetLastError();
    if(trade.PositionOpen(Symbol(), type, Inp_LotSize, price, sl, 0.0, "TTrades ICT Master")) {
        Print("SUCCESS: Order executed. Ticket: ", trade.ResultDeal());
    } else {
        Print("ERROR: Execution Failed! Code: ", GetLastError(), " - ", trade.ResultRetcodeDescription());
        Print("DEBUG INFO: Broker StopLevel: ", stopLevel, " Current Spread: ", SymbolInfoInteger(Symbol(), SYMBOL_SPREAD));
    }
}
