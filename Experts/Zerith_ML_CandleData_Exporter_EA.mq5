//+------------------------------------------------------------------+
//|                              Zerith_ML_CandleData_Exporter_EA.mq5 |
//|              Zerith Series / Machine Learning Raw Data Collector |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / BlamzKunG Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.00"
#property description "Zerith Machine Learning Raw Candlestick Data Collector EA"
#property description "High-Performance Batch & On-Demand OHLCV + Spread Historical Exporter for ML/DL Pipelines"
#property description "Supports Current Chart or Multi-Symbol Batch Export, Date Range or Max Bars, and Unix Timestamp"
#property strict

#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| ENUMERATIONS                                                     |
//+------------------------------------------------------------------+
enum ENUM_EXPORT_MODE
{
   EXPORT_ALL_AVAILABLE   = 0, // All Available History in Terminal
   EXPORT_BY_BAR_COUNT    = 1, // Specific Number of Recent Bars
   EXPORT_BY_DATE_RANGE   = 2  // Specific Date Range (Start -> End)
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group ">>>> 1. Symbol & Timeframe Selection"
input bool               InpCurrentChartOnly    = true;                 // Export Current Chart Symbol Only
input string             InpBatchSymbols        = "XAUUSD,EURUSD,GBPUSD,USDJPY,BTCUSD"; // Multi-Symbols (Comma Separated)
input bool               InpUseChartTimeframe   = true;                 // Use Current Chart Timeframe
input ENUM_TIMEFRAMES    InpCustomTimeframe     = PERIOD_M5;            // Custom Timeframe (if not chart TF)

input group ">>>> 2. Range & Export Configuration"
input ENUM_EXPORT_MODE   InpExportMode          = EXPORT_ALL_AVAILABLE; // History Export Mode
input int                InpBarCount            = 50000;                // Number of Bars to Export (if Bar Count Mode)
input datetime           InpStartDate           = D'2022.01.01 00:00:00';// Start Date (if Date Range Mode)
input datetime           InpEndDate             = D'2026.12.31 23:59:59';// End Date (if Date Range Mode)

input group ">>>> 3. Output CSV Settings"
input string             InpSubfolder           = "ML_Dataset";         // Subfolder inside MQL5/Files/
input bool               InpIncludeHeader       = true;                 // Include Header Row in CSV
input bool               InpIncludeUnixTime     = true;                 // Include Unix Timestamp Column (Epoch)
input bool               InpSplitDateTime       = true;                 // Split Date and Time into Separate Columns
input string             InpDelimiter           = ",";                  // CSV Column Delimiter

input group ">>>> 4. Execution & UI Controls"
input bool               InpExportOnInit        = true;                 // Auto-Export Immediately on Load
input bool               InpShowOnChartUI       = true;                 // Display On-Chart Control & Status HUD
input bool               InpRemoveEAUponFinish  = false;                // Unload EA from Chart after Exporting

//+------------------------------------------------------------------+
//| GLOBAL STATE & DEFINES                                           |
//+------------------------------------------------------------------+
#define BTN_EXPORT_ID   "ZERITH_BTN_EXPORT"
#define HUD_BG_ID       "ZERITH_HUD_BG"
#define HUD_TITLE_ID    "ZERITH_HUD_TITLE"
#define HUD_STATUS_ID   "ZERITH_HUD_STATUS"
#define HUD_INFO_ID     "ZERITH_HUD_INFO"

bool   g_isExporting = false;
int    g_totalExportedBars = 0;
string g_lastExportStatus = "Ready";

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("==================================================================");
   PrintFormat("[Zerith ML Collector] Initializing on %s (%s)...", _Symbol, EnumToString(Period()));

   if(InpShowOnChartUI)
   {
      CreateOnChartUI();
   }

