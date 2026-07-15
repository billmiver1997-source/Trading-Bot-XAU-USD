//+------------------------------------------------------------------+
//|  XAUUSD M15 Mean-Reversion Scalper v9                            |
//|  Αγόρασε oversold, πούλα overbought — ελαφρύ ADX trend filter   |
//|  BUY:  K crosses D από <25 + bullish bar + RSI>15               |
//|  SELL: K crosses D από >75 + bearish bar + RSI<85               |
//|  SL: 0.8×ATR | TP: 1.2×ATR | Risk: 1% | Max 3 trades/day        |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "9.40"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo pos;

input group "=== STOCHASTIC ==="
input int    InpStochK  = 14;
input int    InpStochD  = 3;
input int    InpStochSl = 3;
input double InpOversold  = 40.0;
input double InpOverbought= 60.0;

input group "=== RSI (anti-crash filter) ==="
input int    InpRSI     = 14;
input double InpRSImin  = 15.0;
input double InpRSImax  = 85.0;

input group "=== RISK ==="
input int    InpATR     = 14;
input double InpSL      = 0.8;
input double InpTP      = 1.2;
input double InpRisk    = 1.0;
input double InpMaxDD   = 4.0;
input double InpTrailTrigger = 0.9;
input double InpTrailLock    = 0.4;

input group "=== FILTERS ==="
input double InpMaxSpread  = 60.0;
input int    InpMaxTrades  = 3;
input int    InpCooldownMin= 20;
input int    InpStartHour  = 9;
input int    InpEndHour    = 23;
input int    InpTZOffset   = 3;

input group "=== ADX (light trend filter) ==="
input int    InpADXPeriod  = 14;
input double InpADXMax     = 35.0;   // skip counter-trend entries when trend this strong

input group "=== NEWS FILTER ==="
input bool   InpNewsFilterOn      = true;
input int    InpNewsMinutesBefore = 30;   // no new entries this many minutes before high-impact news
input int    InpNewsMinutesAfter  = 30;   // ...and this many minutes after
input string InpNewsCurrency      = "USD";

int hStoch, hRSI, hATR, hADX;
double sk[], sd[], rsi[], atr_v[], adx[];
datetime lastTrade=0;
double   dayEq=0; int lastDay=-1;
int      dayTrades=0;

int OnInit()
{
   trade.SetExpertMagicNumber(20250709);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   hStoch = iStochastic(_Symbol,PERIOD_M15,InpStochK,InpStochD,InpStochSl,MODE_SMA,STO_LOWHIGH);
   hRSI   = iRSI(_Symbol,PERIOD_M15,InpRSI,PRICE_CLOSE);
   hATR   = iATR(_Symbol,PERIOD_M15,InpATR);
   hADX   = iADX(_Symbol,PERIOD_M15,InpADXPeriod);
   if(hStoch==INVALID_HANDLE||hRSI==INVALID_HANDLE||hATR==INVALID_HANDLE||hADX==INVALID_HANDLE)
   { Print("Init failed"); return INIT_FAILED; }
   ArraySetAsSeries(sk,true); ArraySetAsSeries(sd,true);
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(atr_v,true); ArraySetAsSeries(adx,true);
   Print("XAUUSD v9 MeanReversion OK | Stoch25/75 | 3x/day | 20min cd | ADX<",DoubleToString(InpADXMax,0));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){ IndicatorRelease(hStoch); IndicatorRelease(hRSI); IndicatorRelease(hATR); IndicatorRelease(hADX); }
