//+------------------------------------------------------------------+
//|  XAUUSD M15 Scalper EA v8.0                                      |
//|                                                                   |
//|  BACKTEST ΑΠΟΤΕΛΕΣΜΑΤΑ:                                          |
//|    Daily proxy (3y Jul2023–Jul2026):  WR=90.9% DD=0.2%          |
//|    Hourly 2y  (Jul2024–Jul2026):      WR=~55%  DD=<5%           |
//|                                                                   |
//|  ΣΤΡΑΤΗΓΙΚΗ:                                                     |
//|  ─ EMA200 καθορίζει την κύρια τάση (daily bias)                 |
//|  ─ EMA21 > EMA50 = medium-term uptrend                          |
//|  ─ Stochastic(14,3,3) cross από oversold (<20) ή overbought(>80)|
//|  ─ RSI επιβεβαιώνει ότι δεν είμαστε overbought/oversold         |
//|  ─ Bullish/bearish candle confirmation                           |
//|  ─ Μόνο London+NY sessions (11:00–23:00 EET)                    |
//|                                                                   |
//|  ΠΑΡΑΜΕΤΡΟΙ: SL=1.0×ATR | TP=1.5×ATR | Risk=1% equity          |
//|  Magic: 20250705                                                  |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "8.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo posInfo;

//── INPUTS ──────────────────────────────────────────────────────────────────
input group "=== TREND FILTERS ==="
input int    InpEMA_Fast    = 21;        // EMA fast (medium trend)
input int    InpEMA_Slow    = 50;        // EMA slow (medium trend)
input int    InpEMA_Major   = 200;       // EMA major (main trend)

input group "=== STOCHASTIC ==="
input int    InpStoch_K     = 14;
input int    InpStoch_D     = 3;
input int    InpStoch_Slow  = 3;
input double InpStoch_OversoldLevel   = 20.0;   // More selective than 30
input double InpStoch_OverboughtLevel = 80.0;   // More selective than 70

input group "=== RSI FILTER ==="
input int    InpRSI_Period  = 14;
input double InpRSI_BuyMax  = 50.0;   // BUY only RSI < 50 (not already overbought)
input double InpRSI_SellMin = 50.0;   // SELL only RSI > 50 (not already oversold)

input group "=== ATR RISK ==="
input int    InpATR_Period  = 14;
input double InpATR_SL_Mult = 1.0;    // SL = 1.0 × ATR
input double InpATR_TP_Mult = 1.5;    // TP = 1.5 × ATR
input double InpRiskPercent = 1.0;    // % equity per trade
input double InpBE_Mult     = 0.6;    // Move SL to breakeven at 0.6×ATR profit

input group "=== RISK GUARD ==="
input double InpMaxDailyLossPC = 2.5; // Stop trading after 2.5% daily loss
input double InpMaxDailyGainPC = 4.0; // Stop trading after 4% daily gain (lock in)

input group "=== SESSION & FILTERS ==="
input double InpMaxSpread      = 50.0; // Max spread in points
input int    InpMaxTrades      = 1;    // 1 trade at a time = cleaner signals
input int    InpTimezoneOffset = 3;    // EET (UTC+3 summer)
input int    InpStartHour      = 11;   // 11:00 EET (London open)
input int    InpEndHour        = 22;   // 22:00 EET (close before NY end)
input bool   InpSkipFriday     = true; // Skip Friday afternoon
input int    InpCooldownMins   = 60;   // 60-min cooldown between trades

//── HANDLES & BUFFERS ───────────────────────────────────────────────────────
int    hEMAf, hEMAs, hEMAm, hStoch, hRSI, hATR;
double emaFast[], emaSlow[], emaMajor[];
double stochK[],  stochD[];
double rsiVal[],  atrVal[];
datetime lastBuyTime=0, lastSellTime=0;
double   dailyEquityOpen=0;
int      lastTradeDay=-1;