   if(InpExportOnInit)
   {
      // Run batch export on first launch
      EventSetTimer(1);
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   RemoveOnChartUI();
   Comment("");
}

//+------------------------------------------------------------------+
//| TIMER HANDLER (FOR TRIGGERING ONINIT EXPORT SAFELY)              |
//+------------------------------------------------------------------+
void OnTimer()
{
   EventKillTimer();
   if(!g_isExporting)
   {
      ExecuteBatchExport();
      if(InpRemoveEAUponFinish)
      {
         Print("[Zerith ML Collector] Auto-unloading EA as requested.");
         ExpertRemove();
      }
   }
}

//+------------------------------------------------------------------+
//| TICK HANDLER                                                     |
//+------------------------------------------------------------------+
void OnTick()
{
   // No high-frequency per-tick calculation needed for batch collector
}

//+------------------------------------------------------------------+
//| CHART EVENT HANDLER (BUTTON CLICK INTERACTION)                   |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == BTN_EXPORT_ID)
   {
      ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_STATE, false);
      if(!g_isExporting)
      {
         ExecuteBatchExport();
      }
      else
      {
         Print("[Zerith ML Collector] Export is currently in progress. Please wait.");
      }
   }
}

//+------------------------------------------------------------------+
//| CORE BATCH EXPORT ORCHESTRATOR                                   |
//+------------------------------------------------------------------+
void ExecuteBatchExport()
{
   g_isExporting = true;
   g_totalExportedBars = 0;
   UpdateHUDStatus("Exporting...", C'255,179,0');

   ENUM_TIMEFRAMES targetTF = InpUseChartTimeframe ? (ENUM_TIMEFRAMES)Period() : InpCustomTimeframe;
   string tfString = EnumToString(targetTF);
   StringReplace(tfString, "PERIOD_", "");

   string symbolsToProcess[];
   int count = 0;

   if(InpCurrentChartOnly)
   {
      ArrayResize(symbolsToProcess, 1);
      symbolsToProcess[0] = _Symbol;
      count = 1;
   }
   else
   {
      count = StringSplit(InpBatchSymbols, ',', symbolsToProcess);
   }

   int successCount = 0;

   for(int i = 0; i < count; i++)
   {
      string rawSymbol = symbolsToProcess[i];
      StringTrimLeft(rawSymbol);
      StringTrimRight(rawSymbol);
      if(rawSymbol == "") continue;

      string resolvedSymbol = ResolveBrokerSymbol(rawSymbol);
      if(resolvedSymbol == "")
      {
         PrintFormat("[-] Symbol not found in broker Market Watch: %s", rawSymbol);
         continue;
      }

      UpdateHUDStatus(StringFormat("Processing %s (%s)...", resolvedSymbol, tfString), C'0,176,255');
      ChartRedraw(0);

      if(ExportCandleData(resolvedSymbol, rawSymbol, targetTF, tfString))
      {
         successCount++;
      }
   }

   g_isExporting = false;
   string completionMsg = StringFormat("Done: %d/%d symbols (%d bars)", successCount, count, g_totalExportedBars);
   g_lastExportStatus = completionMsg;
   UpdateHUDStatus(completionMsg, C'0,230,118');

   Print("==================================================================");
   PrintFormat("🎉 [Zerith ML Collector] Export Complete! Successfully exported %d of %d symbols.", successCount, count);
   PrintFormat("📁 Output Folder: MT5 'MQL5/Files/%s/'", (InpSubfolder != "") ? InpSubfolder : "");
   Print("==================================================================");
}

