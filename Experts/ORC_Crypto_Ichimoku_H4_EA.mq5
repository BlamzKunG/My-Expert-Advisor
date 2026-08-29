//+------------------------------------------------------------------+
//|                                   ORC_Crypto_Ichimoku_H4_EA.mq5 |
//|                                  Copyright 2026, Antigravity AI  |
//|               Strategy based on YouTube Channel: ORC Crypto     |
//|               "แจกระบบเทรดฟรี! สูตรกินคำใหญ่ RR 1:3" (Timeframe H4)   |
//+------------------------------------------------------------------+
#property copyright "ORC Crypto Trading Strategy - Antigravity AI"
#property link      "https://youtube.com"
#property version   "1.00"
#property description "EA ตามสูตรระบบเทรดกินคำใหญ่ RR 1:3 จากช่อง ORC Crypto (Timeframe 4H)"
#property description "1. Ichimoku Cloud (9, 26, 52)"
#property description "2. EMA 200 (เส้นบอกเทรนด์หลัก)"
#property description "3. ADX 14 (กรองความแรงเทรนด์ ADX > 25)"
#property description "4. ATR 14 (คำนวณ Stop Loss 2x ATR จาก High/Low แท่งอ้างอิง)"
#property description "5. Take Profit RR 1:3, Risk 3% Compound, Time Stop 480 ชม. (20 วัน)"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input ulong    InpMagicNumber       = 884420;      // Magic Number (รหัสอ้างอิงออเดอร์)
input string   InpTradeComment      = "ORC_H4_EA";  // Order Comment
input ulong    InpSlippage          = 30;          // Max Slippage (Points)

input group "=== Risk & Money Management ==="
input double   InpRiskPercent       = 3.0;         // ความเสี่ยงต่อไม้ (% Compound ของพอร์ต)
input double   InpDefaultLot        = 0.01;        // Lot เริ่มต้น (กรณีไม่ใช้ Risk %)
input bool     InpUseEquityForRisk  = true;        // คำนวณความเสี่ยงจาก Equity (true=Equity, false=Balance)

input group "=== Ichimoku Settings ==="
input int      InpTenkan            = 9;           // Tenkan-sen Period (Conversion Line)
input int      InpKijun             = 26;          // Kijun-sen Period (Base Line)
input int      InpSenkouSpanB       = 52;          // Senkou Span B Period

input group "=== EMA Settings ==="
input int      InpEMAPeriod         = 200;         // EMA Trend Line Period

input group "=== ADX Settings ==="
input int      InpADXPeriod         = 14;          // ADX Period
input double   InpADXThreshold      = 25.0;        // ค่า ADX ขั้นต่ำสำหรับกรองเทรนด์ (> 25)

input group "=== ATR & Risk-Reward Settings ==="
input int      InpATRPeriod         = 14;          // ATR Period
input double   InpATRMultiplier     = 2.0;         // ATR Multiplier สำหรับตั้ง SL (2x ATR)
input double   InpRRRatio           = 3.0;         // Risk to Reward Ratio (1:3 -> 3.0)

input group "=== Time Stop Settings ==="
input bool     InpUseTimeStop       = true;        // เปิดใช้งาน Time Stop
input int      InpMaxTradeHours     = 480;         // ระยะเวลาถือออเดอร์สูงสุด (ชั่วโมง) [480 ชม. = 20 วัน]

