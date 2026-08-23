//+------------------------------------------------------------------+
//|                                           ExportMultiData_M5.mq5 |
//|                                  Copyright 2026, AI Trading Team |
//|                       Multi-Currency M5 Historical Data Exporter |
//+------------------------------------------------------------------+
#property copyright "AI Trading Project"
#property link      "https://localhost"
#property version   "1.00"
#property script_show_inputs

//--- Input Parameters
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;              // Timeframe to Export
input datetime        InpStartDate = D'2020.01.01 00:00:00'; // Start Date
input datetime        InpEndDate   = D'2025.12.31 23:59:59'; // End Date
input string          InpSymbols   = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,USDCAD,NZDUSD,EURJPY,GBPJPY,EURGBP,AUDJPY,XAUUSD"; // Symbols (comma separated)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("======================================================");
   Print("🚀 Starting Multi-Currency Data Export...");
   PrintFormat("Period: %s to %s", TimeToString(InpStartDate), TimeToString(InpEndDate));
   
   string symbolArray[];
   int symbolCount = StringSplit(InpSymbols, ',', symbolArray);
   
   if(symbolCount <= 0)
   {
      Print("[-] Error: No symbols specified!");
      return;
   }
   
   string tfStr = EnumToString(InpTimeframe);
   StringReplace(tfStr, "PERIOD_", "");
   
   int successCount = 0;
   
   for(int i = 0; i < symbolCount; i++)
   {
      string rawSymbol = symbolArray[i];
      StringTrimLeft(rawSymbol);
      StringTrimRight(rawSymbol);
      
      // Auto-resolve broker symbol name (e.g., EURUSD.m, EURUSDpro)
      string brokerSymbol = ResolveBrokerSymbol(rawSymbol);
      
      if(brokerSymbol == "")
      {
         PrintFormat("[-] Symbol not found in Market Watch: %s", rawSymbol);
         continue;
      }
      
      PrintFormat("[+] Exporting %s (%s)...", brokerSymbol, tfStr);
      
      if(ExportSymbolData(brokerSymbol, rawSymbol, InpTimeframe, InpStartDate, InpEndDate, tfStr))
      {
         successCount++;
      }
   }
   
   Print("======================================================");
   PrintFormat("🎉 Export completed: %d / %d symbols exported successfully!", successCount, symbolCount);
   Print("📁 Files are located in MT5 'MQL5/Files/' directory.");
}

//+------------------------------------------------------------------+
//| Find broker specific symbol name                                |
//+------------------------------------------------------------------+
string ResolveBrokerSymbol(string baseName)
{
   if(SymbolInfoInteger(baseName, SYMBOL_SELECT))
      return baseName;
      
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
   {
      string name = SymbolName(i, false);
      if(StringFind(name, baseName) >= 0)
      {
         SymbolSelect(name, true);
         return name;
      }
   }
   return "";
}

//+------------------------------------------------------------------+
//| Export individual symbol data to CSV                            |
//+------------------------------------------------------------------+
bool ExportSymbolData(string brokerSymbol, string baseSymbol, ENUM_TIMEFRAMES tf, datetime start, datetime end, string tfStr)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   
   int copied = CopyRates(brokerSymbol, tf, start, end, rates);
   if(copied <= 0)
   {
      PrintFormat("[-] Failed to copy rates for %s, error: %d", brokerSymbol, GetLastError());
      return false;
   }
   
   string fileName = StringFormat("%s_%s_2020_2025.csv", baseSymbol, tfStr);
   int fileHandle = FileOpen(fileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   
   if(fileHandle == INVALID_HANDLE)
   {
      PrintFormat("[-] Failed to create file %s", fileName);
      return false;
   }
   
   // Write Header
   FileWrite(fileHandle, "datetime", "symbol", "open", "high", "low", "close", "tick_volume", "spread", "real_volume");
   
   // Write Rows
   for(int i = 0; i < copied; i++)
   {
      string timeStr = TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS);
      FileWrite(fileHandle,
         timeStr,
         baseSymbol,
         DoubleToString(rates[i].open, _Digits),
         DoubleToString(rates[i].high, _Digits),
         DoubleToString(rates[i].low, _Digits),
         DoubleToString(rates[i].close, _Digits),
         IntegerToString(rates[i].tick_volume),
         IntegerToString(rates[i].spread),
         IntegerToString(rates[i].real_volume)
      );
   }
   
   FileClose(fileHandle);
   PrintFormat("    ✓ Saved %d bars to %s", copied, fileName);
   return true;
}
