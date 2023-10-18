//+------------------------------------------------------------------+
//|                                              Moving Averages.mq5 |
//|                   Copyright 2009-2017, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2009-2017, MetaQuotes Software Corp."
#property link "http://www.mql5.com"
#property version "1.00"

#include <Trade\Trade.mqh>
#include "Transaction.mqh"

input double MaximumRisk = 0.02; // Maximum Risk in percentage
input double DecreaseFactor = 3; // Descrease factor
input int MovingPeriod = 12;     // Moving Average period
input int MovingShift = 6;       // Moving Average shift
//---
int ExtHandle = 0;
bool ExtHedging = false;
Transaction transaction;

#define MA_MAGIC 1234501
//+------------------------------------------------------------------+
//| Check for open position conditions                               |
//+------------------------------------------------------------------+
void CheckForTrade(void)
{
    /* MqlRates:価格、ボリュームとスプレッドの情報を提供
    struct MqlRates
     {
      datetime time;         // 期間開始時間
      double   open;         // 始値
      double   high;         // 期間中の最高値
      double   low;         // 期間中の最安値
      double   close;       // 終値
      long     tick_volume; // ティックボリューム
      int     spread;       // スプレッド
      long     real_volume; // 取引高
     };
    */
    MqlRates rt[2];
    //--- go trading only for first ticks of new bar
    /*
    CopyRates:指定された銘柄と期間の MqlRates 構造体の指定された量の履歴データを rates_array 配列に配置します。 要素は現在から過去の順に並べられ、インデックス0が現在足です。
    1 番目の位置と必要な要素数によっての呼び出し
    int  CopyRates(
      string          symbol_name,      // 銘柄名
      ENUM_TIMEFRAMES  timeframe,        // 期間
      int              start_pos,        // 開始位置
      int              count,            // 複製するデータ数
      MqlRates         rates_array[]      // 受け取り側の配列
      );
    */
    if (CopyRates(_Symbol, _Period, 0, 2, rt) != 2)
    {
        Print("CopyRates of ", _Symbol, " failed, no history"); // 2本分取得できないとエラー
        return;
    }
    if (rt[1].tick_volume > 1) // 現在のロウソク足の最初のティックの時のみ、以下の処理に進む
        return;
    //--- get current Moving Average
    double ma[1];

    if (CopyBuffer(ExtHandle, 0, 0, 1, ma) != 1)
    {
        Print("CopyBuffer from iMA failed, no data");
        return;
    }
    //--- check signals

    if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && Bars(_Symbol, _Period) > 100)
    {
        if (rt[0].open > ma[0] && rt[0].close < ma[0])      // 1つ前のロウソク足の始値の方がMAの値より大きく、かつ(&&)、1つ前のロウソク足の終値の方がMAの値より小さい場合(上から下に抜けた)に ORDER_TYPE_SELL
            transaction.Sell();                             // sell conditions
        else if (rt[0].open < ma[0] && rt[0].close > ma[0]) // 1つ前のロウソク足の始値の方がMAの値より小さく、かつ(&&)、1つ前のロウソク足の終値の方がMAの値より大きい場合(下から上に抜けた)に ORDER_TYPE_SELL
            transaction.Buy();                              // buy conditions
    }
}
//+------------------------------------------------------------------+
//| Check for close position conditions                              |
//+------------------------------------------------------------------+
int OnInit(void)
// EAがセットされた時（初期化時）に一度だけ実行される関数
{
    transaction.Initialize(MA_MAGIC, MaximumRisk, DecreaseFactor);
    //--- Moving Average indicator
    ExtHandle = iMA(_Symbol, _Period, MovingPeriod, MovingShift, MODE_SMA, PRICE_CLOSE); // EAがセットされているチャートの銘柄・時間足の、 MovingPeriod期間 の MovingShift期間シフトさせた SMA を扱うハンドル
    if (ExtHandle == INVALID_HANDLE)
    {
        printf("Error creating MA indicator");
        return (INIT_FAILED);
    }
    //--- ok
    return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(void)
{
    CheckForTrade();
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}
//+------------------------------------------------------------------+
