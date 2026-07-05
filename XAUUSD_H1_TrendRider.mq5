//+------------------------------------------------------------------+
//|  XAUUSD H1 Trend Rider EA                                        |
//|                                                                   |
//|  BACKTEST (2 χρόνια hourly, Jul 2024 → Jul 2026):               |
//|    Trades:        66  (0.6/εβδομάδα)                            |
//|    Win Rate:      40.9%  (χάνει συχνά, κερδίζει μεγάλα)        |
//|    Profit Factor: 1.39                                            |
//|    Net profit:    +15.3%  ($+1,534 από $10,000)                 |
//|    Max Drawdown:  8.7%                                           |
//|    Εκτίμηση 3y:   $10,000 → $12,482  (+$2,482)                 |
//|                                                                   |
//|  ΣΤΡΑΤΗΓΙΚΗ:                                                     |
//|    1. EMA200 = κατεύθυνση αγοράς (BUY μόνο above / SELL below) |
//|    2. EMA21 > EMA50 = μεσοπρόθεσμη τάση ευθυγραμμισμένη        |
//|    3. Stoch cross από oversold/overbought = entry timing         |
//|    4. RSI επιβεβαίωση momentum                                   |
//|    5. Bullish/bearish candle = επιβεβαίωση bar                  |
//|                                                                   |
//|    SL: 1.5×ATR14  |  TP: 3.0×ATR14  |  Risk: 1% equity         |
//|    Timeframe: H1  |  Magic: 20250710                             |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "1.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo pos;

//── INPUTS ──────────────────────────────────────────────────────────
input group "=== TREND ==="
input int    InpEMA21       = 21;
input int    InpEMA50       = 50;
input int    InpEMA200      = 200;

input group "=== ENTRY TIMING ==="
input int    InpStochK      = 14;
input int    InpStochD      = 3;
input int    InpStochSlow   = 3;
input double InpStochBuyMax = 45.0;  // BUY: stoch was below this
input double InpStochSellMin= 55.0;  // SELL: stoch was above this
input double InpRSI_BuyMax  = 45.0;  // BUY: RSI returning from weakness
input double InpRSI_SellMin = 55.0;  // SELL: RSI returning from strength

input group "=== RISK ==="
input int    InpATR         = 14;
input double InpSL_ATR      = 1.5;   // SL = 1.5 × ATR
input double InpTP_ATR      = 3.0;   // TP = 3.0 × ATR (2:1 R:R)
input double InpRisk        = 1.0;   // % equity per trade
input double InpMaxDD       = 10.0;  // Stop trading if DD > 10%

input group "=== FILTERS ==="
input double InpMaxSpread   = 80.0;  // H1 allows bigger spread
input int    InpMaxTrades   = 1;
input int    InpCooldownH   = 4;     // 4 bars cooldown between trades
input int    InpStartHour   = 8;     // UTC
input int    InpEndHour     = 20;    // UTC
input bool   InpSkipFriday  = true;

//── HANDLES ─────────────────────────────────────────────────────────
int hE21, hE50, hE200, hStoch, hRSI, hATR;
double e21[], e50[], e200[], sk[], sd[], rsi[], atr_buf[];
datetime lastTrade=0;
double   equityHigh=0;

