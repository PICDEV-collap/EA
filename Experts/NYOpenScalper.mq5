//+------------------------------------------------------------------+
//|                                                NYOpenScalper.mq5 |
//|        NY Open Range Break & Retest Scalper (JDU Trader system)  |
//|                                                                  |
//|  Strategy:                                                       |
//|   1. At NY open (20:30 Thai time / 9:30 New York) mark the       |
//|      High/Low of the FIRST M5 candle (Opening Range).            |
//|   2. On M1, wait for a candle to CLOSE outside the range         |
//|      ("break with candle body", not just a wick).                |
//|   3. Wait for price to come back and RETEST the broken level.    |
//|   4. Wait for a strong-bodied confirmation candle in the         |
//|      breakout direction that closes back outside the level.      |
//|   5. Enter at the close of the confirmation candle.              |
//|      SL below/above the confirmation candle, TP = SL x RR.       |
//|                                                                  |
//|  NOTE: SessionHour/SessionMinute are in BROKER SERVER TIME.      |
//|  You must set them so they match 9:30 New York on your broker.   |
//+------------------------------------------------------------------+
#property copyright "EA Development"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- Session / timing (broker server time!)
input group "=== Session (broker server time) ==="
input int      SessionHour        = 16;     // NY open hour (server time)
input int      SessionMinute      = 30;     // NY open minute (server time)
input int      WindowMinutes      = 60;     // Stop looking for setups N minutes after open

//--- Strategy parameters
input group "=== Strategy ==="
input int      RetestBufferPoints = 30;     // Retest zone buffer (points)
input int      MinBodyPoints      = 50;     // Confirmation: min candle body (points)
input double   MinBodyRatio       = 0.60;   // Confirmation: min body/range ratio (0..1)
input int      SLBufferPoints     = 30;     // SL buffer beyond confirmation candle (points)
input double   RiskRewardRatio    = 2.0;    // TP = SL distance x RR
input bool     AllowBuy           = true;   // Allow BUY setups
input bool     AllowSell          = true;   // Allow SELL setups

//--- Money management
input group "=== Money management ==="
input bool     UseRiskPercent     = true;   // Size lot by risk percent (else fixed lot)
input double   RiskPercent        = 1.0;    // Risk per trade (% of balance)
input double   FixedLot           = 0.01;   // Fixed lot (when UseRiskPercent = false)

//--- Limits / misc
input group "=== Limits / misc ==="
input int      MaxTradesPerDay    = 1;      // Max trades per day
input long     MagicNumber        = 20260611; // Magic number
input bool     DrawRangeLines     = true;   // Draw opening range lines on chart

//--- State machine
enum ENUM_SETUP_STATE
  {
   ST_WAIT_RANGE = 0,   // waiting for the first M5 candle to close
   ST_WAIT_BREAKOUT,    // range set, waiting for M1 body-close breakout
   ST_WAIT_RETEST,      // breakout done, waiting for pullback to the level
   ST_WAIT_CONFIRM,     // retest touched, waiting for confirmation candle
   ST_DONE              // trade taken / window expired -> idle until next day
  };

CTrade            trade;

