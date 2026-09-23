//+------------------------------------------------------------------+
//|                              Zerith_ML_CandleData_Exporter_EA.mq5 |
//|              Zerith Series / Machine Learning Raw Data Collector |
//|                 https://github.com/BlamzKunG/My-Expert-Advisor   |
//+------------------------------------------------------------------+
#property copyright "Zerith Series / BlamzKunG Architecture"
#property link      "https://github.com/BlamzKunG/My-Expert-Advisor"
#property version   "1.10"
#property description "Zerith Machine Learning Raw Candlestick Data Collector EA"
#property description "High-Performance OHLCV + Spread Historical Exporter for ML/DL Pipelines"
#property description "Supports Live Chart Export & Full Automatic Strategy Tester Backtest Logging"
#property description "Auto-generates filenames with exact date ranges (e.g. XAUUSD_M5_20220101_to_20230101.csv)"
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
//| INTERNAL CANDLE RECORD STRUCTURE                                 |
//+------------------------------------------------------------------+
struct SCandleRecord
{
   datetime time;
   double   open;
   double   high;
   double   low;
   double   close;
   long     tick_volume;
   int      spread;
   long     real_volume;
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input group ">>>> 1. Symbol & Timeframe Selection"
input bool               InpCurrentChartOnly    = true;                 // Export Current Chart Symbol Only
input string             InpBatchSymbols        = "XAUUSD,EURUSD,GBPUSD,USDJPY,BTCUSD"; // Multi-Symbols (Comma Separated, Live only)
input bool               InpUseChartTimeframe   = true;                 // Use Current Chart Timeframe
input ENUM_TIMEFRAMES    InpCustomTimeframe     = PERIOD_M5;            // Custom Timeframe (if not chart TF)

input group ">>>> 2. Range & Export Configuration (Live Chart)"
input ENUM_EXPORT_MODE   InpExportMode          = EXPORT_BY_DATE_RANGE; // History Export Mode (for Live Chart)
input int                InpBarCount            = 50000;                // Number of Bars to Export (if Bar Count Mode)
input datetime           InpStartDate           = D'2022.01.01 00:00:00';// Start Date (if Date Range Mode)
input datetime           InpEndDate             = D'2023.01.01 00:00:00';// End Date (if Date Range Mode)

input group ">>>> 3. Strategy Tester (Backtest) Settings"
input bool               InpAutoDetectTester    = true;                 // Auto-Capture Strategy Tester Backtest Range
input bool               InpSaveToCommonFolder  = true;                 // Also Save to Common/Files (Easy to open!)

input group ">>>> 4. Output CSV Settings"
input string             InpSubfolder           = "ML_Dataset";         // Subfolder inside MQL5/Files/
input bool               InpIncludeHeader       = true;                 // Include Header Row in CSV
input bool               InpIncludeUnixTime     = true;                 // Include Unix Timestamp Column (Epoch)
input bool               InpSplitDateTime       = true;                 // Split Date and Time into Separate Columns
input string             InpDelimiter           = ",";                  // CSV Column Delimiter

input group ">>>> 5. Execution & UI Controls"
input bool               InpExportOnInit        = true;                 // Auto-Export Immediately on Load (Live Chart)
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

bool           g_isExporting = false;
int            g_totalExportedBars = 0;
string         g_lastExportStatus = "Ready";

// Strategy Tester backtest buffer
SCandleRecord  g_backtestBars[];
int            g_backtestBarCount = 0;
datetime       g_lastBarTime = 0;
bool           g_isTester = false;

//+------------------------------------------------------------------+
//| HELPER: FORMAT DATE TO YYYYMMDD FOR FILENAMES                    |
//+------------------------------------------------------------------+
string FormatDateForFileName(const datetime dt)
{
   MqlDateTime mdt;
   TimeToStruct(dt, mdt);
   return StringFormat("%04d%02d%02d", mdt.year, mdt.mon, mdt.day);
}

//+------------------------------------------------------------------+
//| EXPERT INITIALIZATION                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);

   Print("==================================================================");
   PrintFormat("[Zerith ML Collector] Initializing on %s (%s) | Tester Mode: %s",
               _Symbol, EnumToString(Period()), g_isTester ? "YES" : "NO");