//+------------------------------------------------------------------+
//| EXPORT INDIVIDUAL SYMBOL DATA TO CSV                             |
//+------------------------------------------------------------------+
bool ExportCandleData(const string brokerSymbol,
                      const string baseSymbol,
                      const ENUM_TIMEFRAMES tf,
                      const string tfStr)
{
   CSymbolInfo sym;
   if(!sym.Name(brokerSymbol))
   {
      PrintFormat("[-] Error accessing symbol info for %s", brokerSymbol);
      return false;
   }
   sym.Refresh();
   sym.Select(true);

   MqlRates rates[];
   ArraySetAsSeries(rates, false); // Chronological order (Oldest -> Newest)

   int copied = 0;
   ResetLastError();

   if(InpExportMode == EXPORT_ALL_AVAILABLE)
   {
      datetime oldestServerDate = 0;
      SeriesInfoInteger(brokerSymbol, tf, SERIES_SERVER_FIRSTDATE, oldestServerDate);
      if(oldestServerDate <= 0) oldestServerDate = D'1970.01.01 00:00:00';

      copied = CopyRates(brokerSymbol, tf, oldestServerDate, TimeCurrent(), rates);
   }
   else if(InpExportMode == EXPORT_BY_BAR_COUNT)
   {
      copied = CopyRates(brokerSymbol, tf, 0, InpBarCount, rates);
   }
   else // EXPORT_BY_DATE_RANGE
   {
      copied = CopyRates(brokerSymbol, tf, InpStartDate, InpEndDate, rates);
   }

   if(copied <= 0)
   {
      PrintFormat("[-] Failed to copy rates for %s (%s). Error Code: %d", brokerSymbol, tfStr, GetLastError());
      return false;
   }

   // Prepare output directory
   string folderPath = InpSubfolder;
   StringTrimLeft(folderPath);
   StringTrimRight(folderPath);
   if(folderPath != "")
   {
      FolderCreate(folderPath);
   }

   // Format filename: e.g. "ML_Dataset/XAUUSD_H1_raw.csv"
   string fileName = "";
   if(folderPath != "")
      fileName = StringFormat("%s/%s_%s_raw.csv", folderPath, baseSymbol, tfStr);
   else
      fileName = StringFormat("%s_%s_raw.csv", baseSymbol, tfStr);

   int fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI, InpDelimiter[0]);
   if(fileHandle == INVALID_HANDLE)
   {
      PrintFormat("[-] Failed to create output file: %s (Error: %d)", fileName, GetLastError());
      return false;
   }

   // Write CSV Header
   if(InpIncludeHeader)
   {
      string header = "";
      if(InpIncludeUnixTime) header += "timestamp" + InpDelimiter;
      header += "datetime" + InpDelimiter;
      if(InpSplitDateTime) header += "date" + InpDelimiter + "time" + InpDelimiter;
      header += "symbol" + InpDelimiter;
      header += "open" + InpDelimiter;
      header += "high" + InpDelimiter;
      header += "low" + InpDelimiter;
      header += "close" + InpDelimiter;
      header += "tick_volume" + InpDelimiter;
      header += "spread" + InpDelimiter;
      header += "real_volume";

      FileWriteString(fileHandle, header + "\n");
   }

   int digits = sym.Digits();

   // Write Raw Candlestick Data Rows
   for(int i = 0; i < copied; i++)
   {
      string row = "";

      if(InpIncludeUnixTime)
      {
         row += IntegerToString((long)rates[i].time) + InpDelimiter;
      }

      string dtStr = TimeToString(rates[i].time, TIME_DATE | TIME_SECONDS);
      row += dtStr + InpDelimiter;

      if(InpSplitDateTime)
      {
         string dStr = TimeToString(rates[i].time, TIME_DATE);
         string tStr = TimeToString(rates[i].time, TIME_SECONDS);
         row += dStr + InpDelimiter + tStr + InpDelimiter;
      }

      row += baseSymbol + InpDelimiter;
      row += DoubleToString(rates[i].open, digits) + InpDelimiter;
      row += DoubleToString(rates[i].high, digits) + InpDelimiter;
      row += DoubleToString(rates[i].low, digits) + InpDelimiter;
      row += DoubleToString(rates[i].close, digits) + InpDelimiter;
      row += IntegerToString(rates[i].tick_volume) + InpDelimiter;
      row += IntegerToString(rates[i].spread) + InpDelimiter;
      row += IntegerToString(rates[i].real_volume);

      FileWriteString(fileHandle, row + "\n");
   }

   FileClose(fileHandle);
   g_totalExportedBars += copied;

   PrintFormat("[+] Successfully exported %s (%s): %d bars saved -> %s",
               brokerSymbol, tfStr, copied, fileName);
   return true;
}