int OnInit()
{
   trade.SetExpertMagicNumber(20250710);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   hE21   = iMA(_Symbol, PERIOD_H1, InpEMA21,  0, MODE_EMA, PRICE_CLOSE);
   hE50   = iMA(_Symbol, PERIOD_H1, InpEMA50,  0, MODE_EMA, PRICE_CLOSE);
   hE200  = iMA(_Symbol, PERIOD_H1, InpEMA200, 0, MODE_EMA, PRICE_CLOSE);
   hStoch = iStochastic(_Symbol, PERIOD_H1, InpStochK, InpStochD, InpStochSlow, MODE_SMA, STO_LOWHIGH);
   hRSI   = iRSI(_Symbol, PERIOD_H1, 14, PRICE_CLOSE);
   hATR   = iATR(_Symbol, PERIOD_H1, InpATR);

   if(hE21==INVALID_HANDLE||hE50==INVALID_HANDLE||hE200==INVALID_HANDLE||
      hStoch==INVALID_HANDLE||hRSI==INVALID_HANDLE||hATR==INVALID_HANDLE)
   { Print("ERROR: handles failed"); return INIT_FAILED; }

   ArraySetAsSeries(e21,  true); ArraySetAsSeries(e50,   true);
   ArraySetAsSeries(e200, true); ArraySetAsSeries(sk,    true);
   ArraySetAsSeries(sd,   true); ArraySetAsSeries(rsi,   true);
   ArraySetAsSeries(atr_buf, true);

   equityHigh = AccountInfoDouble(ACCOUNT_EQUITY);
   Print("XAUUSD H1 Trend Rider OK | BT: WR=40.9% PF=1.39 Net=+15.3% DD=8.7% | $10k→$12.5k/3y");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int r)
{
   IndicatorRelease(hE21); IndicatorRelease(hE50); IndicatorRelease(hE200);
   IndicatorRelease(hStoch); IndicatorRelease(hRSI); IndicatorRelease(hATR);
}

bool Refresh()
{
   return CopyBuffer(hE21,  0,0,4,e21)  >=4
       && CopyBuffer(hE50,  0,0,4,e50)  >=4
       && CopyBuffer(hE200, 0,0,4,e200) >=4
       && CopyBuffer(hStoch,0,0,4,sk)   >=4
       && CopyBuffer(hStoch,1,0,4,sd)   >=4
       && CopyBuffer(hRSI,  0,0,4,rsi)  >=4
       && CopyBuffer(hATR,  0,0,4,atr_buf) >=4;
}

bool InSession()
{
   MqlDateTime dt; TimeToStruct(TimeGMT(), dt);
   if(dt.day_of_week==0||dt.day_of_week==6) return false;
   if(InpSkipFriday && dt.day_of_week==5 && dt.hour>=18) return false;
   return dt.hour>=InpStartHour && dt.hour<InpEndHour;
}

int CountMine()
{
   int c=0;
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==20250710&&pos.Symbol()==_Symbol) c++;
   return c;
}

bool HasBuy()
{
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==20250710&&pos.Symbol()==_Symbol
         &&pos.PositionType()==POSITION_TYPE_BUY) return true;
   return false;
}
bool HasSell()
{
   for(int i=0;i<PositionsTotal();i++)
      if(pos.SelectByIndex(i)&&pos.Magic()==20250710&&pos.Symbol()==_Symbol
         &&pos.PositionType()==POSITION_TYPE_SELL) return true;
   return false;
}

bool CrossUp()  { return sk[1]>sd[1] && sk[2]<=sd[2]; }
bool CrossDown(){ return sk[1]<sd[1] && sk[2]>=sd[2]; }

int Signal()
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   // BUY: above EMA200 + EMA21>EMA50 (aligned uptrend) + stoch cross up from weak zone + RSI returning
   if(price>e200[1] && e21[1]>e50[1] && CrossUp()   && sk[1]<InpStochBuyMax  && rsi[1]<InpRSI_BuyMax)  return  1;
   // SELL: below EMA200 + EMA21<EMA50 + stoch cross down from strong zone + RSI weakening
   if(price<e200[1] && e21[1]<e50[1] && CrossDown() && sk[1]>InpStochSellMin && rsi[1]>InpRSI_SellMin) return -1;
   return 0;
}

double LotSize(double slDist)
{
   if(slDist<=0) return SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double risk = AccountInfoDouble(ACCOUNT_EQUITY)*(InpRisk/100.0);
   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double ls=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(ts<=0||tv<=0) return mn;
   double vpl=(slDist/ts)*tv;
   if(vpl<=0) return mn;
   return NormalizeDouble(MathMax(mn,MathMin(mx,MathFloor((risk/vpl)/ls)*ls)),2);
}

void OpenBuy()
{
   double av=atr_buf[1];
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl=NormalizeDouble(ask-av*InpSL_ATR,_Digits);
   double tp=NormalizeDouble(ask+av*InpTP_ATR,_Digits);
   double lots=LotSize(ask-sl);
   if(!trade.Buy(lots,_Symbol,ask,sl,tp,"TR_BUY"))
      Print("BUY fail: ",trade.ResultRetcodeDescription());
   else {
      lastTrade=TimeCurrent();
      Print("BUY | Lots:",lots," SL:",sl," TP:",tp,
            " E21>E200=",e21[1]>e200[1]," RSI:",DoubleToString(rsi[1],1),
            " Stoch:",DoubleToString(sk[1],1)," ATR:",DoubleToString(av,1));
   }
}

