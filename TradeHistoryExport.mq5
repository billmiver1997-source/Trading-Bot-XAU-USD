//+------------------------------------------------------------------+
//|  TradeHistoryExport.mq5                                          |
//|  Script: exports all closed deals to MQL5/Files/trade_history.csv|
//|  Run once from MT5 Navigator → Scripts (drag to any chart)       |
//+------------------------------------------------------------------+
#property script_show_inputs false

void OnStart()
{
   if(!HistorySelect(0, TimeCurrent()))
   { Print("HistorySelect failed"); return; }

   int total = HistoryDealsTotal();
   if(total == 0)
   { Print("No deals found"); return; }

   string path = "trade_history.csv";
   int fh = FileOpen(path, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(fh == INVALID_HANDLE)
   { Print("Cannot open file: ", path); return; }

   FileWrite(fh, "Ticket","Time","Symbol","Type","Volume","Price","Commission","Swap","Profit","Comment","Magic");

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long   magic  = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      string sym    = HistoryDealGetString(ticket, DEAL_SYMBOL);
      int    type   = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      int    entry  = (int)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      datetime t    = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double vol    = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double price  = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double comm   = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap   = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      string comment= HistoryDealGetString(ticket, DEAL_COMMENT);

      string typeStr = (type==DEAL_TYPE_BUY ? "BUY" : type==DEAL_TYPE_SELL ? "SELL" : "OTHER");
      string entryStr= (entry==DEAL_ENTRY_IN ? "IN" : entry==DEAL_ENTRY_OUT ? "OUT" : "INOUT");

      FileWrite(fh,
         IntegerToString((long)ticket),
         TimeToString(t, TIME_DATE|TIME_SECONDS),
         sym, typeStr+"/"+entryStr,
         DoubleToString(vol,2),
         DoubleToString(price,5),
         DoubleToString(comm,2),
         DoubleToString(swap,2),
         DoubleToString(profit,2),
         comment,
         IntegerToString(magic)
      );
   }

   FileClose(fh);
   Print("Exported ", total, " deals → MQL5/Files/trade_history.csv");
}
