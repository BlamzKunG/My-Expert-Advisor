# 📈 TTrades ICT Model: The Ultimate MQL5 EA Master Blueprint (v2.0 - 100 Video Synthesis)

This expanded blueprint synthesizes the advanced concepts extracted from the top 100 videos of the TTrades_edu channel. It transforms basic ICT entries into a **Comprehensive Algorithmic Framework**, introducing Power of 3 (AMD), Market Maker Models (MMXM), advanced PD Arrays (Unicorn, IFVG), and vital "Seek & Destroy" logic to prevent EA blowouts.

---

## 🏗️ 1. Architecture & Core Variables

To support advanced logic, the EA must track states across three distinct timeframes and monitor daily candle phases.

```mql5
//--- MTF & State Inputs
input ENUM_TIMEFRAMES HTF_Bias   = PERIOD_D1;  // Daily Bias & Daily PO3
input ENUM_TIMEFRAMES ITF_Curve  = PERIOD_H1;  // MMXM Curve & Liquidity Pools
input ENUM_TIMEFRAMES LTF_Entry  = PERIOD_M5;  // Entry Execution (Unicorn, CISD)

//--- Risk Management Enums
enum ENUM_DAILY_PROFILE {
    PROFILE_EXPANSION,
    PROFILE_REVERSAL,
    PROFILE_CONSOLIDATION,
    PROFILE_SEEK_AND_DESTROY
};
```

---

## 🧠 2. Macro Context: Power of 3 (PO3) & Daily Profiles
*Derived from: 4 Hour Power of Three (OHLC), Daily Profiles, Phases of Price*

Before the EA executes, it must identify the current "Phase of Price".
The **Power of 3 (AMD)** dictates that a bullish day opens, manipulates lower (Accumulation/Manipulation), and expands higher (Distribution).

**The "Seek & Destroy" Filter (CRITICAL):**
If the market is in a broadening formation or chopping both sides of the Asian Range without a clear draw on liquidity, the EA **MUST HALT**.

```mql5
// MQL5 Logic: Detecting AMD Phase & Seek & Destroy
ENUM_DAILY_PROFILE DetermineDailyProfile() {
    double asianHigh = GetAsianRangeHigh();
    double asianLow  = GetAsianRangeLow();
    
    bool sweptHigh = HasPriceSwept(asianHigh);
    bool sweptLow  = HasPriceSwept(asianLow);
    
    // If it sweeps BOTH sides and returns to the middle -> Seek & Destroy (DO NOT TRADE)
    if(sweptHigh && sweptLow && IsPriceInMiddle()) {
        return PROFILE_SEEK_AND_DESTROY;
    }
    
    // Standard PO3 (Bullish: Open -> Sweep Low -> Expand High)
    if(sweptLow && !sweptHigh && HTF_Bias == BIAS_LONG) {
        return PROFILE_EXPANSION; // Ready for long entries
    }
    
    return PROFILE_CONSOLIDATION;
}
```

---

## 🗺️ 3. Market Maker Models (MMXM) & The Curve
*Derived from: Advanced ICT MMXM Lesson, High vs Low Resistance Liquidity*

The EA must map where it is on the "Curve".
*   **Original Consolidation:** The origin of the move.
*   **Sell-Side of the Curve:** Price is dropping down into an HTF Discount POI.
*   **Buy-Side of the Curve:** Price has reversed at the HTF POI and is now attacking Low Resistance Liquidity Run (LRLR) targets on the way up.

*Rule:* The EA only executes aggressive continuation entries on the **Buy-Side of the Curve** (after the Smart Money Reversal at the POI).

```mql5
bool IsOnCorrectCurveSide() {
    // If we are looking for Longs, ensure a Smart Money Reversal (SMR) has already occurred
    // at the HTF POI. Do not catch falling knives on the Sell-Side of the curve.
    bool smrConfirmed = CheckC3Closure(HTF_Bias) || CheckCISD(HTF_Bias);
    return smrConfirmed; 
}
```

---

## 🎯 4. Advanced Entry Models (The Unicorn & IFVG)
*Derived from: Unicorn Model, Inversion FVGs, Breaker Blocks*

Standard FVGs are great, but the **Unicorn Model** and **Inversion FVGs** provide the highest probability entries.

### The Unicorn Model (Breaker Block + FVG)
This occurs when an FVG aligns perfectly inside a Breaker Block. It is the strongest ICT setup.

```mql5
bool CheckUnicorn_LongEntry() {
    // 1. Identify a Bullish Breaker Block (a failed bearish order block after taking liquidity)
    double breakerTop = GetBreakerBlockTop();
    double breakerBot = GetBreakerBlockBottom();
    
    // 2. Identify an FVG overlapping the Breaker
    double fvgTop = GetFVGTop();
    double fvgBot = GetFVGBottom();
    
    bool isUnicorn = (fvgTop <= breakerTop && fvgBot >= breakerBot); // FVG is inside Breaker
    
    // 3. Entry Trigger: Price taps the Unicorn overlap
    if(isUnicorn && Ask <= fvgTop && Ask >= fvgBot) {
        return true;
    }
    return false;
}
```

### Inversion Fair Value Gaps (IFVG)
When price completely disrespects and closes through an FVG, it becomes an **Inversion FVG**. A Bearish FVG that gets broken upwards becomes support for a Long trade.

```mql5
bool CheckIFVG_LongEntry() {
    // 1. Find a recently failed Bearish FVG
    double failedBearishFVG_Top = GetFailedFVGTop();
    
    // 2. Ensure a full body closure above it (Inversion confirmed)
    if(iClose(Symbol(), LTF_Entry, 2) > failedBearishFVG_Top) {
        
        // 3. Entry Trigger: Price retraces back down to tap the top of the IFVG
        if(iLow(Symbol(), LTF_Entry, 1) <= failedBearishFVG_Top && iClose(Symbol(), LTF_Entry, 1) > failedBearishFVG_Top) {
            return true; // Retest successful
        }
    }
    return false;
}
```

---

## 🛑 5. Institutional Risk Management
*Derived from: High Resistance vs Low Resistance Liquidity*

*   **Avoid High Resistance Liquidity (HRLR):** If the target requires breaking through multiple fresh, unmitigated Order Blocks or choppy consolidation, skip the trade.
*   **Target Low Resistance Liquidity (LRLR):** Target areas where price dropped rapidly with FVGs. Price will retrace through these areas effortlessly.

```mql5
// MQL5 Logic for TP Selection
double FindInstitutionalTarget(int type) {
    if(type == BIAS_LONG) {
        // Scan for the nearest LRLR (Smooth drop with gaps, no consolidation blocks in the way)
        return GetNearestLRLR_Pool(); 
    }
}
```

---
### 💡 The Master EA Workflow Loop

1. **`OnTick()` triggers.**
2. Check `TimeHour(TimeCurrent())`. Is it a valid NY or London Killzone? If not, `return`.
3. Check `DetermineDailyProfile()`. Is it `PROFILE_SEEK_AND_DESTROY`? If yes, `return`.
4. Run `CheckWeeklyProfileBias()` to establish Daily DOL.
5. Check `IsOnCorrectCurveSide()` to ensure we aren't trading against the active MMXM leg.
6. Look for POI overlap via `CheckUnicorn_LongEntry()` or `CheckIFVG_LongEntry()`.
7. Once tapped, zoom to `LTF_Entry` and wait for `CheckCISD()` or `CheckC2C3()` confirmation.
8. Fire `OrderSend()` with SL strictly at the Breaker/IFVG invalidation point. Target LRLR.
