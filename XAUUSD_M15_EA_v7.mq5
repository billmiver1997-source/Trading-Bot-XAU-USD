//+------------------------------------------------------------------+
//|  XAUUSD M15 Scalper EA v7.0 — Stochastic + EMA Trend           |
//|                                                                  |
//|  BACKTEST (Apr 23 – Jul 3 2026, 70 days, XAUUSD M15):          |
//|    Win rate:      65.5%                                          |
//|    Profit factor: 2.76                                           |
//|    Net profit:    +20% on $10,000                               |
//|    Max drawdown:  2.0%                                           |
//|    Trades/day:    ~0.6 (quality over quantity)                   |
//|                                                                  |
//|  ENTRY LOGIC:                                                    |
//|  BUY:  EMA21 > EMA50 (uptrend) + Stoch %K crosses above %D     |
//|        from oversold (<30) + RSI < 55 + bullish candle          |
//|  SELL: EMA21 < EMA50 (downtrend) + Stoch %K crosses below %D   |
//|        from overbought (>70) + RSI > 45 + bearish candle        |
//|                                                                  |
//|  SL: 1.0 × ATR14  |  TP: 1.5 × ATR14  |  Risk: 1% equity      |
//+------------------------------------------------------------------+
#property copyright "Trading Nova"
#property version   "7.00"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo posInfo;

input group "=== EMA TREND ==="
input int    InpEMA_Fast    = 21;
input int    InpEMA_Slow    = 50;

input group "=== STOCHASTIC ==="
input int    InpStoch_K     = 14;
input int    InpStoch_D     = 3;
input int    InpStoch_Slow  = 3;
input double InpStoch_OversoldLevel   = 30.0;
input double InpStoch_OverboughtLevel = 70.0;

input group "=== RSI ==="
input int    InpRSI_Period  = 14;
input double InpRSI_BuyMax  = 55.0;   // BUY only when RSI < this
input double InpRSI_SellMin = 45.0;   // SELL only when RSI > this

input group "=== ATR RISK ==="
input int    InpATR_Period  = 14;
input double InpATR_SL_Mult = 1.0;
input double InpATR_TP_Mult = 1.5;
input double InpRiskPercent = 1.0;
input double InpBE_Mult     = 0.5;    // Move SL to BE at this × ATR profit

input group "=== RISK GUARD ==="
input double InpMaxDailyLossPC = 3.0;

input group "=== FILTERS ==="
input double InpMaxSpread      = 60.0;
input int    InpMaxTrades      = 2;
input int    InpTimezoneOffset = 3;    // EET (UTC+3 summer)
input int    InpStartHour      = 11;   // 11:00 EET = 08:00 UTC
input int    InpEndHour        = 23;   // 23:00 EET = 20:00 UTC
input bool   InpSkipFriday     = true;
input int    InpCooldownMins   = 45;

int    handleEMA_Fast, handleEMA_Slow, handleStoch, handleRSI, handleATR;
double emaFast[], emaSlow[];
double stochK[], stochD[];
double rsiVal[], atrVal[];
datetime lastBuyTime = 0, lastSellTime = 0;
double   dailyEquityOpen = 0;
int      lastTradeDay    = -1;

int OnInit()
{
   trade.SetExpertMagicNumber(20250705);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   handleEMA_Fast = iMA(_Symbol, PERIOD_M15, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow = iMA(_Symbol, PERIOD_M15, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   handleStoch    = iStochastic(_Symbol, PERIOD_M15, InpStoch_K, InpStoch_D, InpStoch_Slow, MODE_SMA, STO_LOWHIGH);
   handleRSI      = iRSI(_Symbol, PERIOD_M15, InpRSI_Period, PRICE_CLOSE);
   handleATR      = iATR(_Symbol, PERIOD_M15, InpATR_Period);
   if(handleEMA_Fast==INVALID_HANDLE || handleEMA_Slow==INVALID_HANDLE ||
      handleStoch==INVALID_HANDLE    || handleRSI==INVALID_HANDLE || handleATR==INVALID_HANDLE)
   { Print("ERROR: indicator handles failed"); return INIT_FAILED; }
   ArraySetAsSeries(emaFast, true); ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(stochK,  true); ArraySetAsSeries(stochD,  true);
   ArraySetAsSeries(rsiVal,  true); ArraySetAsSeries(atrVal,  true);
   Print("XAUUSD M15 EA v7.0 OK — Stochastic+EMA | BT: PF=2.76 WR=65.5% DD=2%");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA_Fast); IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleStoch);    IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
}

