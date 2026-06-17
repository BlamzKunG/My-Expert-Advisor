//+------------------------------------------------------------------+
//|                                         TTrades_ICT_Master.mq5 |
//|                                      Copyright 2026, BlamzKunG |
//|                                       https://github.com/Blamz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BlamzKunG"
#property link      "https://github.com/Blamz"
#property version   "2.50"
#property description "Advanced ICT Framework with Hybrid Profit Management"

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string                 sep1 = "--- Timeframe Settings ---";
input ENUM_TIMEFRAMES         Inp_HTF_Bias   = PERIOD_D1;  // Bias & Daily Profile TF
input ENUM_TIMEFRAMES         Inp_LTF_Entry  = PERIOD_M5;  // Entry Execution TF

sinput string                 sep2 = "--- Killzone Settings (Broker Time) ---";
input bool                    Inp_UseKillzones = true;
input string                  Inp_KZ_Start   = "08:30";
input string                  Inp_KZ_End     = "11:00";

sinput string                 sep3 = "--- Strategy Toggles ---";
input bool                    Inp_Use_IFVG    = true;
input bool                    Inp_Use_C2C3    = true;
input bool                    Inp_Use_CISD    = true;

sinput string                 sep4 = "--- Risk & Profit Management ---";
input double                  Inp_LotSize    = 0.1;
input int                     Inp_SL_Buffer  = 20;   // Buffer in Points
input bool                    Inp_Use_RR     = true; // Use Fixed RR Target
input double                  Inp_TargetRR   = 2.0;  // Target RR (e.g. 2.0 = 1:2)

sinput string                 sep5 = "--- Advanced Exit Systems (Hybrid) ---";
input bool                    Inp_Use_BE       = true;  // Enable Break-Even
input double                  Inp_BE_TriggerRR = 1.0;   // Move to BE after reaching 1:1 RR
input bool                    Inp_Use_Trail    = false; // Standard Trailing Stop
input int                     Inp_TrailPoints  = 300;   // Distance for Standard Trail
input bool                    Inp_Use_CandleTrail = true; // ICT Candle-based Trailing

//--- Global State
datetime lastEntryBarTime = 0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("TTrades ICT Master v2.50 Initialized.");
    trade.SetExpertMagicNumber(20261337);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Print("EA Deinitialized. Code: ", reason);
}

//+------------------------------------------------------------------+
//| Tick Processing                                                  |
//+------------------------------------------------------------------+
void OnTick() {
    // 1. Manage Existing Trades (Dynamic Exits)
    ManageExits();

    // 2. Filters
    if(Inp_UseKillzones && !IsInKillzone()) return;
    
    // 3. One Trade Per Bar
    datetime currentBarTime = iTime(Symbol(), Inp_LTF_Entry, 0);
    if(currentBarTime == lastEntryBarTime) return; 
    
    // 4. Bias & Signal
    int bias = DetermineBias();
    if(bias == 0) return;
    
    if(PositionsTotal() == 0) {
        if(bias == 1 && CheckLongEntry()) {
            ExecuteTrade(ORDER_TYPE_BUY);
            lastEntryBarTime = currentBarTime;
        }
        else if(bias == -1 && CheckShortEntry()) {
            ExecuteTrade(ORDER_TYPE_SELL);
            lastEntryBarTime = currentBarTime;
        }
    }
}

