//+------------------------------------------------------------------+
//|                                                  Transaction.mqh |
//|                                     Copyright 2023, Shuta Shibue |
//|                                       Link inMQLHeadStandard |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Shuta Shibue"
#property link "Link"
#property version "1.00"

#include <Trade\Trade.mqh>

class Transaction
{
protected:
    ulong Magic;
    double MaximumRisk;
    double DecreaseFactor;
    CTrade ExtTrade; // CTrade:取引関数に簡単にアクセスするためのクラス
    bool ExtHedging;

public:
    void Transaction::Buy();
    void Transaction::Sell();
    void Transaction::Initialize(ulong _Magic, double _MaximumRisk, double _DecreaseFactor);

private:
    bool Transaction::SelectPosition();
    double Transaction::TradeSizeOptimized(void);
};

//+------------------------------------------------------------------+
//| Constructor(s):                                                  |
//+------------------------------------------------------------------+
void Transaction::Initialize(ulong _Magic, double _MaximumRisk, double _DecreaseFactor)
{
    MaximumRisk = _MaximumRisk;
    DecreaseFactor = _DecreaseFactor;
    Magic = _Magic;
    ExtTrade.SetExpertMagicNumber(Magic);      // ExtTrade に対してマジックナンバーを設定
    ExtTrade.SetMarginMode();                  // ExtTrade に対して証拠金モードを設定
    ExtTrade.SetTypeFillingBySymbol(Symbol()); // ExtTrade に対して指定された銘柄の設定によって注文の履行タイプを設定
    ExtHedging = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

void Transaction::Buy()
{
    if (SelectPosition())
        ExtTrade.PositionClose(_Symbol, 3);
    else
        ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, TradeSizeOptimized(),
                              SymbolInfoDouble(_Symbol, SYMBOL_ASK), // ORDER_TYPE_BUY:現在のAsk価格
                              0, 0);
}

void Transaction::Sell()
{
    if (SelectPosition())
        ExtTrade.PositionClose(_Symbol, 3);
    else
        ExtTrade.PositionOpen(_Symbol, ORDER_TYPE_BUY, TradeSizeOptimized(),
                              SymbolInfoDouble(_Symbol, SYMBOL_BID), // ORDER_TYPE_SELL:現在のBid価格
                              0, 0);
}

bool Transaction::SelectPosition()
{
    // 保有ポジション一覧からこのEAでエントリーしたポジションを探し、見つかれば true を返す
    bool res = false;
    //--- check position in Hedging mode
    if (ExtHedging) // 複数ポジションを持てるか
    {
        uint total = PositionsTotal(); // 現在保有中のポジションの数（未決済ポジション数）を取得
        for (uint i = 0; i < total; i++)
        {
            string position_symbol = PositionGetSymbol(i);
            if (_Symbol == position_symbol && Magic == PositionGetInteger(POSITION_MAGIC))
            {
                res = true;
                break;
            }
        }
    }
    //--- check position in Netting mode
    else
    {
        if (!PositionSelect(_Symbol))
            return (false);
        else
            return (PositionGetInteger(POSITION_MAGIC) == Magic); //---check Magic number
    }
    //--- result for Hedging mode
    return (res);
}

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double Transaction::TradeSizeOptimized(void)
{
    double price = 0.0;
    double margin = 0.0;
    //--- select lot size
    // price にこのEAをセットしているチャートの銘柄の価格(ask)を代入する
    // 失敗するとreturn
    if (!SymbolInfoDouble(_Symbol, SYMBOL_ASK, price))
        return (0.0);
    // このEAをセットしているチャートの通貨ペアでprice価格で1ロットのロングエントリーをする時に必要な証拠金を計算し、その金額を margin に代入する
    if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin))
        return (0.0);
    if (margin <= 0.0)
        return (0.0);

    // AccountInfoDouble(ACCOUNT_MARGIN_FREE) は余剰証拠金を返す
    // 「剰証拠金×MaximumRisk÷margin」の計算結果を小数点以下2桁で丸める→最大リスクロット数
    double lot = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * MaximumRisk / margin, 2);
    //--- calculate number of losses orders without a break
    if (DecreaseFactor > 0)
    {
        //--- select history for access
        HistorySelect(0, TimeCurrent()); // 注文と取引の履歴を取得
        //---
        int orders = HistoryDealsTotal(); // total history deals 約定履歴の数を取得
        int losses = 0;                   // number of losses orders without a break

        for (int i = orders - 1; i >= 0; i--)
        {
            ulong ticket = HistoryDealGetTicket(i); // 指定したインデックス（約定履歴内での番号、0,1,2...の様に0から順に付与）の約定履歴からその約定チケット(ID)を取得
            if (ticket == 0)
            {
                Print("HistoryDealGetTicket failed, no trade history");
                break;
            }
            //--- check symbol
            if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) // ticket の銘柄（通貨ペア）を返し、 現在のチャートの銘柄(_Symbol)と異なれば以下の処理をスキップする
                continue;
            //--- check Expert Magic number
            if (HistoryDealGetInteger(ticket, DEAL_MAGIC) != Magic) // ticket のマジックナンバー(エントリー時にその取引に紐づける事のできる任意の数値)を取得し、このEAと比較
                continue;
            //--- check profit
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT); // その約定履歴の利益を取得
            if (profit > 0.0)
                break;
            if (profit < 0.0)
                losses++; // 直近からの連敗数
        }
        //---
        if (losses > 1)
            lot = NormalizeDouble(lot - lot * losses / DecreaseFactor, 1); // DecreaseFactor=3の場合、3連敗でlotが0になる
    }
    //--- normalize and check limits
    double stepvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); // 証券会社のロットの最小単位を取得し、最小単位以下の端数を丸める
    lot = stepvol * NormalizeDouble(lot / stepvol, 0);

    double minvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN); // 証券会社の最小ロット数を取得し、上で算出したロット数が最小ロット数以下だった場合は最小ロットをロット数として設定
    if (lot < minvol)
        lot = minvol;

    double maxvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); // 証券会社の最大ロット数を上限とする
    if (lot > maxvol)
        lot = maxvol;
    //--- return trading volume
    return (lot);
}
//+------------------------------------------------------------------+