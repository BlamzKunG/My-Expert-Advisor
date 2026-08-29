//+------------------------------------------------------------------+
//|                                         HaruuSignalReceiver.mq5  |
//|                        Copyright 2026, Haruu Shop Signal System  |
//|                                      http://signal.haruu-shop.com |
//+------------------------------------------------------------------+
#property copyright "Haruu Shop (signal.haruu-shop.com)"
#property link      "http://signal.haruu-shop.com"
#property version   "1.00"
#property description "EA Receiver สำหรับรับสัญญาณ Copy Trade จาก signal.haruu-shop.com"
#property description "แยกตาม Strategy Mode (Breakout, Scalping) และ Risk Level (Low, Medium, High)"

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_STRATEGY_MODE
  {
   MODE_BREAKOUT = 0, // Breakout Mode
   MODE_SCALPING = 1  // Scalping Mode
  };

enum ENUM_RISK_LEVEL
  {
   RISK_LOW    = 0, // Low Risk
   RISK_MEDIUM = 1, // Medium Risk
   RISK_HIGH   = 2  // High Risk
  };

enum ENUM_LOT_TYPE
  {
   LOT_FIXED        = 0, // Fixed Lot Size
   LOT_RISK_PERCENT = 1  // Risk % of Account Balance
  };

//--- Input Parameters
input group "=== Server & Strategy Selection ==="
input string               InpServerURL      = "http://signal.haruu-shop.com"; // Server Base URL
input ENUM_STRATEGY_MODE   InpStrategyMode   = MODE_BREAKOUT;                   // Strategy Mode
input ENUM_RISK_LEVEL      InpRiskLevel      = RISK_LOW;                        // Risk Level

input group "=== Money Management ==="
input ENUM_LOT_TYPE        InpLotType        = LOT_FIXED;     // Lot Calculation Method
input double               InpFixedLot       = 0.01;          // Fixed Lot Size
input double               InpRiskPercent    = 1.0;           // Risk % Per Trade
input ulong                InpSlippage       = 30;            // Max Slippage (Points)

input group "=== EA Settings ==="
input int                  InpClientMagic    = 999111;        // Client Local Magic Number
input int                  InpPollInterval   = 3;             // Poll Interval (Seconds)

//--- Global Variables
CTrade         m_trade;
datetime       m_last_poll_time = 0;
int            m_target_magic   = 111;
string         m_strategy_name  = "";
int            m_total_signals  = 0;
bool           m_connected      = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Determine Target Magic Number based on Mode and Risk
   if(InpStrategyMode == MODE_BREAKOUT)
     {
      if(InpRiskLevel == RISK_LOW)      { m_target_magic = 111; m_strategy_name = "Breakout Low Risk"; }
      else if(InpRiskLevel == RISK_MEDIUM) { m_target_magic = 222; m_strategy_name = "Breakout Medium Risk"; }
      else if(InpRiskLevel == RISK_HIGH)   { m_target_magic = 333; m_strategy_name = "Breakout High Risk"; }
     }
   else if(InpStrategyMode == MODE_SCALPING)
     {
      if(InpRiskLevel == RISK_LOW)      { m_target_magic = 444; m_strategy_name = "Scalping Low Risk"; }
      else if(InpRiskLevel == RISK_MEDIUM) { m_target_magic = 555; m_strategy_name = "Scalping Medium Risk"; }
      else if(InpRiskLevel == RISK_HIGH)   { m_target_magic = 666; m_strategy_name = "Scalping High Risk"; }
     }

   m_trade.SetExpertMagicNumber(InpClientMagic);
   m_trade.SetDeviationInPoints(InpSlippage);

   EventSetTimer(InpPollInterval);
   UpdateChartPanel();

   PrintFormat("[HaruuSignal] EA Initialized. Target: %s (Magic: %d)", m_strategy_name, m_target_magic);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

//+------------------------------------------------------------------+
//| Timer event function                                             |
//+------------------------------------------------------------------+
void OnTimer()
  {
   FetchAndProcessSignals();
   UpdateChartPanel();
  }