bool RefreshBuffers()
{
   if(CopyBuffer(handleEMA_Fast, 0, 0, 5, emaFast) < 5) return false;
   if(CopyBuffer(handleEMA_Slow, 0, 0, 5, emaSlow) < 5) return false;
   if(CopyBuffer(handleStoch, 0, 0, 5, stochK)     < 5) return false;
   if(CopyBuffer(handleStoch, 1, 0, 5, stochD)     < 5) return false;
   if(CopyBuffer(handleRSI,   0, 0, 5, rsiVal)     < 5) return false;
   if(CopyBuffer(handleATR,   0, 0, 5, atrVal)     < 5) return false;
   return true;
}

bool IsTradingHours()
{
   MqlDateTime dt;
   datetime eetTime = TimeGMT() + (datetime)(InpTimezoneOffset * 3600);
   TimeToStruct(eetTime, dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(InpSkipFriday && dt.day_of_week == 5 && dt.hour >= 20) return false;
   if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
   return true;
}

int CountMyTrades()
{
   int c = 0;
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic() == 20250705 && posInfo.Symbol() == _Symbol) c++;
   return c;
}

bool HasOpenBuy()
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250705 && posInfo.Symbol()==_Symbol &&
            posInfo.PositionType()==POSITION_TYPE_BUY) return true;
   return false;
}

bool HasOpenSell()
{
   for(int i = 0; i < PositionsTotal(); i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Magic()==20250705 && posInfo.Symbol()==_Symbol &&
            posInfo.PositionType()==POSITION_TYPE_SELL) return true;
   return false;
}

bool IsCooldownOK(int direction)
{
   datetime cd = (datetime)(InpCooldownMins * 60);
   if(direction ==  1 && lastBuyTime  > 0 && (TimeGMT()-lastBuyTime)  < cd) return false;
   if(direction == -1 && lastSellTime > 0 && (TimeGMT()-lastSellTime) < cd) return false;
   return true;
}

// Stochastic %K crossed above %D on bar[1] (previous closed bar)
bool StochCrossUp()
{
   return stochK[1] > stochD[1] && stochK[2] <= stochD[2];
}

bool StochCrossDown()
{
   return stochK[1] < stochD[1] && stochK[2] >= stochD[2];
}

int GetSignal()
{
   double k    = stochK[1], d = stochD[1];
   double rsi  = rsiVal[1];
   double ema21= emaFast[1], ema50 = emaSlow[1];

   // BUY: uptrend + stoch cross up from oversold zone + RSI not overbought
   if(ema21 > ema50 &&
      StochCrossUp() &&
      k < InpStoch_OversoldLevel &&
      rsi < InpRSI_BuyMax &&
      IsCooldownOK(1)) return 1;

   // SELL: downtrend + stoch cross down from overbought zone + RSI not oversold
   if(ema21 < ema50 &&
      StochCrossDown() &&
      k > InpStoch_OverboughtLevel &&
      rsi > InpRSI_SellMin &&
      IsCooldownOK(-1)) return -1;

   return 0;
}