//+------------------------------------------------------------------+
//| BROKER SYMBOL RESOLVER                                           |
//+------------------------------------------------------------------+
string ResolveBrokerSymbol(const string baseName)
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
//| ON-CHART UI INTERFACE                                            |
//+------------------------------------------------------------------+
void CreateOnChartUI()
{
   int x = 20, y = 30, w = 320, h = 180;
   color bg = C'13,17,23';        // Dark Obsidian
   color border = C'33,38,45';    // Slate Border
   color accent = C'0,230,118';   // Emerald Cyan

   // HUD Background
   ObjectCreate(0, HUD_BG_ID, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, HUD_BG_ID, OBJPROP_SELECTABLE, false);

   // Title Label
   ObjectCreate(0, HUD_TITLE_ID, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, HUD_TITLE_ID, OBJPROP_TEXT, "ZERITH ML DATA COLLECTOR");
   ObjectSetInteger(0, HUD_TITLE_ID, OBJPROP_XDISTANCE, x + 14);
   ObjectSetInteger(0, HUD_TITLE_ID, OBJPROP_YDISTANCE, y + 10);
   ObjectSetInteger(0, HUD_TITLE_ID, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, HUD_TITLE_ID, OBJPROP_COLOR, clrWhite);
   ObjectSetString(0, HUD_TITLE_ID, OBJPROP_FONT, "Segoe UI Bold");

   // Info Subtitle
   ObjectCreate(0, HUD_INFO_ID, OBJ_LABEL, 0, 0, 0);
   string info = StringFormat("Target: %s (%s) | Dest: %s/", _Symbol, EnumToString(Period()), InpSubfolder);
   ObjectSetString(0, HUD_INFO_ID, OBJPROP_TEXT, info);
   ObjectSetInteger(0, HUD_INFO_ID, OBJPROP_XDISTANCE, x + 14);
   ObjectSetInteger(0, HUD_INFO_ID, OBJPROP_YDISTANCE, y + 28);
   ObjectSetInteger(0, HUD_INFO_ID, OBJPROP_FONTSIZE, 7);
   ObjectSetInteger(0, HUD_INFO_ID, OBJPROP_COLOR, C'139,148,158');
   ObjectSetString(0, HUD_INFO_ID, OBJPROP_FONT, "Segoe UI");

   // Status Indicator
   ObjectCreate(0, HUD_STATUS_ID, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, HUD_STATUS_ID, OBJPROP_TEXT, "Status: Ready to Export");
   ObjectSetInteger(0, HUD_STATUS_ID, OBJPROP_XDISTANCE, x + 14);
   ObjectSetInteger(0, HUD_STATUS_ID, OBJPROP_YDISTANCE, y + 60);
   ObjectSetInteger(0, HUD_STATUS_ID, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, HUD_STATUS_ID, OBJPROP_COLOR, accent);
   ObjectSetString(0, HUD_STATUS_ID, OBJPROP_FONT, "Segoe UI Semibold");

   // Interactive Button [EXPORT NOW]
   ObjectCreate(0, BTN_EXPORT_ID, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_XDISTANCE, x + 14);
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_YDISTANCE, y + 100);
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_XSIZE, w - 28);
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_YSIZE, 42);
   ObjectSetString(0, BTN_EXPORT_ID, OBJPROP_TEXT, "📥 EXPORT ML CANDLE DATA NOW");
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, BTN_EXPORT_ID, OBJPROP_FONT, "Segoe UI Bold");
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_COLOR, C'13,17,23');
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_BGCOLOR, accent);
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_BORDER_COLOR, border);
   ObjectSetInteger(0, BTN_EXPORT_ID, OBJPROP_SELECTABLE, false);

   ChartRedraw(0);
}

void UpdateHUDStatus(const string text, const color clr)
{
   if(ObjectFind(0, HUD_STATUS_ID) >= 0)
   {
      ObjectSetString(0, HUD_STATUS_ID, OBJPROP_TEXT, "Status: " + text);
      ObjectSetInteger(0, HUD_STATUS_ID, OBJPROP_COLOR, clr);
      ChartRedraw(0);
   }
}

void RemoveOnChartUI()
{
   ObjectDelete(0, BTN_EXPORT_ID);
   ObjectDelete(0, HUD_BG_ID);
   ObjectDelete(0, HUD_TITLE_ID);
   ObjectDelete(0, HUD_STATUS_ID);
   ObjectDelete(0, HUD_INFO_ID);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
