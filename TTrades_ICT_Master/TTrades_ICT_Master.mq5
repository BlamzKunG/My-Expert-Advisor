//+------------------------------------------------------------------+
//|                                         TTrades_ICT_Master.mq5 |
//|                                      Copyright 2026, BlamzKunG |
//|                                       https://github.com/Blamz |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BlamzKunG"
#property link      "https://github.com/Blamz"
#property version   "2.70"
#property description "Advanced ICT Framework with Institutional Recovery & Hedging"

#include <Trade\Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string                 sep1 = "--- Timeframe Settings ---";
input ENUM_TIMEFRAMES         Inp_HTF_Bias   = PERIOD_D1;  
input ENUM_TIMEFRAMES         Inp_LTF_Entry  = PERIOD_M5;  

sinput string                 sep2 = "--- Killzone Settings ---";
input bool                    Inp_UseKillzones = true;
input string                  Inp_KZ_Start   = "08:30";
input string                  Inp_KZ_End     = "11:00";

sinput string                 sep3 = "--- Strategy Toggles ---";
input bool                    Inp_Use_IFVG    = true;
input bool                    Inp_Use_C2C3    = true;
input bool                    Inp_Use_CISD    = true;

sinput string                 sep4 = "--- Risk & Profit Management ---";
input double                  Inp_LotSize    = 0.1;
input int                     Inp_SL_Buffer  = 20;   
input bool                    Inp_Use_RR     = true; 
input double                  Inp_TargetRR   = 2.0;  

sinput string                 sep5 = "--- Advanced Exit Systems (Hybrid) ---";
input bool                    Inp_Use_BE       = true;  
input double                  Inp_BE_TriggerRR = 1.0;   
input bool                    Inp_Use_Trail    = false; 
input int                     Inp_TrailPoints  = 300;   
input bool                    Inp_Use_CandleTrail = true; 

sinput string                 sep6 = "--- Institutional Recovery (Averaging) ---";
input bool                    Inp_Use_Avg       = false; // Enable Averaging/Grid
input int                     Inp_Avg_Step      = 300;   // Distance between orders (Points)
input double                  Inp_Avg_Multiplier = 1.0;   // Lot Multiplier (1.0 = Same lot, 2.0 = Martingale)
input int                     Inp_Max_Orders    = 3;     // Max orders in one direction

sinput string                 sep7 = "--- Hedge Recovery System ---";
input bool                    Inp_Use_Hedge     = false; // Enable Hedging
input int                     Inp_Hedge_Dist    = 500;   // Distance to trigger Hedge (Points)
input double                  Inp_Hedge_LotMult = 1.0;   // Hedge Lot Multiplier

//--- Global State
datetime lastEntryBarTime = 0;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("TTrades ICT Master v2.70 (Recovery Suite) Initialized.");
    trade.SetExpertMagicNumber(20261337);
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Print("EA Deinitialized.");
}

//+------------------------------------------------------------------+
//| Tick Processing                                                  |
//+------------------------------------------------------------------+
void OnTick() {
    // 1. Manage Existing Trades & Recovery
    ManageExits();
    if(Inp_Use_Avg || Inp_Use_Hedge) ManageRecovery();

    // 2. Killzone Filter
    if(Inp_UseKillzones && !IsInKillzone()) return;
    
    // 3. New Signal Logic (Only if no orders exist for basic ICT)
    if(PositionsTotal() == 0) {
        datetime currentBarTime = iTime(Symbol(), Inp_LTF_Entry, 0);
        if(currentBarTime == lastEntryBarTime) return; 

        int bias = DetermineBias();
        if(bias == 1 && CheckLongEntry()) {
            ExecuteTrade(ORDER_TYPE_BUY, Inp_LotSize);
            lastEntryBarTime = currentBarTime;
        }
        else if(bias == -1 && CheckShortEntry()) {
            ExecuteTrade(ORDER_TYPE_SELL, Inp_LotSize);
            lastEntryBarTime = currentBarTime;
        }
    }
}

