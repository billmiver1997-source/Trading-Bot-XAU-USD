//+------------------------------------------------------------------+
//|  XAUUSD M15 Mean-Reversion Scalper v9                            |
//|  Αγόρασε oversold, πούλα overbought — ADAPTIVE ADX trend filter |
//|  BUY:  K crosses D από <25 + bullish bar + RSI>15               |
//|  SELL: K crosses D από >75 + bearish bar + RSI<85               |
//|  SL: 1.1×ATR | TP: 1.6×ATR | Risk: 1% | Max 3 trades/day        |
//|  ADX threshold is relative to its own rolling average, not a    |
//|  fixed number — "strong trend" is judged against what's normal  |
//|  for this market recently, so it self-adjusts as conditions     |
//|  change instead of using one hardcoded cutoff forever.          |
//|  SL widened from 0.8x to give entries room past opening noise   |
//|  (fast <3min stopouts kept reversing back in our favor) —       |
//|  Lots() auto-shrinks size to hold risk% constant, so this only  |
//|  changes stop distance, not risk per trade or entry frequency.  |
//|  DIRECTIONAL BIAS: ADX only measures trend STRENGTH, not which  |
//|  way — this EA was still buying dips into real downtrends and   |
//|  selling rips into real uptrends (the exact pattern behind our  |
//|  worst losses). A slow EMA now gates direction: BUY only when   |
//|  price is above it, SELL only when below. Complements ADX       |
//|  (magnitude) with actual direction, without touching signal     |
//|  frequency in genuinely rangy conditions.                       |
//|  BREAKOUT-RETEST: second, independent entry path alongside the  |
//|  mean-reversion signal above. Tracks the N-bar high/low; when   |
//|  price closes through it, that level is remembered as "broken". |
//|  If price then pulls back close to it without closing back      |
//|  through, and the pullback bar closes back in the breakout      |
//|  direction, that's the retest — enter with the breakout, not    |
//|  against it. Still one position at a time (same risk gate as    |
//|  the rest of the EA) to keep exposure predictable.               |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "9.80"
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
input double InpSL      = 1.1;
input double InpTP      = 1.6;
input double InpRisk    = 1.0;
input double InpMaxDD   = 4.0;
input double InpTrailTrigger = 1.2;
input double InpTrailLock    = 0.53;

input group "=== FILTERS ==="
input double InpMaxSpread  = 60.0;
input int    InpMaxTrades  = 3;
input int    InpCooldownMin= 20;
input int    InpStartHour  = 9;
input int    InpEndHour    = 23;
input int    InpTZOffset   = 3;

input group "=== ADX (adaptive trend filter) ==="
input int    InpADXPeriod    = 14;
input int    InpADXAvgPeriod = 30;    // bars used to compute this market's own recent-normal ADX
input double InpADXRelMult   = 1.4;   // skip when ADX is this many times ABOVE its own recent average
input double InpADXAbsCap    = 50.0;  // hard safety ceiling regardless of the adaptive baseline

input group "=== NEWS FILTER ==="
input bool   InpNewsFilterOn      = true;
input int    InpNewsMinutesBefore = 30;   // no new entries this many minutes before high-impact news
input int    InpNewsMinutesAfter  = 30;   // ...and this many minutes after
input string InpNewsCurrency      = "USD";

input group "=== DIRECTIONAL BIAS (trade with the bigger trend) ==="
input int    InpEMAPeriod = 40;    // ~10h on M15 — fast enough to catch an intraday trend flip
                                    // (100 was too slow: kept reading stale direction into a real move)

input group "=== BREAKOUT-RETEST (2nd entry path) ==="
input bool   InpBreakoutOn       = true;
input int    InpBreakoutLookback = 20;   // bars used to define the level that gets broken
input double InpRetestTolerance  = 0.3;  // ×ATR — how close price must return to the level to count as a retest
input int    InpRetestMaxBars    = 20;   // give up on a break if no retest within this many bars
input double InpBreakoutSL       = 1.0;  // ×ATR stop beyond the retested level
input double InpBreakoutTP       = 2.0;  // ×ATR target — wider, this is trend-following not fading