   if(g_isTester && InpAutoDetectTester)
   {
      // Prepare buffer for capturing Strategy Tester backtest bars
      g_backtestBarCount = 0;
      ArrayResize(g_backtestBars, 10000);
      g_lastBarTime = 0;
      Print("[Zerith ML Collector] Strategy Tester Mode Active: Will record bars from backtest period and save at completion.");
   }
   else
   {
      if(InpShowOnChartUI && !g_isTester)
      {
         CreateOnChartUI();
      }

      if(InpExportOnInit && !g_isTester)
      {
         EventSetTimer(1);
      }
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| EXPERT DEINITIALIZATION                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   // If running in Strategy Tester, finalize and save the backtest dataset
   if(g_isTester && InpAutoDetectTester && g_backtestBarCount > 0)
   {
      SaveBacktestDataset();
   }

   if(!g_isTester)
   {
      RemoveOnChartUI();
   }
   Comment("");
}

//+------------------------------------------------------------------+
//| TIMER HANDLER (LIVE CHART AUTO-EXPORT)                           |
//+------------------------------------------------------------------+
void OnTimer()
{
   EventKillTimer();
   if(!g_isExporting && !g_isTester)
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
//| TICK HANDLER (CAPTURES BARS AS STRATEGY TESTER BACKTEST PLAYS)   |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_isTester || !InpAutoDetectTester) return;

   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   datetime currentBarTime = iTime(_Symbol, tf, 0);

   if(currentBarTime != g_lastBarTime)
   {
      if(g_lastBarTime != 0)
      {
         // Bar at index 1 has just closed and is complete
         MqlRates closedRate[1];
         if(CopyRates(_Symbol, tf, 1, 1, closedRate) > 0)
         {
            if(g_backtestBarCount >= ArraySize(g_backtestBars))
               ArrayResize(g_backtestBars, g_backtestBarCount + 10000);

            g_backtestBars[g_backtestBarCount].time        = closedRate[0].time;
            g_backtestBars[g_backtestBarCount].open        = closedRate[0].open;
            g_backtestBars[g_backtestBarCount].high        = closedRate[0].high;
            g_backtestBars[g_backtestBarCount].low         = closedRate[0].low;
            g_backtestBars[g_backtestBarCount].close       = closedRate[0].close;
            g_backtestBars[g_backtestBarCount].tick_volume = closedRate[0].tick_volume;
            g_backtestBars[g_backtestBarCount].spread      = closedRate[0].spread;
            g_backtestBars[g_backtestBarCount].real_volume = closedRate[0].real_volume;
            g_backtestBarCount++;
         }
      }
      g_lastBarTime = currentBarTime;
   }
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
//| SAVE BACKTEST DATASET AT END OF STRATEGY TESTER RUN              |
//+------------------------------------------------------------------+
void SaveBacktestDataset()
{
   // Append the last bar (index 0) which was open when the backtest ended
   ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
   MqlRates lastRate[1];
   if(CopyRates(_Symbol, tf, 0, 1, lastRate) > 0)
   {
      if(g_backtestBarCount >= ArraySize(g_backtestBars))
         ArrayResize(g_backtestBars, g_backtestBarCount + 1);

      g_backtestBars[g_backtestBarCount].time        = lastRate[0].time;
      g_backtestBars[g_backtestBarCount].open        = lastRate[0].open;
      g_backtestBars[g_backtestBarCount].high        = lastRate[0].high;
      g_backtestBars[g_backtestBarCount].low         = lastRate[0].low;
      g_backtestBars[g_backtestBarCount].close       = lastRate[0].close;
      g_backtestBars[g_backtestBarCount].tick_volume = lastRate[0].tick_volume;
      g_backtestBars[g_backtestBarCount].spread      = lastRate[0].spread;
      g_backtestBars[g_backtestBarCount].real_volume = lastRate[0].real_volume;
      g_backtestBarCount++;
   }

   datetime firstDate = g_backtestBars[0].time;
   datetime lastDate  = g_backtestBars[g_backtestBarCount - 1].time;

   string tfString = EnumToString(tf);
   StringReplace(tfString, "PERIOD_", "");

   string dateRangeStr = StringFormat("%s_to_%s", FormatDateForFileName(firstDate), FormatDateForFileName(lastDate));
   string fileBaseName = StringFormat("%s_%s_%s.csv", _Symbol, tfString, dateRangeStr);

   // Save file
   WriteRecordsToFile(fileBaseName, _Symbol, g_backtestBars, g_backtestBarCount);

   Print("==================================================================");
   PrintFormat("🎉 [Zerith ML Collector] Strategy Tester Backtest Export Finished!");
   PrintFormat("📊 Total Bars Saved: %d", g_backtestBarCount);
   PrintFormat("📅 Backtest Period:  %s  -->  %s", TimeToString(firstDate), TimeToString(lastDate));
   PrintFormat("📄 Filename:         %s", fileBaseName);
   PrintFormat("📂 Tester Directory: MQL5/Files/%s/%s", InpSubfolder, fileBaseName);
   if(InpSaveToCommonFolder)
   {
      PrintFormat("🌐 Common Directory: MetaQuotes/Terminal/Common/Files/%s/%s", InpSubfolder, fileBaseName);
   }
   Print("==================================================================");
}

//+------------------------------------------------------------------+
//| WRITE ARRAY OF CANDLE RECORDS TO CSV FILE                        |
//+------------------------------------------------------------------+
bool WriteRecordsToFile(const string fileBaseName,
                        const string symName,
                        const SCandleRecord &records[],
                        const int totalCount)
{
   if(totalCount <= 0) return false;

   CSymbolInfo sym;
   sym.Name(symName);
   int digits = sym.Digits();

   string folderPath = InpSubfolder;
   StringTrimLeft(folderPath);
   StringTrimRight(folderPath);

   // 1. Write to standard local terminal / tester folder
   if(folderPath != "") FolderCreate(folderPath);
   string localPath = (folderPath != "") ? StringFormat("%s/%s", folderPath, fileBaseName) : fileBaseName;

   int localHandle = FileOpen(localPath, FILE_WRITE | FILE_CSV | FILE_ANSI, InpDelimiter[0]);
   if(localHandle == INVALID_HANDLE)
   {
      PrintFormat("[-] Failed to create local file: %s (Error: %d)", localPath, GetLastError());
      return false;
   }

   // 2. Optional: Also write to Common directory
   int commonHandle = INVALID_HANDLE;
   if(InpSaveToCommonFolder)
   {
      if(folderPath != "") FolderCreate(folderPath, FILE_COMMON);
      commonHandle = FileOpen(localPath, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, InpDelimiter[0]);
   }

   // Prepare Header
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

      FileWriteString(localHandle, header + "\n");
      if(commonHandle != INVALID_HANDLE) FileWriteString(commonHandle, header + "\n");
   }

   // Write rows
   for(int i = 0; i < totalCount; i++)
   {
      string row = "";
      if(InpIncludeUnixTime) row += IntegerToString((long)records[i].time) + InpDelimiter;

      string dtStr = TimeToString(records[i].time, TIME_DATE | TIME_SECONDS);
      row += dtStr + InpDelimiter;

      if(InpSplitDateTime)
      {
         string dStr = TimeToString(records[i].time, TIME_DATE);
         string tStr = TimeToString(records[i].time, TIME_SECONDS);
         row += dStr + InpDelimiter + tStr + InpDelimiter;
      }

      row += symName + InpDelimiter;
      row += DoubleToString(records[i].open, digits) + InpDelimiter;
      row += DoubleToString(records[i].high, digits) + InpDelimiter;
      row += DoubleToString(records[i].low, digits) + InpDelimiter;
      row += DoubleToString(records[i].close, digits) + InpDelimiter;
      row += IntegerToString(records[i].tick_volume) + InpDelimiter;
      row += IntegerToString(records[i].spread) + InpDelimiter;
      row += IntegerToString(records[i].real_volume);

      FileWriteString(localHandle, row + "\n");
      if(commonHandle != INVALID_HANDLE) FileWriteString(commonHandle, row + "\n");
   }

   FileClose(localHandle);
   if(commonHandle != INVALID_HANDLE) FileClose(commonHandle);

   return true;
}

//+------------------------------------------------------------------+
//| CORE BATCH EXPORT (FOR LIVE CHART MODE)                          |
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

