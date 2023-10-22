//+------------------------------------------------------------------+
//|                                                       ADX_MA.mq5 |
//|                                     Copyright 2023, Shuta Shibue |
//|                                       Link inMQLHeadStandard |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Shuta Shibue"
#property link "Link"
#property version "1.00"

#include "Transaction/Transaction.mqh"
#include <Indicators/Trend.mqh>
#include <Indicators/Oscilators.mqh>

input double MaximumRisk = 0.02; // Maximum Risk in percentage
input double DecreaseFactor = 3; // Descrease factor
input int MovingPeriod = 10;     // Moving Average period
input int MovingShift = 0;       // Moving Average shift
input int ADXBase = 14;

int MaHandle = 0;
CiADX adx;
CiMA ma;
Transaction transaction;

#define MA_MAGIC 1234503

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    transaction.Initialize(MA_MAGIC, MaximumRisk, DecreaseFactor);
    ma = new CiMA;
    ma.Create(_Symbol, _Period, MovingPeriod, MovingShift, MODE_SMA, PRICE_CLOSE);
    ma.Refresh(-1);

    adx = new CiADX;
    adx.Create(_Symbol, _Period, ADXBase);
    adx.Refresh(-1);

    //---
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    MqlRates rt[2];
    if (CopyRates(_Symbol, _Period, 0, 2, rt) != 2)
    {
        printf("failed to get data");
        return;
    }
    // ローソク足が確定したときだけ動作させる
    static datetime time = iTime(_Symbol, PERIOD_CURRENT, 0);
    if (time == iTime(_Symbol, PERIOD_CURRENT, 0))
        return;

    adx.Refresh();
    ma.Refresh();

    double currentAdx = adx.Main(0);
    bool adxStrength = currentAdx > adx.Main(5) && currentAdx > 20 && currentAdx < 40;
    bool adxWeakness = currentAdx < adx.Main(5);
    bool maWeakness = ma.Main(10) > ma.Main(20) != ma.Main(0) > ma.Main(10);
    TrendDirection adxTrendDir = adx.Plus(0) > adx.Minus(0) ? UP : DOWN;
    TrendDirection maTrendDir = ma.Main(0) > ma.Main(10) ? UP : DOWN;

    if (adxStrength && PositionsTotal() == 0)
    {
        if (adxTrendDir == UP && maTrendDir == UP)
        {
            printf("ma.diff " + DoubleToString(ma.Main(0) - ma.Main(10)));
            printf("adx.diff " + DoubleToString(adx.Plus(0) - adx.Minus(0)));
            transaction.Buy();
        }
        else if (adxTrendDir == DOWN && maTrendDir == DOWN)
        {
            printf("ma.diff " + DoubleToString(ma.Main(0) - ma.Main(10)));
            printf("+-.diff " + DoubleToString(adx.Plus(0) - adx.Minus(0)));
            transaction.Sell();
        }
    }
    else if (adxWeakness && maWeakness && PositionsTotal() != 0)
    {

        printf("close");
        transaction.Close();
    }
}

//+------------------------------------------------------------------+

enum TrendDirection
{
    UP,
    DOWN,
    FLAT
};