int hStoch, hRSI, hATR, hADX, hEMA;
double sk[], sd[], rsi[], atr_v[], adx[], ema[], closeArr[], highArr[], lowArr[];
datetime lastTrade=0;
double   dayEq=0; int lastDay=-1;
int      dayTrades=0;
double   breakLevel=0; int breakDir=0; int barsSinceBreak=0;

int OnInit()
{
   trade.SetExpertMagicNumber(20250709);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   hStoch = iStochastic(_Symbol,PERIOD_M15,InpStochK,InpStochD,InpStochSl,MODE_SMA,STO_LOWHIGH);
   hRSI   = iRSI(_Symbol,PERIOD_M15,InpRSI,PRICE_CLOSE);
   hATR   = iATR(_Symbol,PERIOD_M15,InpATR);
   hADX   = iADX(_Symbol,PERIOD_M15,InpADXPeriod);
   hEMA   = iMA(_Symbol,PERIOD_M15,InpEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   if(hStoch==INVALID_HANDLE||hRSI==INVALID_HANDLE||hATR==INVALID_HANDLE||hADX==INVALID_HANDLE||hEMA==INVALID_HANDLE)
   { Print("Init failed"); return INIT_FAILED; }
   ArraySetAsSeries(sk,true); ArraySetAsSeries(sd,true);
   ArraySetAsSeries(rsi,true); ArraySetAsSeries(atr_v,true); ArraySetAsSeries(adx,true);
   ArraySetAsSeries(ema,true); ArraySetAsSeries(closeArr,true);
   ArraySetAsSeries(highArr,true); ArraySetAsSeries(lowArr,true);
   Print("XAUUSD v9 MeanReversion OK | Stoch25/75 | 3x/day | 20min cd | adaptive ADX x",DoubleToString(InpADXRelMult,1)," | EMA",InpEMAPeriod," bias | breakout-retest ",InpBreakoutOn?"ON":"OFF");
   return INIT_SUCCEEDED;
}
void OnDeinit(const int r){ IndicatorRelease(hStoch); IndicatorRelease(hRSI); IndicatorRelease(hATR); IndicatorRelease(hADX); IndicatorRelease(hEMA); }
bool Refresh()
{
   int adxBars = InpADXAvgPeriod + 2;
   int hlBars  = InpBreakoutLookback + 3;
   return CopyBuffer(hStoch,0,0,4,sk)    >=4
       && CopyBuffer(hStoch,1,0,4,sd)    >=4
       && CopyBuffer(hRSI,  0,0,4,rsi)   >=4
       && CopyBuffer(hATR,  0,0,4,atr_v) >=4
       && CopyBuffer(hADX,  0,0,adxBars,adx) >= adxBars
       && CopyBuffer(hEMA,  0,0,4,ema)   >=4
       && CopyClose(_Symbol,PERIOD_M15,0,4,closeArr) >=4
       && CopyHigh(_Symbol,PERIOD_M15,0,hlBars,highArr) >= hlBars
       && CopyLow(_Symbol,PERIOD_M15,0,hlBars,lowArr)   >= hlBars;
}
double RecentHigh(){ double h=highArr[2]; for(int i=3;i<2+InpBreakoutLookback;i++) if(highArr[i]>h) h=highArr[i]; return h; }
double RecentLow(){ double l=lowArr[2]; for(int i=3;i<2+InpBreakoutLookback;i++) if(lowArr[i]<l) l=lowArr[i]; return l; }
double AdxBaseline()
{
   double sum=0; int n=0;
   for(int i=1;i<=InpADXAvgPeriod && i<ArraySize(adx);i++){ sum+=adx[i]; n++; }
   return n>0 ? sum/n : adx[1];
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
   double adxAvg = AdxBaseline();
   bool trendTooStrong = adx[1] > adxAvg*InpADXRelMult || adx[1] > InpADXAbsCap;
   bool newsBlack = NewsBlackout();
   bool biasUp = closeArr[1] > ema[1];
   bool biasBlockBuy  = crossUp && !biasUp;   // dip-buy fighting a downtrend
   bool biasBlockSell = crossDn && biasUp;    // rip-sell fighting an uptrend

   Print("SCAN | K=",DoubleToString(sk[1],1)," D=",DoubleToString(sd[1],1),
         " RSI=",DoubleToString(rsi[1],1)," ADX=",DoubleToString(adx[1],1),
         " ADXavg=",DoubleToString(adxAvg,1)," Bias=",biasUp?"UP":"DN",
         " Cross=",crossUp?"BUY↑":crossDn?"SELL↓":"–",
         trendTooStrong && (crossUp||crossDn) ? " [TREND-SKIP]" : "",
         newsBlack && (crossUp||crossDn) ? " [NEWS-BLACKOUT]" : "",
         (biasBlockBuy||biasBlockSell) ? " [BIAS-SKIP]" : "",
         " Day=",dayTrades,"/",InpMaxTrades);

   double av=atr_v[1];

   if(newsBlack) return;

   if(!trendTooStrong)
   {
      if(crossUp && rsi[1]>InpRSImin && !HasBuy() && !HasSell() && !biasBlockBuy)
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
      else if(crossDn && rsi[1]<InpRSImax && !HasSell() && !HasBuy() && !biasBlockSell)
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

   // --- Breakout-retest: independent of the mean-reversion signal above,
   //     and intentionally NOT gated by trendTooStrong — a strong trend is
   //     exactly what this path is trying to trade WITH.
   if(InpBreakoutOn && !HasBuy() && !HasSell() && dayTrades<InpMaxTrades)
   {
      double rHigh=RecentHigh(), rLow=RecentLow();
      double c1=closeArr[1], c2=closeArr[2];

      if(breakDir==0 || barsSinceBreak>InpRetestMaxBars)
      {
         if(c1>rHigh && c2<=rHigh) { breakLevel=rHigh; breakDir=1; barsSinceBreak=0; Print("BREAK-UP level=",DoubleToString(breakLevel,_Digits)); }
         else if(c1<rLow && c2>=rLow) { breakLevel=rLow; breakDir=-1; barsSinceBreak=0; Print("BREAK-DN level=",DoubleToString(breakLevel,_Digits)); }
      }
      else barsSinceBreak++;

      if(breakDir==1 && MathAbs(c1-breakLevel)<=av*InpRetestTolerance && c1>breakLevel && c1>c2)
      {
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double sl=NormalizeDouble(breakLevel-av*InpBreakoutSL,_Digits);
         double tp=NormalizeDouble(ask+av*InpBreakoutTP,_Digits);
         double lots=Lots(ask-sl);
         if(trade.Buy(lots,_Symbol,ask,sl,tp,"XAU_BRK_BUY"))
         { lastTrade=TimeCurrent(); dayTrades++; breakDir=0;
           Print(">>> BREAKOUT BUY (retest of ",DoubleToString(breakLevel,_Digits),") | lots=",lots," sl=",sl," tp=",tp); }
         else
           Print("!!! BREAKOUT BUY FAILED | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      }
      else if(breakDir==-1 && MathAbs(c1-breakLevel)<=av*InpRetestTolerance && c1<breakLevel && c1<c2)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double sl=NormalizeDouble(breakLevel+av*InpBreakoutSL,_Digits);
         double tp=NormalizeDouble(bid-av*InpBreakoutTP,_Digits);
         double lots=Lots(sl-bid);
         if(trade.Sell(lots,_Symbol,bid,sl,tp,"XAU_BRK_SELL"))
         { lastTrade=TimeCurrent(); dayTrades++; breakDir=0;
           Print(">>> BREAKOUT SELL (retest of ",DoubleToString(breakLevel,_Digits),") | lots=",lots," sl=",sl," tp=",tp); }
         else
           Print("!!! BREAKOUT SELL FAILED | retcode=",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
      }
   }
}
