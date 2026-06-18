//+------------------------------------------------------------------+
//|                                         TTrades_ICT_Master.mq5  |
//|                                      Copyright 2026, BlamzKunG  |
//|                                       https://github.com/Blamz  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, BlamzKunG"
#property link      "https://github.com/Blamz"
#property version   "3.00"
#property description "Advanced ICT Framework with Institutional Recovery & Hedging v3"

#include <Trade\Trade.mqh>
CTrade trade;

//+------------------------------------------------------------------+
//| ENUMS                                                            |
//+------------------------------------------------------------------+
enum ENUM_RECOVERY_MODE {
    RECOVERY_NONE   = 0,  // ปิดระบบ Recovery
    RECOVERY_AVG    = 1,  // Averaging Only
    RECOVERY_HEDGE  = 2,  // Hedge Only
    RECOVERY_HYBRID = 3   // Hedge แล้ว Avg ต่อ
};

enum ENUM_BASKET_STATE {
    BASKET_EMPTY    = 0,  // ไม่มี Position
    BASKET_NORMAL   = 1,  // Position เปิดปกติ
    BASKET_AVG      = 2,  // กำลัง Averaging
    BASKET_HEDGED   = 3,  // Hedged แล้ว
    BASKET_CLOSING  = 4   // กำลังจะปิด
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
sinput string sep1 = "=== Timeframe Settings ===";
input ENUM_TIMEFRAMES  Inp_HTF_Bias   = PERIOD_D1;
input ENUM_TIMEFRAMES  Inp_LTF_Entry  = PERIOD_M5;

sinput string sep2 = "=== Killzone Settings ===";
input bool    Inp_UseKillzones = true;
input bool    Inp_KZ_London    = true;   // 08:00-11:00
input bool    Inp_KZ_NewYork   = true;   // 13:30-16:00
input bool    Inp_KZ_Asian     = false;  // 01:00-04:00

sinput string sep3 = "=== Strategy Toggles ===";
input bool    Inp_Use_IFVG  = true;
input bool    Inp_Use_C2C3  = true;
input bool    Inp_Use_CISD  = true;

sinput string sep4 = "=== Risk Management ===";
input bool    Inp_UseRiskPercent = true;    // true=% Risk, false=Fixed Lot
input double  Inp_RiskPercent    = 1.0;     // Risk % ต่อ Trade
input double  Inp_LotSize        = 0.1;     // Fixed Lot (ถ้าไม่ใช้ % Risk)
input int     Inp_SL_Buffer      = 20;
input bool    Inp_Use_RR         = true;
input double  Inp_TargetRR       = 2.0;
input double  Inp_MaxSpread      = 30.0;    // Max Spread (Points) ที่ยอมรับ

sinput string sep5 = "=== Account Protection ===";
input double  Inp_MaxDrawdown    = 10.0;    // Max Drawdown % ก่อน EA หยุด
input double  Inp_DailyLossLimit = 3.0;     // Daily Loss Limit %
input double  Inp_BasketMaxLoss  = 5.0;     // Max Loss % ต่อ Basket ก่อน Force Close

sinput string sep6 = "=== Exit Management ===";
input bool    Inp_Use_BE         = true;
input double  Inp_BE_TriggerRR   = 1.0;
input bool    Inp_Use_CandleTrail = true;

sinput string sep7 = "=== Recovery System ===";
input ENUM_RECOVERY_MODE Inp_RecoveryMode = RECOVERY_NONE;  // โหมด Recovery

// --- Averaging Settings ---
sinput string sep8 = "--- Averaging Config ---";
input int     Inp_Avg_Step        = 300;    // ระยะห่างระหว่าง Order (Points)
input double  Inp_Avg_Multiplier  = 1.5;    // Lot Multiplier (1.0=Same, 1.5=Increase)
input int     Inp_Max_Avg_Orders  = 3;      // จำนวน Avg ครั้งสูงสุด
input bool    Inp_Use_Dynamic_Step = true;  // Step เพิ่มขึ้นตาม Order ที่เพิ่ม

// --- Hedge Settings ---
sinput string sep9 = "--- Hedge Config ---";
input int     Inp_Hedge_Dist      = 500;    // ระยะก่อน Hedge (Points)
input double  Inp_Hedge_LotMult   = 1.5;    // Hedge Lot Multiplier
input bool    Inp_Hedge_Use_TP    = true;   // ใช้ TP บน Hedge
input double  Inp_Hedge_TP_RR     = 1.0;    // Hedge TP RR

// --- Basket TP Settings ---
sinput string sep10 = "--- Basket Profit Target ---";
input bool    Inp_Use_BasketTP    = true;
input double  Inp_BasketTP_Pct    = 0.5;    // ปิด Basket เมื่อได้กำไร % นี้ของ Balance

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+
datetime      g_LastEntryBarTime  = 0;
datetime      g_LastRecoveryBar   = 0;
datetime      g_DayStartTime      = 0;
double        g_DayStartBalance   = 0;
ENUM_BASKET_STATE g_BasketState   = BASKET_EMPTY;
int           g_AvgOrderCount     = 0;   // นับจำนวนครั้งที่ Avg แล้ว
bool          g_HedgeTriggered    = false;
bool          g_EA_Paused         = false;
ulong         g_HedgeTicket       = 0;   // Ticket ของ Hedge Order

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit() {
    Print("TTrades ICT Master v3.00 | Recovery Suite Initialized");
    trade.SetExpertMagicNumber(20261337);

    // Check Config Conflict
    if(Inp_RecoveryMode == RECOVERY_HYBRID) {
        Print("⚠️ HYBRID Mode: Hedge แล้วจึง Average ต่อ");
    }

    // Init Daily Tracking
    ResetDailyStats();
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    Comment("");
    Print("EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| MAIN TICK                                                        |
//+------------------------------------------------------------------+
void OnTick() {
    // --- 1. Safety Guards ---
    if(!RunSafetyChecks()) return;

    // --- 2. Reset Daily Stats หากวันใหม่ ---
    CheckNewDay();

    // --- 3. Update Basket State ---
    UpdateBasketState();

    // --- 4. Exit Management ---
    ManageExits();

    // --- 5. Recovery System ---
    if(Inp_RecoveryMode != RECOVERY_NONE) {
        ManageRecovery();
    }

    // --- 6. Basket TP Check ---
    if(Inp_Use_BasketTP && g_BasketState != BASKET_EMPTY) {
        CheckBasketTP();
    }

    // --- 7. New Signal Entry ---
    if(g_BasketState == BASKET_EMPTY) {
        TryNewEntry();
    }

    // --- 8. Update Dashboard ---
    UpdateDashboard();
}

//+------------------------------------------------------------------+
//| SAFETY CHECKS                                                    |
//+------------------------------------------------------------------+
bool RunSafetyChecks() {
    // Spread Filter
    double spread = SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    if(spread > Inp_MaxSpread) return false;

    // Max Drawdown
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    if(balance > 0) {
        double dd = (balance - equity) / balance * 100.0;
        if(dd >= Inp_MaxDrawdown) {
            if(!g_EA_Paused) {
                Print("🛑 MAX DRAWDOWN HIT! EA Paused. DD=", DoubleToString(dd, 2), "%");
                g_EA_Paused = true;
            }
            return false;
        }
    }

    // Daily Loss Limit
    if(IsDailyLossLimitHit()) {
        if(!g_EA_Paused) {
            Print("🛑 DAILY LOSS LIMIT HIT! EA Paused for today.");
            g_EA_Paused = true;
        }
        return false;
    }

    g_EA_Paused = false;
    return true;
}

//+------------------------------------------------------------------+
//| DAILY STATS MANAGEMENT                                           |
//+------------------------------------------------------------------+
void ResetDailyStats() {
    g_DayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DayStartTime    = TimeCurrent();
    g_EA_Paused       = false;
    Print("📅 Daily Stats Reset. Balance: ", DoubleToString(g_DayStartBalance, 2));
}

void CheckNewDay() {
    MqlDateTime now, dayStart;
    TimeToStruct(TimeCurrent(), now);
    TimeToStruct(g_DayStartTime, dayStart);
    if(now.day != dayStart.day) {
        ResetDailyStats();
    }
}

bool IsDailyLossLimitHit() {
    if(g_DayStartBalance <= 0) return false;
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    double pnlPct  = (equity - g_DayStartBalance) / g_DayStartBalance * 100.0;
    return (pnlPct <= -Inp_DailyLossLimit);
}

//+------------------------------------------------------------------+
//| BASKET STATE MACHINE                                             |
//+------------------------------------------------------------------+
void UpdateBasketState() {
    int buys = 0, sells = 0;
    ScanPositions(buys, sells, NULL, NULL, NULL, NULL);

    if(buys == 0 && sells == 0) {
        // Basket หมดแล้ว Reset ทุก State
        if(g_BasketState != BASKET_EMPTY) {
            Print("✅ Basket Closed. Resetting State.");
            g_BasketState    = BASKET_EMPTY;
            g_AvgOrderCount  = 0;
            g_HedgeTriggered = false;
            g_HedgeTicket    = 0;
        }
    }
    else if(buys > 0 && sells > 0) {
        g_BasketState = BASKET_HEDGED;
    }
    else if(g_AvgOrderCount > 0) {
        g_BasketState = BASKET_AVG;
    }
    else {
        g_BasketState = BASKET_NORMAL;
    }
}

//+------------------------------------------------------------------+
//| POSITION SCANNER (Helper)                                       |
//+------------------------------------------------------------------+
void ScanPositions(
    int    &buyCount,
    int    &sellCount,
    double *avgBuyPrice,   // Weighted Avg Entry
    double *avgSellPrice,
    double *totalBuyLots,
    double *totalSellLots
) {
    buyCount  = 0; sellCount  = 0;
    double wBuy = 0, wSell = 0, vBuy = 0, vSell = 0;

    for(int i = 0; i < PositionsTotal(); i++) {
        if(PositionGetSymbol(i) != Symbol()) continue;
        if(PositionGetInteger(POSITION_MAGIC) != 20261337) continue;

        double vol  = PositionGetDouble(POSITION_VOLUME);
        double open = PositionGetDouble(POSITION_PRICE_OPEN);

        if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
            buyCount++;
            wBuy += open * vol;
            vBuy += vol;
        } else {
            sellCount++;
            wSell += open * vol;
            vSell += vol;
        }
    }

    if(avgBuyPrice  != NULL) *avgBuyPrice  = (vBuy  > 0) ? wBuy  / vBuy  : 0;
    if(avgSellPrice != NULL) *avgSellPrice = (vSell > 0) ? wSell / vSell : 0;
    if(totalBuyLots  != NULL) *totalBuyLots  = vBuy;
    if(totalSellLots != NULL) *totalSellLots = vSell;
}

//+------------------------------------------------------------------+
//| RECOVERY MANAGEMENT (Core)                                       |
//+------------------------------------------------------------------+
void ManageRecovery() {
    // Bar Filter: Recovery ทำได้ครั้งเดียวต่อแท่ง
    datetime currentBar = iTime(Symbol(), Inp_LTF_Entry, 0);
    if(currentBar == g_LastRecoveryBar) return;

    int    buyCount = 0, sellCount = 0;
    double avgBuyPrice = 0, avgSellPrice = 0;
    double totalBuyLots = 0, totalSellLots = 0;

    ScanPositions(buyCount, sellCount,
                  &avgBuyPrice, &avgSellPrice,
                  &totalBuyLots, &totalSellLots);

    if(buyCount == 0 && sellCount == 0) return;

    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double pt  = Point();

    // ========================================
    // MODE: AVERAGING ONLY
    // ========================================
    if(Inp_RecoveryMode == RECOVERY_AVG) {
        ExecuteAveraging(buyCount, sellCount,
                         avgBuyPrice, avgSellPrice,
                         totalBuyLots, totalSellLots,
                         bid, ask, pt);
        g_LastRecoveryBar = currentBar;
    }

    // ========================================
    // MODE: HEDGE ONLY
    // ========================================
    else if(Inp_RecoveryMode == RECOVERY_HEDGE) {
        ExecuteHedge(buyCount, sellCount,
                     avgBuyPrice, avgSellPrice,
                     totalBuyLots, totalSellLots,
                     bid, ask, pt);
        g_LastRecoveryBar = currentBar;
    }

    // ========================================
    // MODE: HYBRID (Hedge แล้ว Average ต่อ)
    // ========================================
    else if(Inp_RecoveryMode == RECOVERY_HYBRID) {
        if(!g_HedgeTriggered) {
            // Step 1: Hedge ก่อน
            ExecuteHedge(buyCount, sellCount,
                         avgBuyPrice, avgSellPrice,
                         totalBuyLots, totalSellLots,
                         bid, ask, pt);
        } else {
            // Step 2: Avg บน Hedge Side
            ExecuteAveraging(buyCount, sellCount,
                             avgBuyPrice, avgSellPrice,
                             totalBuyLots, totalSellLots,
                             bid, ask, pt);
        }
        g_LastRecoveryBar = currentBar;
    }
}

//+------------------------------------------------------------------+
//| AVERAGING LOGIC                                                  |
//+------------------------------------------------------------------+
void ExecuteAveraging(
    int buys, int sells,
    double avgBuyPx, double avgSellPx,
    double buyLots, double sellLots,
    double bid, double ask, double pt
) {
    // --- Long Averaging ---
    if(buys > 0 && buys < Inp_Max_Avg_Orders) {
        // Dynamic Step: เพิ่ม Step ทุกครั้งที่ Avg
        double step = Inp_Avg_Step;
        if(Inp_Use_Dynamic_Step) {
            step = Inp_Avg_Step * (1.0 + (g_AvgOrderCount * 0.5));
        }

        double avgTrigger = avgBuyPx - (step * pt);
        if(bid <= avgTrigger) {
            double newLot = NormalizeLot(buyLots * Inp_Avg_Multiplier);
            Print("📈 AVG BUY #", buys + 1,
                  " | AvgEntry=", DoubleToString(avgBuyPx, 5),
                  " | Trigger=", DoubleToString(avgTrigger, 5),
                  " | Lot=", DoubleToString(newLot, 2));

            // SL ใหม่ = ต่ำกว่า Avg Price ปัจจุบัน
            double newSL = bid - (Inp_SL_Buffer * 3 * pt);
            double newTP = GetBasketBreakevenTP(POSITION_TYPE_BUY,
                                                 buyLots, avgBuyPx,
                                                 newLot, ask);
            if(ExecuteRecoveryTrade(ORDER_TYPE_BUY, newLot, newSL, newTP)) {
                g_AvgOrderCount++;
                UpdateAllBuySL(newSL); // Sync SL ทุก Buy Order
            }
        }
    }

    // --- Short Averaging ---
    if(sells > 0 && sells < Inp_Max_Avg_Orders) {
        double step = Inp_Avg_Step;
        if(Inp_Use_Dynamic_Step) {
            step = Inp_Avg_Step * (1.0 + (g_AvgOrderCount * 0.5));
        }

        double avgTrigger = avgSellPx + (step * pt);
        if(ask >= avgTrigger) {
            double newLot = NormalizeLot(sellLots * Inp_Avg_Multiplier);
            Print("📉 AVG SELL #", sells + 1,
                  " | AvgEntry=", DoubleToString(avgSellPx, 5),
                  " | Trigger=", DoubleToString(avgTrigger, 5),
                  " | Lot=", DoubleToString(newLot, 2));

            double newSL = ask + (Inp_SL_Buffer * 3 * pt);
            double newTP = GetBasketBreakevenTP(POSITION_TYPE_SELL,
                                                 sellLots, avgSellPx,
                                                 newLot, bid);
            if(ExecuteRecoveryTrade(ORDER_TYPE_SELL, newLot, newSL, newTP)) {
                g_AvgOrderCount++;
                UpdateAllSellSL(newSL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| HEDGE LOGIC                                                      |
//+------------------------------------------------------------------+
void ExecuteHedge(
    int buys, int sells,
    double avgBuyPx, double avgSellPx,
    double buyLots, double sellLots,
    double bid, double ask, double pt
) {
    // Hedge ได้ครั้งเดียว
    if(g_HedgeTriggered) return;

    // --- Hedge Buy Position (เปิด Sell Hedge) ---
    if(buys > 0 && sells == 0) {
        double hedgeTrigger = avgBuyPx - (Inp_Hedge_Dist * pt);
        if(bid <= hedgeTrigger) {
            double hedgeLot = NormalizeLot(buyLots * Inp_Hedge_LotMult);

            // คำนวณ TP บน Hedge
            double hedgeSL = 0, hedgeTP = 0;
            if(Inp_Hedge_Use_TP) {
                double risk = Inp_Hedge_Dist * pt;
                hedgeTP = bid - (risk * Inp_Hedge_TP_RR);
            }

            Print("🛡️ HEDGE SELL triggered.",
                  " AvgBuy=", DoubleToString(avgBuyPx, 5),
                  " Trigger=", DoubleToString(hedgeTrigger, 5),
                  " HedgeLot=", DoubleToString(hedgeLot, 2));

            if(ExecuteRecoveryTrade(ORDER_TYPE_SELL, hedgeLot, hedgeSL, hedgeTP)) {
                g_HedgeTriggered = true;
            }
        }
    }

    // --- Hedge Sell Position (เปิด Buy Hedge) ---
    if(sells > 0 && buys == 0) {
        double hedgeTrigger = avgSellPx + (Inp_Hedge_Dist * pt);
        if(ask >= hedgeTrigger) {
            double hedgeLot = NormalizeLot(sellLots * Inp_Hedge_LotMult);

            double hedgeSL = 0, hedgeTP = 0;
            if(Inp_Hedge_Use_TP) {
                double risk = Inp_Hedge_Dist * pt;
                hedgeTP = ask + (risk * Inp_Hedge_TP_RR);
            }

            Print("🛡️ HEDGE BUY triggered.",
                  " AvgSell=", DoubleToString(avgSellPx, 5),
                  " Trigger=", DoubleToString(hedgeTrigger, 5),
                  " HedgeLot=", DoubleToString(hedgeLot, 2));

            if(ExecuteRecoveryTrade(ORDER_TYPE_BUY, hedgeLot, hedgeSL, hedgeTP)) {
                g_HedgeTriggered = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| คำนวณ TP สำหรับ Breakeven ของ Basket                            |
//+------------------------------------------------------------------+
double GetBasketBreakevenTP(
    ENUM_POSITION_TYPE dir,
    double existingLots, double existingAvgPx,
    double newLots, double newPx
) {
    double totalLots  = existingLots + newLots;
    double weightedPx = (existingLots * existingAvgPx + newLots * newPx) / totalLots;
    double spread     = SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                       - SymbolInfoDouble(Symbol(), SYMBOL_BID);

    // TP = Weighted Avg + Buffer สำหรับ Breakeven + กำไรเล็กน้อย
    double bufferPts = (Inp_SL_Buffer * 2) * Point();
    if(dir == POSITION_TYPE_BUY)
        return weightedPx + spread + bufferPts;
    else
        return weightedPx - spread - bufferPts;
}

//+------------------------------------------------------------------+
//| BASKET TP CHECK                                                  |
//+------------------------------------------------------------------+
void CheckBasketTP() {
    double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity      = AccountInfoDouble(ACCOUNT_EQUITY);
    double floatProfit = equity - balance;
    double targetProfit = balance * (Inp_BasketTP_Pct / 100.0);

    // Basket Max Loss → Force Close
    double maxLoss = -balance * (Inp_BasketMaxLoss / 100.0);
    if(floatProfit <= maxLoss) {
        Print("💀 BASKET MAX LOSS HIT! Force closing all. P&L=",
              DoubleToString(floatProfit, 2));
        CloseAllPositions("BasketMaxLoss");
        return;
    }

    // Basket TP Hit
    if(floatProfit >= targetProfit) {
        Print("🎯 BASKET TP HIT! P&L=", DoubleToString(floatProfit, 2),
              " | Target=", DoubleToString(targetProfit, 2));
        CloseAllPositions("BasketTP");
    }
}

//+------------------------------------------------------------------+
//| CLOSE ALL POSITIONS                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason) {
    g_BasketState = BASKET_CLOSING;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != 20261337) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        trade.PositionClose(ticket);
        Print("🔒 Closed ticket #", ticket, " | Reason: ", reason);
    }
}

//+------------------------------------------------------------------+
//| UPDATE ALL BUY/SELL SL (Sync SL ทุก Order ใน Basket)           |
//+------------------------------------------------------------------+
void UpdateAllBuySL(double newSL) {
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != 20261337) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
        double curTP = PositionGetDouble(POSITION_TP);
        trade.PositionModify(ticket, newSL, curTP);
    }
}

void UpdateAllSellSL(double newSL) {
    for(int i = 0; i < PositionsTotal(); i++) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != 20261337) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
        double curTP = PositionGetDouble(POSITION_TP);
        trade.PositionModify(ticket, newSL, curTP);
    }
}

//+------------------------------------------------------------------+
//| EXIT MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void ManageExits() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetInteger(POSITION_MAGIC) != 20261337) continue;
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;

        // Skip Recovery Orders (manage ด้วย Basket TP แทน)
        if(g_BasketState == BASKET_AVG || g_BasketState == BASKET_HEDGED) continue;

        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL  = PositionGetDouble(POSITION_SL);
        double currentTP  = PositionGetDouble(POSITION_TP);
        bool   isBuy      = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
        double curPrice   = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_BID)
                                  : SymbolInfoDouble(Symbol(), SYMBOL_ASK);

        double nSL = currentSL;
        bool   mod = false;

        // --- Breakeven ---
        if(Inp_Use_BE && currentSL != 0) {
            double risk = MathAbs(entryPrice - currentSL);
            double pips = isBuy ? (curPrice - entryPrice)
                                : (entryPrice - curPrice);
            if(risk > 0 && pips >= risk * Inp_BE_TriggerRR) {
                if(isBuy && nSL < entryPrice) {
                    nSL = entryPrice; mod = true;
                    Print("⚙️ BE: Buy ticket #", ticket, " SL→Entry");
                }
                if(!isBuy && (nSL > entryPrice || nSL == 0)) {
                    nSL = entryPrice; mod = true;
                    Print("⚙️ BE: Sell ticket #", ticket, " SL→Entry");
                }
            }
        }

        // --- Candle Trail ---
        if(Inp_Use_CandleTrail) {
            if(isBuy) {
                double prevLow = iLow(Symbol(), Inp_LTF_Entry, 1);
                if(prevLow > nSL) { nSL = prevLow; mod = true; }
            } else {
                double prevHigh = iHigh(Symbol(), Inp_LTF_Entry, 1);
                if(nSL == 0 || prevHigh < nSL) { nSL = prevHigh; mod = true; }
            }
        }

        if(mod && nSL != currentSL) {
            trade.PositionModify(ticket, nSL, currentTP);
        }
    }
}

//+------------------------------------------------------------------+
//| NEW ENTRY LOGIC                                                  |
//+------------------------------------------------------------------+
void TryNewEntry() {
    if(Inp_UseKillzones && !IsInKillzone()) return;

    datetime currentBar = iTime(Symbol(), Inp_LTF_Entry, 0);
    if(currentBar == g_LastEntryBarTime) return;

    int bias = DetermineBias();
    if(bias == 0) return;

    if(bias == 1 && CheckLongEntry()) {
        double lot = Inp_UseRiskPercent ? CalcLotByRisk(true) : Inp_LotSize;
        if(ExecuteInitialTrade(ORDER_TYPE_BUY, lot)) {
            g_LastEntryBarTime = currentBar;
            g_BasketState = BASKET_NORMAL;
        }
    }
    else if(bias == -1 && CheckShortEntry()) {
        double lot = Inp_UseRiskPercent ? CalcLotByRisk(false) : Inp_LotSize;
        if(ExecuteInitialTrade(ORDER_TYPE_SELL, lot)) {
            g_LastEntryBarTime = currentBar;
            g_BasketState = BASKET_NORMAL;
        }
    }
}

//+------------------------------------------------------------------+
//| LOT CALCULATION BY RISK %                                        |
//+------------------------------------------------------------------+
double CalcLotByRisk(bool isBuy) {
    double entryPrice = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                              : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double slPrice    = isBuy
        ? iLow(Symbol(), Inp_LTF_Entry, 1)  - (Inp_SL_Buffer * Point())
        : iHigh(Symbol(), Inp_LTF_Entry, 1) + (Inp_SL_Buffer * Point());

    double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmt    = balance * (Inp_RiskPercent / 100.0);
    double slDist     = MathAbs(entryPrice - slPrice);

    if(slDist <= 0) return Inp_LotSize;

    double tickVal    = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double tickSize   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double lot        = riskAmt / ((slDist / tickSize) * tickVal);
    return NormalizeLot(lot);
}

//+------------------------------------------------------------------+
//| EXECUTE INITIAL TRADE                                            |
//+------------------------------------------------------------------+
bool ExecuteInitialTrade(ENUM_ORDER_TYPE type, double lots) {
    bool isBuy  = (type == ORDER_TYPE_BUY);
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                         : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double sl = isBuy
        ? iLow(Symbol(), Inp_LTF_Entry, 1)  - (Inp_SL_Buffer * Point())
        : iHigh(Symbol(), Inp_LTF_Entry, 1) + (Inp_SL_Buffer * Point());
    double tp = 0;
    if(Inp_Use_RR) {
        double risk = MathAbs(price - sl);
        tp = isBuy ? (price + risk * Inp_TargetRR)
                   : (price - risk * Inp_TargetRR);
    }
    bool res = trade.PositionOpen(Symbol(), type, lots, price, sl, tp, "ICT_Initial");
    if(res) Print("🟢 Initial Trade: ", EnumToString(type),
                  " Lot=", lots, " SL=", sl, " TP=", tp);
    return res;
}

//+------------------------------------------------------------------+
//| EXECUTE RECOVERY TRADE                                           |
//+------------------------------------------------------------------+
bool ExecuteRecoveryTrade(ENUM_ORDER_TYPE type, double lots, double sl, double tp) {
    bool isBuy  = (type == ORDER_TYPE_BUY);
    double price = isBuy ? SymbolInfoDouble(Symbol(), SYMBOL_ASK)
                         : SymbolInfoDouble(Symbol(), SYMBOL_BID);
    bool res = trade.PositionOpen(Symbol(), type, lots, price, sl, tp, "ICT_Recovery");
    if(res) Print("🔄 Recovery Trade: ", EnumToString(type),
                  " Lot=", lots, " SL=", sl, " TP=", tp);
    return res;
}

//+------------------------------------------------------------------+
//| NORMALIZE LOT                                                    |
//+------------------------------------------------------------------+
double NormalizeLot(double lots) {
    double minLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
    if(lotStep <= 0) lotStep = 0.01;
    lots = MathFloor(lots / lotStep) * lotStep;
    lots = MathMax(minLot, MathMin(maxLot, lots));
    return lots;
}

//+------------------------------------------------------------------+
//| SIGNALS                                                          |
//+------------------------------------------------------------------+
bool IsInKillzone() {
    MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
    int hhmm = dt.hour * 100 + dt.min;
    if(Inp_KZ_London   && hhmm >= 800  && hhmm <= 1100) return true;
    if(Inp_KZ_NewYork  && hhmm >= 1330 && hhmm <= 1600) return true;
    if(Inp_KZ_Asian    && hhmm >= 100  && hhmm <= 400)  return true;
    return false;
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
    if(Inp_Use_IFVG && CheckIFVGShort()) return true;
    if(Inp_Use_C2C3 && CheckC2C3_Short()) return true;
    return false;
}

bool CheckC2C3_Long() {
    double c1L = iLow(Symbol(),  Inp_LTF_Entry, 3);
    double c1H = iHigh(Symbol(), Inp_LTF_Entry, 3);
    double c2C = iClose(Symbol(),Inp_LTF_Entry, 2);
    double c2H = iHigh(Symbol(), Inp_LTF_Entry, 2);
    double c3C = iClose(Symbol(),Inp_LTF_Entry, 1);
    if(c1L <= iLow(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2C > c1H || (c2C <= c1H && c3C > c2H)) return true;
    }
    return false;
}

bool CheckC2C3_Short() {
    double c1H = iHigh(Symbol(), Inp_LTF_Entry, 3);
    double c1L = iLow(Symbol(),  Inp_LTF_Entry, 3);
    double c2C = iClose(Symbol(),Inp_LTF_Entry, 2);
    double c2L = iLow(Symbol(),  Inp_LTF_Entry, 2);
    double c3C = iClose(Symbol(),Inp_LTF_Entry, 1);
    if(c1H >= iHigh(Symbol(), Inp_LTF_Entry, 5)) {
        if(c2C < c1L || (c2C >= c1L && c3C < c2L)) return true;
    }
    return false;
}

bool CheckIFVGLong() {
    for(int i = 5; i <= 15; i++) {
        double h3 = iHigh(Symbol(), Inp_LTF_Entry, i);
        double l1 = iLow(Symbol(),  Inp_LTF_Entry, i - 2);
        if(l1 > h3 && iClose(Symbol(), Inp_LTF_Entry, 2) > l1) {
            if(iLow(Symbol(),   Inp_LTF_Entry, 1) <= l1 &&
               iClose(Symbol(), Inp_LTF_Entry, 1)  > l1) return true;
        }
    }
    return false;
}

bool CheckIFVGShort() {
    for(int i = 5; i <= 15; i++) {
        double l3 = iLow(Symbol(),  Inp_LTF_Entry, i);
        double h1 = iHigh(Symbol(), Inp_LTF_Entry, i - 2);
        if(h1 < l3 && iClose(Symbol(), Inp_LTF_Entry, 2) < h1) {
            if(iHigh(Symbol(),  Inp_LTF_Entry, 1) >= h1 &&
               iClose(Symbol(), Inp_LTF_Entry, 1)  < h1) return true;
        }
    }
    return false;
}

bool CheckCISD_Long() {
    for(int i = 2; i <= 10; i++) {
        if(iClose(Symbol(), Inp_LTF_Entry, i) < iOpen(Symbol(), Inp_LTF_Entry, i)) {
            if(iClose(Symbol(), Inp_LTF_Entry, 1) > iHigh(Symbol(), Inp_LTF_Entry, i))
                return true;
            break;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| DASHBOARD                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard() {
    string stateStr = "";
    switch(g_BasketState) {
        case BASKET_EMPTY:   stateStr = "💤 Empty";   break;
        case BASKET_NORMAL:  stateStr = "🟢 Normal";  break;
        case BASKET_AVG:     stateStr = "🔄 Averaging"; break;
        case BASKET_HEDGED:  stateStr = "🛡️ Hedged";  break;
        case BASKET_CLOSING: stateStr = "🔒 Closing"; break;
    }

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
    double dd      = balance > 0 ? (balance - equity) / balance * 100.0 : 0;
    double dayPnL  = (equity - g_DayStartBalance);

    int    buys = 0, sells = 0;
    double avgB = 0, avgS = 0, lotsB = 0, lotsS = 0;
    ScanPositions(buys, sells, &avgB, &avgS, &lotsB, &lotsS);

    string modeStr = "";
    switch(Inp_RecoveryMode) {
        case RECOVERY_NONE:   modeStr = "OFF";    break;
        case RECOVERY_AVG:    modeStr = "AVG";    break;
        case RECOVERY_HEDGE:  modeStr = "HEDGE";  break;
        case RECOVERY_HYBRID: modeStr = "HYBRID"; break;
    }

    string dash = "";
    dash += "╔══════════════════════════════╗\n";
    dash += "║   TTrades ICT v3.00          ║\n";
    dash += "╠══════════════════════════════╣\n";
    dash += StringFormat("║ Mode    : %-20s║\n", modeStr);
    dash += StringFormat("║ State   : %-20s║\n", stateStr);
    dash += StringFormat("║ KZ      : %-20s║\n", IsInKillzone()?"✅ Active":"⏸ Inactive");
    dash += StringFormat("║ Bias    : %-20s║\n", DetermineBias()==1?"🐂 BULL":"🐻 BEAR");
    dash += "╠══════════════════════════════╣\n";
    dash += StringFormat("║ Buys    : %-3d @ %-15s║\n", buys, DoubleToString(avgB,5));
    dash += StringFormat("║ Sells   : %-3d @ %-15s║\n", sells, DoubleToString(avgS,5));
    dash += StringFormat("║ AvgOrds : %-20d║\n", g_AvgOrderCount);
    dash += StringFormat("║ Hedged  : %-20s║\n", g_HedgeTriggered?"YES":"NO");
    dash += "╠══════════════════════════════╣\n";
    dash += StringFormat("║ Balance : %-20s║\n", DoubleToString(balance,2));
    dash += StringFormat("║ Equity  : %-20s║\n", DoubleToString(equity,2));
    dash += StringFormat("║ Day P&L : %-20s║\n", DoubleToString(dayPnL,2));
    dash += StringFormat("║ DD      : %-17s%%  ║\n", DoubleToString(dd,2));
    if(g_EA_Paused)
    dash += "║  ⚠️  EA PAUSED               ║\n";
    dash += "╚══════════════════════════════╝";
    Comment(dash);
}