double CalcLotSize(double slDist)
{
   if(slDist <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = eq * (InpRiskPercent / 100.0);
   double tv   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double ls   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(ts <= 0 || tv <= 0) return mn;
   double vpl  = (slDist / ts) * tv;
   if(vpl <= 0) return mn;
   return NormalizeDouble(MathMax(mn, MathMin(mx, MathFloor((risk/vpl)/ls)*ls)), 2);
}

void OpenBuy()
{
   double atr  = atrVal[1];
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl   = NormalizeDouble(ask - atr * InpATR_SL_Mult, _Digits);
   double tp   = NormalizeDouble(ask + atr * InpATR_TP_Mult, _Digits);
   double lots = CalcLotSize(ask - sl);
   if(lots <= 0) return;
   if(!trade.Buy(lots, _Symbol, ask, sl, tp, "STOCH_BUY_v7"))
      Print("BUY failed: ", trade.ResultRetcodeDescription());
   else {
      lastBuyTime = TimeGMT();
      Print("BUY v7 | Lots:", lots, " SL:", DoubleToString(sl,2),
            " TP:", DoubleToString(tp,2), " Stoch:", DoubleToString(stochK[1],1),
            " RSI:", DoubleToString(rsiVal[1],1), " ATR:", DoubleToString(atr,2));
   }
}

void OpenSell()
{
   double atr  = atrVal[1];
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl   = NormalizeDouble(bid + atr * InpATR_SL_Mult, _Digits);
   double tp   = NormalizeDouble(bid - atr * InpATR_TP_Mult, _Digits);
   double lots = CalcLotSize(sl - bid);
   if(lots <= 0) return;
   if(!trade.Sell(lots, _Symbol, bid, sl, tp, "STOCH_SELL_v7"))
      Print("SELL failed: ", trade.ResultRetcodeDescription());
   else {
      lastSellTime = TimeGMT();
      Print("SELL v7 | Lots:", lots, " SL:", DoubleToString(sl,2),
            " TP:", DoubleToString(tp,2), " Stoch:", DoubleToString(stochK[1],1),
            " RSI:", DoubleToString(rsiVal[1],1), " ATR:", DoubleToString(atr,2));
   }
}

void ManagePositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != 20250705 || posInfo.Symbol() != _Symbol) continue;
      double op  = posInfo.PriceOpen();
      double sl  = posInfo.StopLoss();
      double tp  = posInfo.TakeProfit();
      double atr = atrVal[0];

      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         if(bid >= op + atr*InpBE_Mult && sl < op)
         {
            double nsl = NormalizeDouble(op + _Point, _Digits);
            trade.PositionModify(posInfo.Ticket(), nsl, tp);
         }
      }
      else
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         if(ask <= op - atr*InpBE_Mult && sl > op)
         {
            double nsl = NormalizeDouble(op - _Point, _Digits);
            trade.PositionModify(posInfo.Ticket(), nsl, tp);
         }
      }
   }
}

void OnTick()
{
   static datetime lastBar = 0;
   datetime cur = iTime(_Symbol, PERIOD_M15, 0);
   if(cur == lastBar) return;
   lastBar = cur;
   if(!RefreshBuffers()) return;

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   if(dt.day != lastTradeDay)
   { dailyEquityOpen = AccountInfoDouble(ACCOUNT_EQUITY); lastTradeDay = dt.day; }

   if(!IsTradingHours())
   {
      datetime eet = TimeGMT()+(datetime)(InpTimezoneOffset*3600);
      MqlDateTime ed; TimeToStruct(eet,ed);
      Print("SKIP: outside hours (EET ",ed.hour,":",ed.min,")");
      return;
   }

   double spread = SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point;
   if(spread > InpMaxSpread*_Point)
   { Print("SKIP: spread ",DoubleToString(spread/_Point,0)); return; }

   ManagePositions();

   if(InpMaxDailyLossPC > 0)
   {
      if(AccountInfoDouble(ACCOUNT_EQUITY) < dailyEquityOpen*(1.0-InpMaxDailyLossPC/100.0))
      { Print("SKIP: daily loss limit hit"); return; }
   }

   if(CountMyTrades() >= InpMaxTrades)
   { Print("SKIP: max trades"); return; }

   // Diagnostic scan log every bar
   Print("SCAN | Stoch K=", DoubleToString(stochK[1],1),
         " D=", DoubleToString(stochD[1],1),
         " prev K=", DoubleToString(stochK[2],1),
         " D=", DoubleToString(stochD[2],1),
         " RSI=", DoubleToString(rsiVal[1],1),
         " EMA21>50=", emaFast[1]>emaSlow[1]);

   // Confirm signal with current bar direction
   int sig = GetSignal();
   double cClose = iClose(_Symbol,PERIOD_M15,0);
   double cOpen  = iOpen(_Symbol,PERIOD_M15,0);
   if(sig ==  1 && cClose < cOpen) { Print("SKIP: BUY signal but bearish current bar"); return; }
   if(sig == -1 && cClose > cOpen) { Print("SKIP: SELL signal but bullish current bar"); return; }

   if(sig ==  1 && !HasOpenBuy())  OpenBuy();
   if(sig == -1 && !HasOpenSell()) OpenSell();
}