input group "=== Display Settings ==="
input bool     InpShowDashboard     = true;        // แสดง On-Screen Dashboard บนกราฟ

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES & HANDLES                                       |
//+------------------------------------------------------------------+
CTrade         trade;
int            hIchimoku            = INVALID_HANDLE;
int            hEMA                 = INVALID_HANDLE;
int            hADX                 = INVALID_HANDLE;
int            hATR                 = INVALID_HANDLE;
datetime       g_lastBarTime        = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // กำหนดค่าเริ่มต้นให้กับ CTrade object
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   // สร้าง Indicator Handles
   hIchimoku = iIchimoku(_Symbol, _Period, InpTenkan, InpKijun, InpSenkouSpanB);
   if(hIchimoku == INVALID_HANDLE)
   {
      Print("Error creating Ichimoku handle! Code: ", GetLastError());
      return(INIT_FAILED);
   }

   hEMA = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(hEMA == INVALID_HANDLE)
   {
      Print("Error creating EMA handle! Code: ", GetLastError());
      return(INIT_FAILED);
   }

   hADX = iADX(_Symbol, _Period, InpADXPeriod);
   if(hADX == INVALID_HANDLE)
   {
      Print("Error creating ADX handle! Code: ", GetLastError());
      return(INIT_FAILED);
   }

   hATR = iATR(_Symbol, _Period, InpATRPeriod);
   if(hATR == INVALID_HANDLE)
   {
      Print("Error creating ATR handle! Code: ", GetLastError());
      return(INIT_FAILED);
   }

   Print("ORC Crypto Ichimoku H4 EA Initialized Successfully.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // ลบ Indicator Handles เพื่อคืน Memory
   if(hIchimoku != INVALID_HANDLE) IndicatorRelease(hIchimoku);
   if(hEMA != INVALID_HANDLE)      IndicatorRelease(hEMA);
   if(hADX != INVALID_HANDLE)      IndicatorRelease(hADX);
   if(hATR != INVALID_HANDLE)      IndicatorRelease(hATR);

   // ลบคอมเมนต์หน้าจอ
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. เช็คและตัดออเดอร์ด้วย Time Stop (หากเปิดออเดอร์นานเกินกว่ากำหนด)
   CheckTimeStop();

   // 2. อัปเดต Dashboard แสดงผลบนกราฟ
   if(InpShowDashboard) UpdateDashboard();

   // 3. ตรวจสอบว่ามีแท่งเทียนใหม่ปิดตัวแล้วหรือไม่ (สัญญาณเข้าที่ราคาเปิดแท่งถัดไป)
   if(!IsNewBar()) return;

   // 4. ตรวจสอบว่ามีออเดอร์เปิดอยู่แล้วหรือไม่ (จำกัด 1 ออเดอร์ต่อสัญลักษณ์/MagicNumber)
   if(HasOpenPosition()) return;

   // 5. ดึงข้อมูลตัวชี้วัดของแท่งเทียนที่เพิ่งปิด (Index 1) และแท่งก่อนหน้า (Index 2)
   double close1 = iClose(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);

   // Ichimoku Buffers:
   // 0: TENKANSEN, 1: KIJUNSEN, 2: SENKOUSPANA, 3: SENKOUSPANB
   double tenkan[3], kijun[3], spanA[3], spanB[3];
   if(CopyBuffer(hIchimoku, TENKANSEN_LINE, 0, 3, tenkan) < 3 ||
      CopyBuffer(hIchimoku, KIJUNSEN_LINE, 0, 3, kijun) < 3 ||
      CopyBuffer(hIchimoku, SENKOUSPANA_LINE, 0, 3, spanA) < 3 ||
      CopyBuffer(hIchimoku, SENKOUSPANB_LINE, 0, 3, spanB) < 3)
   {
      Print("Failed to copy Ichimoku buffers");
      return;
   }

   // กำหนด Array เป็น Series เพื่อให้ index 1 = แท่งล่าสุดที่ปิดตัว
   ArraySetAsSeries(tenkan, true);
   ArraySetAsSeries(kijun, true);
   ArraySetAsSeries(spanA, true);
   ArraySetAsSeries(spanB, true);

   // EMA Buffer
   double ema[2];
   if(CopyBuffer(hEMA, 0, 0, 2, ema) < 2) return;
   ArraySetAsSeries(ema, true);

   // ADX Buffer (Buffer 0 = Main ADX)
   double adx[2];
   if(CopyBuffer(hADX, 0, 0, 2, adx) < 2) return;
   ArraySetAsSeries(adx, true);

   // ATR Buffer
   double atr[2];
   if(CopyBuffer(hATR, 0, 0, 2, atr) < 2) return;
   ArraySetAsSeries(atr, true);

   // --- เช็คเงื่อนไขการเข้าออเดอร์ ---
   
   // ข้อมูลเมฆ (Kumo) ณ แท่งอ้างอิง (Index 1)
   bool isGreenCloud = (spanA[1] > spanB[1]);
   bool isRedCloud   = (spanA[1] < spanB[1]);
   double upperCloud = MathMax(spanA[1], spanB[1]);
   double lowerCloud = MathMin(spanA[1], spanB[1]);

   // เงื่อนไขฝั่ง BUY (Long) [ตามคลิป ORC Crypto]:
   // 1. ราคาปิดแท่งเทียนอยู่เหนือเมฆ Ichimoku และเมฆเป็นสีเขียว
   // 2. เส้น Conversion Line (Tenkan 9) ตัดขึ้นเหนือเส้น Base Line (Kijun 26)
   // 3. แท่งเทียนปิดตัวอยู่เหนือเส้น EMA 200
   // 4. ค่า ADX > 25
   bool buyCondition = (close1 > upperCloud) && 
                        isGreenCloud && 
                       (tenkan[1] > kijun[1] && tenkan[2] <= kijun[2]) && 
                       (close1 > ema[1]) && 
                       (adx[1] > InpADXThreshold);

   // เงื่อนไขฝั่ง SELL (Short) [ตามคลิป ORC Crypto]:
   // 1. ราคาปิดแท่งเทียนอยู่ใต้เมฆ Ichimoku และเมฆเป็นสีแดง
   // 2. เส้น Conversion Line (Tenkan 9) อยู่ต่ำกว่าและตัดเส้น Base Line (Kijun 26) ลงมา
   // 3. แท่งเทียนปิดตัวอยู่ใต้เส้น EMA 200
   // 4. ค่า ADX > 25
   bool sellCondition = (close1 < lowerCloud) && 
                         isRedCloud && 
                        (tenkan[1] < kijun[1] && tenkan[2] >= kijun[2]) && 
                        (close1 < ema[1]) && 
                        (adx[1] > InpADXThreshold);

   // --- ดำเนินการเปิดออเดอร์ BUY ---
   if(buyCondition)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // คำนวณ SL: ต่ำสุดของแท่งอ้างอิง (Low[1]) ลบออก 2x ATR
      double slPrice = low1 - (InpATRMultiplier * atr[1]);
      double riskDistance = ask - slPrice;

      if(riskDistance > 0)
      {
         // คำนวณ TP: Risk:Reward 1:3
         double tpPrice = ask + (InpRRRatio * riskDistance);
         
         // คำนวณ Lot Size จากความเสี่ยง 3% Compound
         double lotSize = CalculateLotSize(riskDistance);
         
         slPrice = NormalizeDouble(slPrice, _Digits);
         tpPrice = NormalizeDouble(tpPrice, _Digits);

         PrintFormat("[BUY SIGNAL] Ask: %.5f | Low[1]: %.5f | ATR: %.5f | SL: %.5f | TP: %.5f | Lot: %.2f", 
                     ask, low1, atr[1], slPrice, tpPrice, lotSize);

         trade.Buy(lotSize, _Symbol, ask, slPrice, tpPrice, InpTradeComment);
      }
   }
   // --- ดำเนินการเปิดออเดอร์ SELL ---
   else if(sellCondition)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // คำนวณ SL: สูงสุดของแท่งอ้างอิง (High[1]) บวกเพิ่ม 2x ATR
      double slPrice = high1 + (InpATRMultiplier * atr[1]);
      double riskDistance = slPrice - bid;

      if(riskDistance > 0)
      {
         // คำนวณ TP: Risk:Reward 1:3
         double tpPrice = bid - (InpRRRatio * riskDistance);
         
         // คำนวณ Lot Size จากความเสี่ยง 3% Compound
         double lotSize = CalculateLotSize(riskDistance);
         
         slPrice = NormalizeDouble(slPrice, _Digits);
         tpPrice = NormalizeDouble(tpPrice, _Digits);

         PrintFormat("[SELL SIGNAL] Bid: %.5f | High[1]: %.5f | ATR: %.5f | SL: %.5f | TP: %.5f | Lot: %.2f", 
                     bid, high1, atr[1], slPrice, tpPrice, lotSize);

         trade.Sell(lotSize, _Symbol, bid, slPrice, tpPrice, InpTradeComment);
      }
   }
}