//+------------------------------------------------------------------+
//| Fetch signals from server API via WebRequest                     |
//+------------------------------------------------------------------+
void FetchAndProcessSignals()
  {
   string url = InpServerURL + "/api/v1/signals?magic_number=" + IntegerToString(m_target_magic);
   string headers = "User-Agent: HaruuSignalEA/1.0\r\nContent-Type: application/json\r\n";
   char post_data[], result[];
   string result_headers;

   ResetLastError();
   int res = WebRequest("GET", url, headers, 3000, post_data, result, result_headers);

   if(res == 200)
     {
      m_connected = true;
      string response_text = CharArrayToString(result);
      ProcessSignalResponse(response_text);
     }
   else
     {
      m_connected = false;
      PrintFormat("[HaruuSignal] WebRequest Failed. Code: %d, Error: %d. Check URL permissions!", res, GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Parse JSON response & sync client positions                      |
//+------------------------------------------------------------------+
void ProcessSignalResponse(string json)
  {
   // Extract total_signals count
   int total_idx = StringFind(json, "\"total_signals\":");
   if(total_idx >= 0)
     {
      string sub = StringSubstr(json, total_idx + 16, 10);
      m_total_signals = (int)StringToInteger(sub);
     }

   // Master ticket tracking array
   long master_tickets[];
   ArrayResize(master_tickets, 0);

   // Simple JSON parsing loop for signals
   int pos = 0;
   while((pos = StringFind(json, "{\"ticket\":", pos)) >= 0)
     {
      int end_pos = StringFind(json, "}", pos);
      if(end_pos < 0) break;

      string obj = StringSubstr(json, pos, end_pos - pos + 1);
      pos = end_pos + 1;

      // Extract Fields
      long ticket       = (long)ExtractJsonNumber(obj, "ticket");
      string symbol    = ExtractJsonString(obj, "symbol");
      string order_type= ExtractJsonString(obj, "order_type");
      double master_price= ExtractJsonNumber(obj, "open_price");
      double sl        = ExtractJsonNumber(obj, "sl");
      double tp        = ExtractJsonNumber(obj, "tp");

      if(ticket > 0 && StringLen(symbol) > 0)
        {
         int size = ArraySize(master_tickets);
         ArrayResize(master_tickets, size + 1);
         master_tickets[size] = ticket;

         // Sync Open Position
         SyncOpenTrade(ticket, symbol, order_type, master_price, sl, tp);
        }
     }

   // Close client positions that are no longer active on Master
   CloseOrphanedClientTrades(master_tickets);
  }

//+------------------------------------------------------------------+
//| Execute or modify position on Slave                              |
//+------------------------------------------------------------------+
void SyncOpenTrade(long master_ticket, string symbol, string order_type, double master_price, double sl, double tp)
  {
   string comment_tag = "Haruu_M#" + IntegerToString(master_ticket);
   bool already_exists = false;

   // Check existing client positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpClientMagic)
        {
         string pos_comment = PositionGetString(POSITION_COMMENT);
         if(pos_comment == comment_tag)
           {
            already_exists = true;

            // Check if SL/TP needs modification
            double cur_sl = PositionGetDouble(POSITION_SL);
            double cur_tp = PositionGetDouble(POSITION_TP);

            if(MathAbs(cur_sl - sl) > _Point || MathAbs(cur_tp - tp) > _Point)
              {
               m_trade.PositionModify(ticket, sl, tp);
               PrintFormat("[HaruuSignal] Modified SL/TP for Master Ticket #%d", master_ticket);
              }
            break;
           }
        }
     }

   // If not open yet, execute new trade
   if(!already_exists)
     {
      double lot = CalculateLotSize(symbol);
      
      if(order_type == "BUY")
        {
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         if(m_trade.Buy(lot, symbol, ask, sl, tp, comment_tag))
            PrintFormat("[HaruuSignal] OPEN BUY: Symbol %s, Lot %.2f, Master Ticket #%d", symbol, lot, master_ticket);
        }
      else if(order_type == "SELL")
        {
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         if(m_trade.Sell(lot, symbol, bid, sl, tp, comment_tag))
            PrintFormat("[HaruuSignal] OPEN SELL: Symbol %s, Lot %.2f, Master Ticket #%d", symbol, lot, master_ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| Close trades on Slave if Master closed them                      |
//+------------------------------------------------------------------+
void CloseOrphanedClientTrades(const long &master_tickets[])
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionGetInteger(POSITION_MAGIC) == InpClientMagic)
        {
         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "Haruu_M#") == 0)
           {
            long master_ticket = (long)StringToInteger(StringSubstr(comment, 8));
            
            bool found = false;
            for(int j = 0; j < ArraySize(master_tickets); j++)
              {
               if(master_tickets[j] == master_ticket)
                 {
                  found = true;
                  break;
                 }
              }

            if(!found)
              {
               m_trade.PositionClose(ticket);
               PrintFormat("[HaruuSignal] CLOSED position #%d (Master Ticket #%d closed)", ticket, master_ticket);
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on User Setting                         |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol)
  {
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   double lot = InpFixedLot;

   if(InpLotType == LOT_RISK_PERCENT)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_amount = balance * (InpRiskPercent / 100.0);
      lot = NormalizeDouble(risk_amount / 1000.0, 2); // Simple risk calculation
     }

   lot = MathMax(min_lot, MathMin(max_lot, lot));
   lot = MathFloor(lot / lot_step) * lot_step;
   return lot;
  }

//--- JSON Parsing Helpers
double ExtractJsonNumber(string json, string key)
  {
   string search = "\"" + key + "\":";
   int pos = StringFind(json, search);
   if(pos < 0) return 0.0;
   
   int start = pos + StringLen(search);
   int end = StringFind(json, ",", start);
   if(end < 0) end = StringFind(json, "}", start);
   if(end < 0) return 0.0;
   
   string val = StringSubstr(json, start, end - start);
   StringTrimLeft(val); StringTrimRight(val);
   return StringToDouble(val);
  }

string ExtractJsonString(string json, string key)
  {
   string search = "\"" + key + "\":\"";
   int pos = StringFind(json, search);
   if(pos < 0) return "";
   
   int start = pos + StringLen(search);
   int end = StringFind(json, "\"", start);
   if(end < 0) return "";
   
   return StringSubstr(json, start, end - start);
  }

//+------------------------------------------------------------------+
//| Render On-Screen Dashboard Panel                                |
//+------------------------------------------------------------------+
void UpdateChartPanel()
  {
   string text = "==========================================\n";
   text += "      HARUU SIGNAL RECEIVER (MT5)         \n";
   text += "      domain: signal.haruu-shop.com       \n";
   text += "==========================================\n";
   text += " Status Server : " + (m_connected ? "🟢 ONLINE (CONNECTED)" : "🔴 OFFLINE / RECONNECTING") + "\n";
   text += " Selected Mode : " + m_strategy_name + "\n";
   text += " Target Magic  : " + IntegerToString(m_target_magic) + "\n";
   text += " Active Signals: " + IntegerToString(m_total_signals) + "\n";
   text += "------------------------------------------\n";
   text += " Client Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   text += " Client Equity : $" + DoubleToString(AccountInfoDouble(ACCOUNT_PRICE_INDEX), 2) + "\n";
   text += "==========================================\n";

   Comment(text);
  }
