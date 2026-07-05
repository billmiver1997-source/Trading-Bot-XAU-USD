//+------------------------------------------------------------------+
//|  HistoryExportM15.mq5 — exports XAUUSD M15 bars to CSV          |
//|  Run once from Navigator → Scripts                               |
//+------------------------------------------------------------------+
#property script_show_inputs true
input int InpYears = 3;   // Years of history to export

void OnStart()
{
   datetime start = TimeCurrent() - (datetime)(InpYears * 365 * 86400);
   datetime end   = TimeCurrent();

   MqlRates rates[];
   int copied = CopyRates("XAUUSD", PERIOD_M15, start, end, rates);
   if(copied <= 0) { Print("CopyRates failed: ", GetLastError()); return; }

   string path = "XAUUSD_M15_history.csv";
   int fh = FileOpen(path, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE) { Print("Cannot open file"); return; }

   FileWrite(fh, "time","open","high","low","close","tick_volume","spread");
   for(int i = 0; i < copied; i++)
   {
      FileWrite(fh,
         TimeToString(rates[i].time, TIME_DATE|TIME_SECONDS),
         DoubleToString(rates[i].open,  2),
         DoubleToString(rates[i].high,  2),
         DoubleToString(rates[i].low,   2),
         DoubleToString(rates[i].close, 2),
         IntegerToString(rates[i].tick_volume),
         IntegerToString(rates[i].spread)
      );
   }
   FileClose(fh);
   Print("Exported ", copied, " bars → MQL5/Files/", path);
}