//+------------------------------------------------------------------+
//| RECOVERY MANAGEMENT (Averaging & Hedging)                        |
//+------------------------------------------------------------------+
void ManageRecovery() {
    int buyCount = 0, sellCount = 0;
    double lastBuyPrice = 0, lastSellPrice = 0;
    double buyLots = 0, sellLots = 0;

    // Scan current positions
    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionGetSymbol(i) != Symbol() || PositionGetInteger(POSITION_MAGIC) != 20261337) continue;
        
        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            buyCount++;
            lastBuyPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            buyLots = PositionGetDouble(POSITION_VOLUME);
        } else {
            sellCount++;
            lastSellPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            sellLots = PositionGetDouble(POSITION_VOLUME);
        }
    }

    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);

    // --- 1. Institutional Averaging Logic ---
    if(Inp_Use_Avg) {
        // Long Averaging
        if(buyCount > 0 && buyCount < Inp_Max_Orders) {
            if(bid < lastBuyPrice - (Inp_Avg_Step * Point())) {
                Print("RECOVERY: Triggering Buy Averaging Order #", buyCount + 1);
                ExecuteTrade(ORDER_TYPE_BUY, buyLots * Inp_Avg_Multiplier);
            }
        }
        // Short Averaging
        if(sellCount > 0 && sellCount < Inp_Max_Orders) {
            if(ask > lastSellPrice + (Inp_Avg_Step * Point())) {
                Print("RECOVERY: Triggering Sell Averaging Order #", sellCount + 1);
                ExecuteTrade(ORDER_TYPE_SELL, sellLots * Inp_Avg_Multiplier);
            }
        }
    }

    // --- 2. Hedge Recovery Logic ---
    if(Inp_Use_Hedge) {
        // Hedge a losing Buy with a Sell
        if(buyCount > 0 && sellCount == 0) {
            if(bid < lastBuyPrice - (Inp_Hedge_Dist * Point())) {
                Print("RECOVERY: Triggering Hedge SELL.");
                ExecuteTrade(ORDER_TYPE_SELL, buyLots * Inp_Hedge_LotMult);
            }
        }
        // Hedge a losing Sell with a Buy
        if(sellCount > 0 && buyCount == 0) {
            if(ask > lastSellPrice + (Inp_Hedge_Dist * Point())) {
                Print("RECOVERY: Triggering Hedge BUY.");
                ExecuteTrade(ORDER_TYPE_BUY, sellLots * Inp_Hedge_LotMult);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| HYBRID EXIT MANAGEMENT                                           |
//+------------------------------------------------------------------+
void ManageExits() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket) || PositionGetInteger(POSITION_MAGIC) != 20261337) continue;

        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL  = PositionGetDouble(POSITION_SL);
        double currentTP  = PositionGetDouble(POSITION_TP);
        double curPrice   = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        
        bool mod = false;
        double nSL = currentSL;

        // BE & Trailing logic (Only if not hedged, to keep it simple)
        if(Inp_Use_BE) {
            double pips = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? (curPrice - entryPrice) : (entryPrice - curPrice);
            double risk = MathAbs(entryPrice - currentSL);
            if(risk > 0 && pips >= risk * Inp_BE_TriggerRR) {
                if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && nSL < entryPrice) ||
                   (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && (nSL > entryPrice || nSL == 0))) {
                    nSL = entryPrice; mod = true;
                }
            }
        }

        if(Inp_Use_CandleTrail) {
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                double pl = iLow(Symbol(), Inp_LTF_Entry, 1);
                if(pl > nSL) { nSL = pl; mod = true; }
            } else {
                double ph = iHigh(Symbol(), Inp_LTF_Entry, 1);
                if(ph < nSL || nSL == 0) { nSL = ph; mod = true; }
            }
        }

        if(mod && nSL != currentSL) trade.PositionModify(ticket, nSL, currentTP);
    }
}

//+------------------------------------------------------------------+
//| EXECUTION                                                        |
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double lots) {
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl = 0, tp = 0;
    
    // Initial SL/TP only for the first trade of a basket
    if(PositionsTotal() == 0) {
        if(type == ORDER_TYPE_BUY) sl = iLow(Symbol(), Inp_LTF_Entry, 1) - (Inp_SL_Buffer * Point());
        else sl = iHigh(Symbol(), Inp_LTF_Entry, 1) + (Inp_SL_Buffer * Point());
        
        if(Inp_Use_RR) {
            double risk = MathAbs(price - sl);
            tp = (type == ORDER_TYPE_BUY) ? (price + risk * Inp_TargetRR) : (price - risk * Inp_TargetRR);
        }
    }

    trade.PositionOpen(Symbol(), type, lots, price, sl, tp, "ICT Recovery");
}

//+------------------------------------------------------------------+
//| MODULES (Signals)                                                |
//+------------------------------------------------------------------+
bool IsInKillzone() {
    datetime t = TimeCurrent(); MqlDateTime dt; TimeToStruct(t, dt);
    string s = StringFormat("%02d:%02d", dt.hour, dt.min);
    return (s >= Inp_KZ_Start && s <= Inp_KZ_End);
}

int DetermineBias() {
    double c1 = iClose(Symbol(), Inp_HTF_Bias, 1), c2 = iClose(Symbol(), Inp_HTF_Bias, 2);
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

bool CheckC2C3_Long() {
    double c1L = iLow(Symbol(), Inp_LTF_Entry, 3), c1H = iHigh(Symbol(), Inp_LTF_Entry, 3);
    double c2C = iClose(Symbol(), Inp_LTF_Entry, 2), c2H = iHigh(Symbol(), Inp_LTF_Entry, 2);
    double c3C = iClose(Symbol(), Inp_LTF_Entry, 1);
    if(c1L <= iLow(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2C > c1H || (c2C <= c1H && c3C > c2H)) return true;
    }
    return false;
}

bool CheckC2C3_Short() {
    double c1H = iHigh(Symbol(), Inp_LTF_Entry, 3), c1L = iLow(Symbol(), Inp_LTF_Entry, 3);
    double c2C = iClose(Symbol(), Inp_LTF_Entry, 2), c2L = iLow(Symbol(), Inp_LTF_Entry, 2);
    double c3C = iClose(Symbol(), Inp_LTF_Entry, 1);
    if(c1H >= iHigh(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2C < c1L || (c2C >= c1L && c3C < c2L)) return true;
    }
    return false;
}

bool CheckIFVGLong() {
    for(int i=5; i<=15; i++) {
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