      if(ExportLiveCandleData(resolvedSymbol, rawSymbol, targetTF, tfString))
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
//| EXPORT INDIVIDUAL SYMBOL DATA IN LIVE CHART MODE                 |
//+------------------------------------------------------------------+
bool ExportLiveCandleData(const string brokerSymbol,
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
   ArraySetAsSeries(rates, false);

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

   // Format filename with actual date range
   datetime actualStart = rates[0].time;
   datetime actualEnd   = rates[copied - 1].time;
   string dateRangeStr  = StringFormat("%s_to_%s", FormatDateForFileName(actualStart), FormatDateForFileName(actualEnd));
   string fileBaseName  = StringFormat("%s_%s_%s.csv", baseSymbol, tfStr, dateRangeStr);

   SCandleRecord records[];
   ArrayResize(records, copied);
   for(int i = 0; i < copied; i++)
   {
      records[i].time        = rates[i].time;
      records[i].open        = rates[i].open;
      records[i].high        = rates[i].high;
      records[i].low         = rates[i].low;
      records[i].close       = rates[i].close;
      records[i].tick_volume = rates[i].tick_volume;
      records[i].spread      = rates[i].spread;
      records[i].real_volume = rates[i].real_volume;
   }

   bool ok = WriteRecordsToFile(fileBaseName, baseSymbol, records, copied);
   if(ok)
   {
      g_totalExportedBars += copied;
      PrintFormat("[+] Successfully exported %s (%s): %d bars saved -> %s",
                  brokerSymbol, tfStr, copied, fileBaseName);
   }
   return ok;
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