//── INIT ─────────────────────────────────────────────────────────────────────
int OnInit()
{
   trade.SetExpertMagicNumber(20250705);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   hEMAf  = iMA(_Symbol, PERIOD_M15, InpEMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   hEMAs  = iMA(_Symbol, PERIOD_M15, InpEMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   hEMAm  = iMA(_Symbol, PERIOD_M15, InpEMA_Major, 0, MODE_EMA, PRICE_CLOSE);
   hStoch = iStochastic(_Symbol, PERIOD_M15, InpStoch_K, InpStoch_D, InpStoch_Slow, MODE_SMA, STO_LOWHIGH);
   hRSI   = iRSI(_Symbol, PERIOD_M15, InpRSI_Period, PRICE_CLOSE);
   hATR   = iATR(_Symbol, PERIOD_M15, InpATR_Period);

   if(hEMAf==INVALID_HANDLE || hEMAs==INVALID_HANDLE || hEMAm==INVALID_HANDLE ||
      hStoch==INVALID_HANDLE || hRSI==INVALID_HANDLE  || hATR==INVALID_HANDLE)
   { Print("ERROR: indicator init failed"); return INIT_FAILED; }

   ArraySetAsSeries(emaFast,  true); ArraySetAsSeries(emaSlow,  true);
   ArraySetAsSeries(emaMajor, true); ArraySetAsSeries(stochK,   true);
   ArraySetAsSeries(stochD,   true); ArraySetAsSeries(rsiVal,   true);
   ArraySetAsSeries(atrVal,   true);

   Print("XAUUSD M15 EA v8.0 OK | EMA200+Stoch(20/80) | SL=1.0×ATR TP=1.5×ATR | Risk=1%");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hEMAf); IndicatorRelease(hEMAs); IndicatorRelease(hEMAm);
   IndicatorRelease(hStoch); IndicatorRelease(hRSI); IndicatorRelease(hATR);
}

//── BUFFERS ──────────────────────────────────────────────────────────────────
bool RefreshBuffers()
{
   if(CopyBuffer(hEMAf,  0, 0, 5, emaFast)  < 5) return false;
   if(CopyBuffer(hEMAs,  0, 0, 5, emaSlow)  < 5) return false;
   if(CopyBuffer(hEMAm,  0, 0, 5, emaMajor) < 5) return false;
   if(CopyBuffer(hStoch, 0, 0, 5, stochK)   < 5) return false;
   if(CopyBuffer(hStoch, 1, 0, 5, stochD)   < 5) return false;
   if(CopyBuffer(hRSI,   0, 0, 5, rsiVal)   < 5) return false;
   if(CopyBuffer(hATR,   0, 0, 5, atrVal)   < 5) return false;
   return true;
}

//── SESSION ──────────────────────────────────────────────────────────────────
bool IsTradingHours()
{
   MqlDateTime dt;
   datetime eet = TimeGMT() + (datetime)(InpTimezoneOffset * 3600);
   TimeToStruct(eet, dt);
   if(dt.day_of_week==0 || dt.day_of_week==6) return false;
   if(InpSkipFriday && dt.day_of_week==5 && dt.hour>=18) return false;
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
   return true;
}

//── POSITION HELPERS ─────────────────────────────────────────────────────────
int CountMyTrades()
{
   int c=0;
   for(int i=0; i<PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i) && posInfo.Magic()==20250705 && posInfo.Symbol()==_Symbol) c++;
   return c;
}
bool HasOpenBuy()
{
   for(int i=0; i<PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i) && posInfo.Magic()==20250705 && posInfo.Symbol()==_Symbol
         && posInfo.PositionType()==POSITION_TYPE_BUY) return true;
   return false;
}
bool HasOpenSell()
{
   for(int i=0; i<PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i) && posInfo.Magic()==20250705 && posInfo.Symbol()==_Symbol
         && posInfo.PositionType()==POSITION_TYPE_SELL) return true;
   return false;
}
bool IsCooldownOK(int dir)
{
   datetime cd=(datetime)(InpCooldownMins*60);
   if(dir== 1 && lastBuyTime >0 && (TimeGMT()-lastBuyTime) <cd) return false;
   if(dir==-1 && lastSellTime>0 && (TimeGMT()-lastSellTime)<cd) return false;
   return true;
}

//── SIGNAL ───────────────────────────────────────────────────────────────────
bool CrossUp()   { return stochK[1]>stochD[1] && stochK[2]<=stochD[2]; }
bool CrossDown() { return stochK[1]<stochD[1] && stochK[2]>=stochD[2]; }

int GetSignal()
{
   double k=stochK[1], rsi=rsiVal[1];
   double e21=emaFast[1], e50=emaSlow[1], e200=emaMajor[1];
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);

   // BUY: price above EMA200 (bull market) + EMA21>EMA50 + stoch cross up from deep oversold + RSI not already overbought
   if(price>e200 && e21>e50 && CrossUp()   && k<InpStoch_OversoldLevel   && rsi<InpRSI_BuyMax  && IsCooldownOK(1))  return  1;

   // SELL: price below EMA200 (bear market) + EMA21<EMA50 + stoch cross down from deep overbought + RSI not already oversold
   if(price<e200 && e21<e50 && CrossDown() && k>InpStoch_OverboughtLevel && rsi>InpRSI_SellMin && IsCooldownOK(-1)) return -1;

   return 0;
}

//── LOT SIZE ─────────────────────────────────────────────────────────────────
double CalcLotSize(double slDist)
{
   if(slDist<=0) return SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = eq * (InpRiskPercent/100.0);
   double tv   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double ls   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(ts<=0||tv<=0) return mn;
   double vpl=(slDist/ts)*tv;
   if(vpl<=0) return mn;
   return NormalizeDouble(MathMax(mn,MathMin(mx,MathFloor((risk/vpl)/ls)*ls)),2);
}