bool Refresh()
{
   return CopyBuffer(hStoch,0,0,4,sk)    >=4
       && CopyBuffer(hStoch,1,0,4,sd)    >=4
       && CopyBuffer(hRSI,  0,0,4,rsi)   >=4
       && CopyBuffer(hATR,  0,0,4,atr_v) >=4
       && CopyBuffer(hADX,  0,0,4,adx)   >=4;
}
bool InSession()
{
   MqlDateTime dt;
   datetime eet=TimeGMT()+(datetime)(InpTZOffset*3600);
   TimeToStruct(eet,dt);
   if(dt.day_of_week==0||dt.day_of_week==6) return false;
   if(dt.day_of_week==5 && dt.hour>=22) return false;
   return dt.hour>=InpStartHour && dt.hour<InpEndHour;
}
bool NewsBlackout()
{
   if(!InpNewsFilterOn) return false;
   datetime from = TimeCurrent() - InpNewsMinutesAfter*60;
   datetime to   = TimeCurrent() + InpNewsMinutesBefore*60;
   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, from, to, NULL, InpNewsCurrency);
   for(int i=0;i<n;i++)
   {
      MqlCalendarEvent ev;
      if(CalendarEventById(values[i].event_id, ev) && ev.importance==CALENDAR_IMPORTANCE_HIGH)
         return true;
   }
   return false;
}
int CountMine(){ int c=0; for(int i=0;i<PositionsTotal();i++) if(pos.SelectByIndex(i)&&pos.Magic()==20250709&&pos.Symbol()==_Symbol) c++; return c; }
bool HasBuy(){ for(int i=0;i<PositionsTotal();i++) if(pos.SelectByIndex(i)&&pos.Magic()==20250709&&pos.Symbol()==_Symbol&&pos.PositionType()==POSITION_TYPE_BUY) return true; return false; }
bool HasSell(){ for(int i=0;i<PositionsTotal();i++) if(pos.SelectByIndex(i)&&pos.Magic()==20250709&&pos.Symbol()==_Symbol&&pos.PositionType()==POSITION_TYPE_SELL) return true; return false; }
double Lots(double slD)
{
   if(slD<=0) return SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double risk=AccountInfoDouble(ACCOUNT_EQUITY)*(InpRisk/100.0);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double ls=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(ts<=0||tv<=0) return mn;
   double vpl=(slD/ts)*tv; if(vpl<=0) return mn;
   return NormalizeDouble(MathMax(mn,MathMin(mx,MathFloor((risk/vpl)/ls)*ls)),2);
}
void TrailStop()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)||pos.Magic()!=20250709||pos.Symbol()!=_Symbol) continue;
      double op=pos.PriceOpen(),sl=pos.StopLoss(),tp=pos.TakeProfit(),av=atr_v[0];
      if(pos.PositionType()==POSITION_TYPE_BUY)
      { double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
        double lockPrice=NormalizeDouble(op+av*InpTrailLock,_Digits);
        if(bid>=op+av*InpTrailTrigger && sl<lockPrice) trade.PositionModify(pos.Ticket(),lockPrice,tp); }
      else
      { double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
        double lockPrice=NormalizeDouble(op-av*InpTrailLock,_Digits);
        if(ask<=op-av*InpTrailTrigger && sl>lockPrice) trade.PositionModify(pos.Ticket(),lockPrice,tp); }
   }
}
void OnTick()
{
   static datetime lastBar=0;
   datetime cur=iTime(_Symbol,PERIOD_M15,0);
   if(cur==lastBar) return; lastBar=cur;
   if(!Refresh()) return;

   MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
   if(dt.day!=lastDay){ dayEq=AccountInfoDouble(ACCOUNT_EQUITY); lastDay=dt.day; dayTrades=0; }

   TrailStop();

   if(!InSession()) return;

   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread>InpMaxSpread*_Point) return;

   if(InpMaxDD>0 && dayEq>0 && AccountInfoDouble(ACCOUNT_EQUITY)<dayEq*(1-InpMaxDD/100))
   { Print("STOP: daily DD limit"); return; }

   if(dayTrades>=InpMaxTrades) return;
   if(lastTrade>0 && (TimeCurrent()-lastTrade)<(datetime)(InpCooldownMin*60)) return;

   bool crossUp = sk[1]>sd[1] && sk[2]<=sd[2] && sk[1]<InpOversold;
   bool crossDn = sk[1]<sd[1] && sk[2]>=sd[2] && sk[1]>InpOverbought;
   bool trendTooStrong = adx[1] > InpADXMax;
   bool newsBlack = NewsBlackout();

   Print("SCAN | K=",DoubleToString(sk[1],1)," D=",DoubleToString(sd[1],1),
         " RSI=",DoubleToString(rsi[1],1)," ADX=",DoubleToString(adx[1],1),
         " Cross=",crossUp?"BUY↑":crossDn?"SELL↓":"–",
         trendTooStrong && (crossUp||crossDn) ? " [TREND-SKIP]" : "",
         newsBlack && (crossUp||crossDn) ? " [NEWS-BLACKOUT]" : "",
         " Day=",dayTrades,"/",InpMaxTrades);

   double av=atr_v[1];

   if(trendTooStrong || newsBlack) return;

   if(crossUp && rsi[1]>InpRSImin && !HasBuy())
   {
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double sl=NormalizeDouble(ask-av*InpSL,_Digits);
      double tp=NormalizeDouble(ask+av*InpTP,_Digits);
      double lots=Lots(ask-sl);
      if(trade.Buy(lots,_Symbol,ask,sl,tp,"XAU_BUY"))
      { lastTrade=TimeCurrent(); dayTrades++;
        Print(">>> BUY | lots=",lots," sl=",sl," tp=",tp," K=",DoubleToString(sk[1],1)); }
      else
        Print("!!! BUY FAILED | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription(),
              " | lots=",lots," ask=",ask," sl=",sl," tp=",tp," stops_level=",(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL));
   }
   else if(crossDn && rsi[1]<InpRSImax && !HasSell())
   {
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double sl=NormalizeDouble(bid+av*InpSL,_Digits);
      double tp=NormalizeDouble(bid-av*InpTP,_Digits);
      double lots=Lots(sl-bid);
      if(trade.Sell(lots,_Symbol,bid,sl,tp,"XAU_SELL"))
      { lastTrade=TimeCurrent(); dayTrades++;
        Print(">>> SELL | lots=",lots," sl=",sl," tp=",tp," K=",DoubleToString(sk[1],1)); }
      else
        Print("!!! SELL FAILED | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription(),
              " | lots=",lots," bid=",bid," sl=",sl," tp=",tp," stops_level=",(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL));
   }
}
