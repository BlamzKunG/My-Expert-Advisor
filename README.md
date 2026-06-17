# My Expert Advisor (EA) Collection

Welcome to my personal repository for Algorithmic Trading and Expert Advisors (EAs). This repository serves as a centralized hub for various automated trading systems, custom indicators, and quantitative research models primarily built in MQL4 and MQL5 for MetaTrader.

## Repository Structure

To maintain organization and modularity, each Expert Advisor or trading system is contained within its own dedicated directory. Each directory includes its respective source code, blueprints, and documentation.

### 📂 Current Projects:

*   **[`TTrades_ICT_Master/`](TTrades_ICT_Master/)**
    *   **Type:** MQL5 Expert Advisor
    *   **Description:** An advanced, highly parameterized algorithmic framework based on ICT (Inner Circle Trader) concepts. It synthesizes over 100 strategic video transcripts to implement mechanics like Intracandle CISD, Candle 2/3 Closures, Inversion FVGs, the Unicorn Model, and "Seek & Destroy" daily profile filters. Features built-in algorithmic scanning for automated execution.
    *   **Documentation:** See the [EA Blueprint](TTrades_ICT_Master/TTrades_EA_Blueprint.md) inside the folder for the complete architectural breakdown.

*(More EAs will be added to this repository over time.)*

## Development Philosophy

*   **Flexibility:** Systems are built with highly parameterized inputs to allow deep optimization of timeframes, session hours (Killzones), and entry logic toggles.
*   **Modularity:** Clean state-machine architectures separating Bias, Validation, Entry, and Execution.
*   **Function over Form:** Prioritizing robust algorithmic scanning and execution logic over manual chart interaction.

## License

This repository is licensed under the **MIT License**.

You are free to use, modify, distribute, and integrate this code into your own projects (including commercial projects) as long as the original copyright notice and permission notice are included. 

See the [LICENSE](LICENSE) file for complete details.