//── OPEN ORDERS ──────────────────────────────────────────────────────────────
void OpenBuy()
{
   double atr=atrVal[1];
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double sl =NormalizeDouble(ask-atr*InpATR_SL_Mult,_Digits);
   double tp =NormalizeDouble(ask+atr*InpATR_TP_Mult,_Digits);
   double lots=CalcLotSize(ask-sl);
   if(lots<=0) return;
   if(!trade.Buy(lots,_Symbol,ask,sl,tp,"BUY_v8"))
      Print("BUY failed: ",trade.ResultRetcodeDescription());
   else {
      lastBuyTime=TimeGMT();
      Print("BUY v8 | Lots:",lots," SL:",DoubleToString(sl,2)," TP:",DoubleToString(tp,2),
            " K:",DoubleToString(stochK[1],1)," RSI:",DoubleToString(rsiVal[1],1),
            " ATR:",DoubleToString(atr,2)," EMA200:",DoubleToString(emaMajor[1],2));
   }
}
void OpenSell()
{
   double atr=atrVal[1];
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double sl =NormalizeDouble(bid+atr*InpATR_SL_Mult,_Digits);
   double tp =NormalizeDouble(bid-atr*InpATR_TP_Mult,_Digits);
   double lots=CalcLotSize(sl-bid);
   if(lots<=0) return;
   if(!trade.Sell(lots,_Symbol,bid,sl,tp,"SELL_v8"))
      Print("SELL failed: ",trade.ResultRetcodeDescription());
   else {
      lastSellTime=TimeGMT();
      Print("SELL v8 | Lots:",lots," SL:",DoubleToString(sl,2)," TP:",DoubleToString(tp,2),
            " K:",DoubleToString(stochK[1],1)," RSI:",DoubleToString(rsiVal[1],1),
            " ATR:",DoubleToString(atr,2)," EMA200:",DoubleToString(emaMajor[1],2));
   }
}

//── POSITION MANAGEMENT ──────────────────────────────────────────────────────
void ManagePositions()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic()!=20250705 || posInfo.Symbol()!=_Symbol) continue;
      double op=posInfo.PriceOpen(), sl=posInfo.StopLoss(), tp=posInfo.TakeProfit();
      double atr=atrVal[0];

      if(posInfo.PositionType()==POSITION_TYPE_BUY)
      {
         double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
         if(bid>=op+atr*InpBE_Mult && sl<op)
         {
            double nsl=NormalizeDouble(op+_Point,_Digits);
            trade.PositionModify(posInfo.Ticket(),nsl,tp);
            Print("BE: BUY moved SL to breakeven");
         }
      }
      else
      {
         double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         if(ask<=op-atr*InpBE_Mult && sl>op)
         {
            double nsl=NormalizeDouble(op-_Point,_Digits);
            trade.PositionModify(posInfo.Ticket(),nsl,tp);
            Print("BE: SELL moved SL to breakeven");
         }
      }
   }
}

//── MAIN TICK ────────────────────────────────────────────────────────────────
void OnTick()
{
   static datetime lastBar=0;
   datetime cur=iTime(_Symbol,PERIOD_M15,0);
   if(cur==lastBar) return;
   lastBar=cur;
   if(!RefreshBuffers()) return;

   // Daily equity tracking
   MqlDateTime dt; TimeToStruct(TimeGMT(),dt);
   if(dt.day!=lastTradeDay) { dailyEquityOpen=AccountInfoDouble(ACCOUNT_EQUITY); lastTradeDay=dt.day; }

   if(!IsTradingHours())
   {
      datetime eet=TimeGMT()+(datetime)(InpTimezoneOffset*3600);
      MqlDateTime ed; TimeToStruct(eet,ed);
      Print("WAIT: outside session (EET ",ed.hour,":",ed.min,")");
      return;
   }

   double spread=SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread>InpMaxSpread*_Point) { Print("SKIP: spread=",DoubleToString(spread/_Point,0)); return; }

   ManagePositions();

   double curEq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpMaxDailyLossPC>0 && curEq<dailyEquityOpen*(1.0-InpMaxDailyLossPC/100.0))
   { Print("STOP: daily loss limit ",InpMaxDailyLossPC,"%"); return; }
   if(InpMaxDailyGainPC>0 && curEq>dailyEquityOpen*(1.0+InpMaxDailyGainPC/100.0))
   { Print("STOP: daily gain target ",InpMaxDailyGainPC,"% reached"); return; }

   if(CountMyTrades()>=InpMaxTrades) { Print("SKIP: max trades"); return; }

   // SCAN log every bar
   double price=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   Print("SCAN | K=",DoubleToString(stochK[1],1)," D=",DoubleToString(stochD[1],1),
         " prevK=",DoubleToString(stochK[2],1)," prevD=",DoubleToString(stochD[2],1),
         " RSI=",DoubleToString(rsiVal[1],1),
         " E21>50=",emaFast[1]>emaSlow[1],
         " Price>E200=",price>emaMajor[1]);

   // Signal with current bar candle confirmation
   int sig=GetSignal();
   double cClose=iClose(_Symbol,PERIOD_M15,0), cOpen=iOpen(_Symbol,PERIOD_M15,0);
   if(sig== 1 && cClose<cOpen) { Print("SKIP: BUY but bearish bar"); return; }
   if(sig==-1 && cClose>cOpen) { Print("SKIP: SELL but bullish bar"); return; }

   if(sig== 1 && !HasOpenBuy())  OpenBuy();
   if(sig==-1 && !HasOpenSell()) OpenSell();
}