//+------------------------------------------------------------------+
//| Check if a new bar has just opened                               |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime != g_lastBarTime)
   {
      g_lastBarTime = currentBarTime;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if position already exists for this symbol & magic number |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetTicket(i) > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Money Management: Calculate Lot Size based on % Risk             |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
{
   if(InpRiskPercent <= 0.0) return InpDefaultLot;

   double accountValue = InpUseEquityForRisk ? AccountInfoDouble(ACCOUNT_EQUITY) : AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount   = accountValue * (InpRiskPercent / 100.0);

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tickSize <= 0 || tickValue <= 0 || point <= 0 || slDistancePrice <= 0)
      return InpDefaultLot;

   double slPoints = slDistancePrice / point;
   double tickValuePerPoint = tickValue * (point / tickSize);
   double moneyLossPerLot   = slPoints * tickValuePerPoint;

   if(moneyLossPerLot <= 0) return InpDefaultLot;

   double lot = riskAmount / moneyLossPerLot;

   // ปรับแต่งตามข้อกำหนด Volume ของ Broker
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < lotMin) lot = lotMin;
   if(lot > lotMax) lot = lotMax;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Time Stop: Close trade if older than max specified hours        |
//+------------------------------------------------------------------+
void CheckTimeStop()
{
   if(!InpUseTimeStop || InpMaxTradeHours <= 0) return;

   datetime currentTime = TimeCurrent();
   int maxSeconds = InpMaxTradeHours * 3600;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            if((currentTime - openTime) >= maxSeconds)
            {
               PrintFormat("Time Stop Activated: Closing position #%I64u held for %d hours (> %d hrs limit)",
                           ticket, (int)((currentTime - openTime) / 3600), InpMaxTradeHours);
               trade.PositionClose(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Display On-Screen Status Dashboard                               |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double adxVal = 0.0;
   double adxBuf[1];
   if(CopyBuffer(hADX, 0, 1, 1, adxBuf) > 0) adxVal = adxBuf[0];

   double emaVal = 0.0;
   double emaBuf[1];
   if(CopyBuffer(hEMA, 0, 1, 1, emaBuf) > 0) emaVal = emaBuf[0];

   double close1 = iClose(_Symbol, _Period, 1);
   string trendState = (close1 > emaVal) ? "BULLISH (เหนือ EMA 200)" : "BEARISH (ใต้ EMA 200)";
   string adxState   = (adxVal > InpADXThreshold) ? StringFormat("STRONG (%.2f > %.1f)", adxVal, InpADXThreshold) 
                                                  : StringFormat("WEAK (%.2f <= %.1f)", adxVal, InpADXThreshold);

   string posState = HasOpenPosition() ? "มีออเดอร์ถืออยู่ (IN POSITION)" : "รอสัญญาณเข้า (WAITING FOR SIGNAL)";

   string info = "=========================================\n" +
                 "   ORC CRYPTO H4 SYSTEM - EA DASHBOARD   \n" +
                 "=========================================\n" +
                 " Symbol: " + _Symbol + " | Timeframe: " + EnumToString(_Period) + "\n" +
                 " Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + 
                 " | Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE) != 0 ? AccountInfoDouble(ACCOUNT_EQUITY) : 0, 2) + "\n" +
                 " Risk % per trade: " + DoubleToString(InpRiskPercent, 1) + "% | RR Ratio: 1:" + DoubleToString(InpRRRatio, 1) + "\n" +
                 "-----------------------------------------\n" +
                 " Trend (EMA 200): " + trendState + "\n" +
                 " ADX Trend Filter: " + adxState + "\n" +
                 " Position Status: " + posState + "\n" +
                 " Time Stop Limit: " + IntegerToString(InpMaxTradeHours) + " Hours (20 Days)\n" +
                 "=========================================";

   Comment(info);
}
//+------------------------------------------------------------------+