ENUM_SETUP_STATE  g_state        = ST_WAIT_RANGE;
int               g_dir          = 0;        // +1 buy setup, -1 sell setup
double            g_rangeHigh    = 0.0;
double            g_rangeLow     = 0.0;
datetime          g_sessionStart = 0;        // today's session start (server time)
datetime          g_currentDay   = 0;        // start of current trading day
datetime          g_lastM1Bar    = 0;        // last processed closed M1 bar time
int               g_tradesToday  = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(SessionHour < 0 || SessionHour > 23 || SessionMinute < 0 || SessionMinute > 59)
     {
      Print("NYOpenScalper: invalid SessionHour/SessionMinute");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(MinBodyRatio < 0.0 || MinBodyRatio > 1.0)
     {
      Print("NYOpenScalper: MinBodyRatio must be between 0 and 1");
      return(INIT_PARAMETERS_INCORRECT);
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   ResetDay(StartOfDay(TimeCurrent()));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteRangeLines();
  }

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
  {
   datetime now = TimeCurrent();

   //--- new trading day -> reset state machine
   datetime day = StartOfDay(now);
   if(day != g_currentDay)
      ResetDay(day);

   //--- step 1: capture the opening range from the first M5 candle
   if(g_state == ST_WAIT_RANGE)
     {
      TryCaptureRange(now);
      return;
     }

   if(g_state == ST_DONE)
      return;

   //--- setup window expired -> stop for today
   if(now >= g_sessionStart + (datetime)WindowMinutes * 60)
     {
      g_state = ST_DONE;
      Print("NYOpenScalper: setup window expired, no more entries today");
      return;
     }

   //--- act only once per closed M1 candle
   datetime barTime = iTime(_Symbol, PERIOD_M1, 0);
   if(barTime == g_lastM1Bar)
      return;
   g_lastM1Bar = barTime;

   ProcessClosedM1Bar();
  }

//+------------------------------------------------------------------+
//| Reset all per-day state                                          |
//+------------------------------------------------------------------+
void ResetDay(const datetime dayStart)
  {
   g_currentDay   = dayStart;
   g_sessionStart = dayStart + (datetime)(SessionHour * 3600 + SessionMinute * 60);
   g_state        = ST_WAIT_RANGE;
   g_dir          = 0;
   g_rangeHigh    = 0.0;
   g_rangeLow     = 0.0;
   g_lastM1Bar    = 0;
   g_tradesToday  = 0;
   DeleteRangeLines();
  }

//+------------------------------------------------------------------+
//| Capture High/Low of the first M5 candle after session start      |
//+------------------------------------------------------------------+
void TryCaptureRange(const datetime now)
  {
   //--- the opening M5 candle must be fully closed first
   if(now < g_sessionStart + 5 * 60)
      return;

   int shift = iBarShift(_Symbol, PERIOD_M5, g_sessionStart, true);
   if(shift < 1) // not found, or candle still forming
      return;

   //--- make sure the found candle really is the session-open candle
   if(iTime(_Symbol, PERIOD_M5, shift) != g_sessionStart)
      return;

   g_rangeHigh = iHigh(_Symbol, PERIOD_M5, shift);
   g_rangeLow  = iLow(_Symbol, PERIOD_M5, shift);
   g_state     = ST_WAIT_BREAKOUT;
   g_lastM1Bar = iTime(_Symbol, PERIOD_M1, 0);

   PrintFormat("NYOpenScalper: opening range set  High=%s  Low=%s",
               DoubleToString(g_rangeHigh, _Digits),
               DoubleToString(g_rangeLow, _Digits));

   if(DrawRangeLines)
      DrawRange();
  }

//+------------------------------------------------------------------+
//| State machine driven by the last CLOSED M1 candle (shift 1)      |
//+------------------------------------------------------------------+
void ProcessClosedM1Bar()
  {
   double op = iOpen(_Symbol,  PERIOD_M1, 1);
   double hi = iHigh(_Symbol,  PERIOD_M1, 1);
   double lo = iLow(_Symbol,   PERIOD_M1, 1);
   double cl = iClose(_Symbol, PERIOD_M1, 1);

   //--- ignore candles formed before the range existed
   if(iTime(_Symbol, PERIOD_M1, 1) < g_sessionStart + 5 * 60)
      return;

   double buffer = RetestBufferPoints * _Point;

   switch(g_state)
     {
      //================================================================
      case ST_WAIT_BREAKOUT:
        {
         //--- BUY breakout: bullish candle CLOSES above the range high
         if(AllowBuy && cl > g_rangeHigh && cl > op)
           {
            g_dir   = 1;
            g_state = ST_WAIT_RETEST;
            Print("NYOpenScalper: BUY breakout (body close above High), waiting for retest");
           }
         //--- SELL breakout: bearish candle CLOSES below the range low
         else if(AllowSell && cl < g_rangeLow && cl < op)
           {
            g_dir   = -1;
            g_state = ST_WAIT_RETEST;
            Print("NYOpenScalper: SELL breakout (body close below Low), waiting for retest");
           }
         break;
        }

      //================================================================
      case ST_WAIT_RETEST:
        {
         if(CheckInvalidation(op, cl))
            break;

         if(g_dir > 0)
           {
            //--- pullback touches the broken High zone
            if(lo <= g_rangeHigh + buffer)
              {
               //--- retest + confirmation can happen on the same candle
               if(IsConfirmCandle(op, hi, lo, cl, g_dir))
                  EnterTrade(hi, lo);
               else
                 {
                  g_state = ST_WAIT_CONFIRM;
                  Print("NYOpenScalper: BUY retest touched, waiting for confirmation candle");
                 }
              }
           }
         else // g_dir < 0
           {
            //--- pullback touches the broken Low zone
            if(hi >= g_rangeLow - buffer)
              {
               if(IsConfirmCandle(op, hi, lo, cl, g_dir))
                  EnterTrade(hi, lo);
               else
                 {
                  g_state = ST_WAIT_CONFIRM;
                  Print("NYOpenScalper: SELL retest touched, waiting for confirmation candle");
                 }
              }
           }
         break;
        }

      //================================================================
      case ST_WAIT_CONFIRM:
        {
         if(CheckInvalidation(op, cl))
            break;

         if(IsConfirmCandle(op, hi, lo, cl, g_dir))
            EnterTrade(hi, lo);
         //--- no confirmation yet: keep waiting (until window cutoff
         //    or invalidation). Never enter just because price hit
         //    the line - that is the "no confirm = no entry" rule.
         break;
        }

      default:
         break;
     }
  }

//+------------------------------------------------------------------+
//| Setup invalidation: price closes back through the OPPOSITE side  |
//| of the range -> cancel the setup and re-arm breakout detection   |
//| (this closed candle may itself qualify as the opposite breakout) |
//+------------------------------------------------------------------+
bool CheckInvalidation(const double op, const double cl)
  {
   bool invalidated = false;

   if(g_dir > 0 && cl < g_rangeLow)
      invalidated = true;
   if(g_dir < 0 && cl > g_rangeHigh)
      invalidated = true;

   if(!invalidated)
      return(false);

   PrintFormat("NYOpenScalper: %s setup invalidated (close through opposite side of range)",
               g_dir > 0 ? "BUY" : "SELL");

   int oldDir = g_dir;
   g_dir   = 0;
   g_state = ST_WAIT_BREAKOUT;

   //--- the invalidating candle may be a valid breakout the other way
   if(oldDir > 0 && AllowSell && cl < g_rangeLow && cl < op)
     {
      g_dir   = -1;
      g_state = ST_WAIT_RETEST;
      Print("NYOpenScalper: SELL breakout (body close below Low), waiting for retest");
     }
   else if(oldDir < 0 && AllowBuy && cl > g_rangeHigh && cl > op)
     {
      g_dir   = 1;
      g_state = ST_WAIT_RETEST;
      Print("NYOpenScalper: BUY breakout (body close above High), waiting for retest");
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Confirmation candle: strong body in the breakout direction that  |
//| closes back outside the broken level                             |
//+------------------------------------------------------------------+
bool IsConfirmCandle(const double op, const double hi, const double lo,
                     const double cl, const int dir)
  {
   double body  = MathAbs(cl - op);
   double range = hi - lo;

   if(body < MinBodyPoints * _Point)
      return(false);
   if(range <= 0.0 || body / range < MinBodyRatio)
      return(false);

   if(dir > 0)
      return(cl > op && cl > g_rangeHigh);   // bullish, closes above the level
   else
      return(cl < op && cl < g_rangeLow);    // bearish, closes below the level
  }

//+------------------------------------------------------------------+
//| Open the trade at confirmation-candle close                      |
//+------------------------------------------------------------------+
void EnterTrade(const double confirmHigh, const double confirmLow)
  {
   if(g_tradesToday >= MaxTradesPerDay)
     {
      g_state = ST_DONE;
      return;
     }

   double slBuffer = SLBufferPoints * _Point;
   double entry, sl, tp;

   if(g_dir > 0)
     {
      entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = confirmLow - slBuffer;
      if(sl >= entry)
        {
         Print("NYOpenScalper: invalid BUY SL (above entry), trade skipped");
         g_state = ST_DONE;
         return;
        }
      tp = entry + (entry - sl) * RiskRewardRatio;
     }
   else
     {
      entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = confirmHigh + slBuffer;
      if(sl <= entry)
        {
         Print("NYOpenScalper: invalid SELL SL (below entry), trade skipped");
         g_state = ST_DONE;
         return;
        }
      tp = entry - (sl - entry) * RiskRewardRatio;
     }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   double lot = CalcLot(MathAbs(entry - sl));
   if(lot <= 0.0)
     {
      Print("NYOpenScalper: lot calculation failed, trade skipped");
      g_state = ST_DONE;
      return;
     }

   bool ok;
   if(g_dir > 0)
      ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, "NYOpenScalper BUY");
   else
      ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, "NYOpenScalper SELL");

   if(ok)
     {
      g_tradesToday++;
      PrintFormat("NYOpenScalper: %s opened  lot=%s  SL=%s  TP=%s",
                  g_dir > 0 ? "BUY" : "SELL",
                  DoubleToString(lot, 2),
                  DoubleToString(sl, _Digits),
                  DoubleToString(tp, _Digits));
     }
   else
      PrintFormat("NYOpenScalper: order failed  retcode=%d  (%s)",
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());

   //--- one setup per day: done either way
   g_state = ST_DONE;
  }

//+------------------------------------------------------------------+
//| Lot size from risk percent (or fixed lot)                        |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance)
  {
   double lot;

   if(!UseRiskPercent)
      lot = FixedLot;
   else
     {
      double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0 || slDistance <= 0.0)
         return(0.0);

      double riskMoney   = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
      double lossPerLot  = slDistance / tickSize * tickValue;
      if(lossPerLot <= 0.0)
         return(0.0);

      lot = riskMoney / lossPerLot;
     }

   //--- normalize to broker constraints
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0.0)
      lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(minLot, MathMin(maxLot, lot));

   return(NormalizeDouble(lot, 2));
  }

//+------------------------------------------------------------------+
//| Chart objects                                                    |
//+------------------------------------------------------------------+
void DrawRange()
  {
   datetime from = g_sessionStart;
   datetime to   = g_sessionStart + (datetime)WindowMinutes * 60;

   DrawLine("NYOS_High", from, to, g_rangeHigh, clrLimeGreen);
   DrawLine("NYOS_Low",  from, to, g_rangeLow,  clrOrangeRed);
  }

void DrawLine(const string name, const datetime from, const datetime to,
              const double price, const color clr)
  {
   ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, from, price, to, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

void DeleteRangeLines()
  {
   ObjectDelete(0, "NYOS_High");
   ObjectDelete(0, "NYOS_Low");
  }

//+------------------------------------------------------------------+
//| Start of day (server time)                                       |
//+------------------------------------------------------------------+
datetime StartOfDay(const datetime t)
  {
   return(t - (t % 86400));
  }
//+------------------------------------------------------------------+