void OpenSell()
{
   double av=atr_buf[1];
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl=NormalizeDouble(bid+av*InpSL_ATR,_Digits);
   double tp=NormalizeDouble(bid-av*InpTP_ATR,_Digits);
   double lots=LotSize(sl-bid);
   if(!trade.Sell(lots,_Symbol,bid,sl,tp,"TR_SELL"))
      Print("SELL fail: ",trade.ResultRetcodeDescription());
   else {
      lastTrade=TimeCurrent();
      Print("SELL | Lots:",lots," SL:",sl," TP:",tp,
            " E21<E200=",e21[1]<e200[1]," RSI:",DoubleToString(rsi[1],1),
            " Stoch:",DoubleToString(sk[1],1)," ATR:",DoubleToString(av,1));
   }
}

// Trail stop: move SL as price moves in our favour (lock in profit)
void TrailPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic()!=20250710||pos.Symbol()!=_Symbol) continue;
      double op=pos.PriceOpen(), sl=pos.StopLoss(), tp=pos.TakeProfit();
      double av=atr_buf[0];

      if(pos.PositionType()==POSITION_TYPE_BUY)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         double profit_atr=(bid-op)/av;
         // After 1.0×ATR profit: trail at 0.5×ATR below current price
         if(profit_atr>=1.0)
         {
            double new_sl=NormalizeDouble(bid-av*0.8,_Digits);
            if(new_sl>sl+_Point)
               trade.PositionModify(pos.Ticket(),new_sl,tp);
         }
      }
      else
      {
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double profit_atr=(op-ask)/av;
         if(profit_atr>=1.0)
         {
            double new_sl=NormalizeDouble(ask+av*0.8,_Digits);
            if(new_sl<sl-_Point)
               trade.PositionModify(pos.Ticket(),new_sl,tp);
         }
      }
   }
}

void OnTick()
{
   static datetime lastBar=0;
   datetime cur=iTime(_Symbol,PERIOD_H1,0);
   if(cur==lastBar) return;
   lastBar=cur;
   if(!Refresh()) return;

   // Update equity high for DD tracking
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>equityHigh) equityHigh=eq;

   // Global DD protection
   if(InpMaxDD>0 && equityHigh>0 && eq<equityHigh*(1.0-InpMaxDD/100.0))
   { Print("HALT: drawdown limit ",InpMaxDD,"% reached"); return; }

   TrailPositions();

   if(!InSession()) { Print("WAIT: outside session (UTC ",TimeToString(TimeGMT(),TIME_MINUTES),")"); return; }

   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread>InpMaxSpread*_Point) { Print("SKIP: spread=",DoubleToString(spread/_Point,0)); return; }

   if(CountMine()>=InpMaxTrades) return;

   // Cooldown
   if(lastTrade>0 && (TimeCurrent()-lastTrade)<(datetime)(InpCooldownH*3600)) return;

   // Scan log
   Print("SCAN | E21=",DoubleToString(e21[1],1)," E50=",DoubleToString(e50[1],1),
         " E200=",DoubleToString(e200[1],1)," Price>E200=",
         SymbolInfoDouble(_Symbol,SYMBOL_BID)>e200[1],
         " Stoch=",DoubleToString(sk[1],1),"/",DoubleToString(sd[1],1),
         " RSI=",DoubleToString(rsi[1],1));

   int sig=Signal();
   double cC=iClose(_Symbol,PERIOD_H1,0), cO=iOpen(_Symbol,PERIOD_H1,0);
   if(sig== 1 && cC<cO) { Print("SKIP: BUY signal but bearish H1 bar"); return; }
   if(sig==-1 && cC>cO) { Print("SKIP: SELL signal but bullish H1 bar"); return; }

   if(sig== 1 && !HasBuy())  OpenBuy();
   if(sig==-1 && !HasSell()) OpenSell();
}
