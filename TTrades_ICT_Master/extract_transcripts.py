import subprocess
import json
import os

videos = [
    ("Vo2n47RjjMo", "Intracandle CISD (IC-CISD)"),
    ("-ocfPuD_oqE", "How To Use SMT Divergence"),
    ("A4NasIa371c", "How to Set Price Targets"),
    ("v1X8UMWgWmI", "Best Trading Strategy 2026 - TTFM"),
    ("_CSO5Mf7CM8", "Weekly Profile - TGIF Setup"),
    ("uPUNOi_R9fA", "Weekly Profile - Thursday Counter"),
    ("FvOUvQ7odiw", "Weekly Profile - Intraweek Reversal"),
    ("McJflkKuvrI", "Weekly Profile - Consolidation Reversal"),
    ("-gyDd_E_qD4", "Weekly Profile - Midweek Reversal"),
    ("Qt7Ek4keMzs", "Weekly Profile - Classic Expansion"),
    ("jKuXaC84Qx4", "Trading Invalidation of Daily Bias"),
    ("HbOeD_JVens", "Swing Highs and Lows Matter"),
    ("nWHint4Yano", "EURGBP for Relative Strength"),
    ("HrjYoxAUb3s", "Currency Futures for Forex"),
    ("yH4eYwUgdTY", "Relative Strength & SMT Guide"),
    ("9BY-MQRNy-Y", "TTrades Swing Trading Model"),
    ("PQiRV0JMhIQ", "Why Continuations Fail - CISD"),
    ("eywpZT3z6GQ", "TTrades Scalping Model"),
    ("FgP2lc9nneM", "Timeframe for Fractal Model"),
    ("oSrXv92fIzc", "Candle 2 Closures - Fractal Concept")
]

os.makedirs("transcripts", exist_ok=True)

for video_id, title in videos:
    print(f"Processing: {title} ({video_id})")
    cmd = [
        "yt-dlp",
        "--write-auto-subs",
        "--skip-download",
        "--sub-langs", "en",
        "--output", f"transcripts/{video_id}.%(ext)s",
        f"https://www.youtube.com/watch?v={video_id}"
    ]
    subprocess.run(cmd)

print("Extraction Complete.")