//+------------------------------------------------------------------+
//| HYBRID EXIT MANAGEMENT SYSTEM                                    |
//+------------------------------------------------------------------+
void ManageExits() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != 20261337) continue;

        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL  = PositionGetDouble(POSITION_SL);
        double currentTP  = PositionGetDouble(POSITION_TP);
        double currentPrice = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        
        double slDistance = MathAbs(entryPrice - currentSL);
        bool modified = false;
        double newSL = currentSL;

        // --- 1. Break-Even Logic ---
        if(Inp_Use_BE) {
            double profitInPoints = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
            if(profitInPoints >= (slDistance * Inp_BE_TriggerRR)) {
                if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && newSL < entryPrice) ||
                   (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && (newSL > entryPrice || newSL == 0))) {
                    newSL = entryPrice + (SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point()); // BE + Spread
                    Print("EXIT: Break-Even Triggered. Moving SL to Entry.");
                    modified = true;
                }
            }
        }

        // --- 2. Standard Trailing Stop ---
        if(Inp_Use_Trail) {
            double trailDist = Inp_TrailPoints * Point();
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                if(currentPrice - trailDist > newSL) {
                    newSL = currentPrice - trailDist;
                    modified = true;
                }
            } else {
                if(currentPrice + trailDist < newSL || newSL == 0) {
                    newSL = currentPrice + trailDist;
                    modified = true;
                }
            }
        }

        // --- 3. ICT Candle-based Trailing (Move to Prev Candle Low/High) ---
        if(Inp_Use_CandleTrail) {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                double prevLow = iLow(Symbol(), Inp_LTF_Entry, 1);
                if(prevLow > newSL) {
                    newSL = prevLow;
                    modified = true;
                }
            } else {
                double prevHigh = iHigh(Symbol(), Inp_LTF_Entry, 1);
                if(prevHigh < newSL || newSL == 0) {
                    newSL = prevHigh;
                    modified = true;
                }
            }
        }

        // Apply Modifications
        if(modified && newSL != currentSL) {
            if(!trade.PositionModify(ticket, newSL, currentTP)) {
                Print("DEBUG: Failed to modify SL. Error: ", GetLastError());
            } else {
                Print("EXIT: SL Adjusted to ", newSL, " based on Hybrid rules.");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| EXECUTION (With Initial RR Calculation)                          |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type) {
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double price = (type == ORDER_TYPE_BUY) ? ask : bid;
    double sl = 0.0, tp = 0.0;
    
    // 1. SL Calculation
    if(type == ORDER_TYPE_BUY) sl = iLow(Symbol(), Inp_LTF_Entry, 1) - (Inp_SL_Buffer * Point());
    else sl = iHigh(Symbol(), Inp_LTF_Entry, 1) + (Inp_SL_Buffer * Point());
    
    // Validate StopLevel
    double stopLevel = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * Point();
    double minStep = stopLevel + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point();
    
    if(type == ORDER_TYPE_BUY && (price - sl < minStep)) sl = price - minStep;
    if(type == ORDER_TYPE_SELL && (sl - price < minStep)) sl = price + minStep;

    // 2. TP Calculation (Fixed RR)
    if(Inp_Use_RR) {
        double risk = MathAbs(price - sl);
        if(type == ORDER_TYPE_BUY) tp = price + (risk * Inp_TargetRR);
        else tp = price - (risk * Inp_TargetRR);
    }

    Print("ATTEMPT: Opening ", EnumToString(type), " at ", price, " SL: ", sl, " TP: ", tp);
    if(trade.PositionOpen(Symbol(), type, Inp_LotSize, price, sl, tp, "TTrades ICT Master")) {
        Print("SUCCESS: Ticket ", trade.ResultDeal());
    } else {
        Print("ERROR: Code ", GetLastError(), " - ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| MODULES (Signals & Logic)                                        |
//+------------------------------------------------------------------+
bool IsInKillzone() {
    datetime t = TimeCurrent(); MqlDateTime dt; TimeToStruct(t, dt);
    string s = StringFormat("%02d:%02d", dt.hour, dt.min);
    return (s >= Inp_KZ_Start && s <= Inp_KZ_End);
}

int DetermineBias() {
    double c1 = iClose(Symbol(), Inp_HTF_Bias, 1);
    double c2 = iClose(Symbol(), Inp_HTF_Bias, 2);
    return (c1 > c2) ? 1 : ((c1 < c2) ? -1 : 0);
}

bool CheckLongEntry() {
    if(Inp_Use_IFVG && CheckIFVGLong()) return true;
    if(Inp_Use_C2C3 && CheckC2C3_Long()) return true;
    if(Inp_Use_CISD && CheckCISD_Long()) return true;
    return false;
}

bool CheckShortEntry() {
    if(Inp_Use_C2C3 && CheckC2C3_Short()) return true;
    return false;
}

// Signal Logic Implementation (Shortened for brevity, same as previous)
bool CheckC2C3_Long() {
    double c1L = iLow(Symbol(), Inp_LTF_Entry, 3), c1H = iHigh(Symbol(), Inp_LTF_Entry, 3);
    double c2C = iClose(Symbol(), Inp_LTF_Entry, 2), c2H = iHigh(Symbol(), Inp_LTF_Entry, 2);
    double c3C = iClose(Symbol(), Inp_LTF_Entry, 1);
    if(c1L <= iLow(Symbol(), Inp_LTF_Entry, 4) && c1L <= iLow(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2C > c1H || (c2C <= c1H && c3C > c2H)) return true;
    }
    return false;
}

bool CheckC2C3_Short() {
    double c1H = iHigh(Symbol(), Inp_LTF_Entry, 3), c1L = iLow(Symbol(), Inp_LTF_Entry, 3);
    double c2C = iClose(Symbol(), Inp_LTF_Entry, 2), c2L = iLow(Symbol(), Inp_LTF_Entry, 2);
    double c3C = iClose(Symbol(), Inp_LTF_Entry, 1);
    if(c1H >= iHigh(Symbol(), Inp_LTF_Entry, 4) && c1H >= iHigh(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2C < c1L || (c2C >= c1L && c3C < c2L)) return true;
    }
    return false;
}

bool CheckIFVGLong() {
    for(int i=5; i<=20; i++) {
        double h3 = iHigh(Symbol(), Inp_LTF_Entry, i), l1 = iLow(Symbol(), Inp_LTF_Entry, i-2);
        if(l1 > h3 && iClose(Symbol(), Inp_LTF_Entry, 2) > l1) {
            if(iLow(Symbol(), Inp_LTF_Entry, 1) <= l1 && iClose(Symbol(), Inp_LTF_Entry, 1) > l1) return true;
        }
    }
    return false;
}

bool CheckCISD_Long() {
    for(int i=2; i<=10; i++) {
        if(iClose(Symbol(), Inp_LTF_Entry, i) < iOpen(Symbol(), Inp_LTF_Entry, i)) {
            if(iClose(Symbol(), Inp_LTF_Entry, 1) > iHigh(Symbol(), Inp_LTF_Entry, i)) return true;
            break;
        }
    }
    return false;
}
bool CheckUnicornLong() { return false; }
