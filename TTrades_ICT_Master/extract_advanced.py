import subprocess
import os

advanced_videos = [
    ("FKTBkTzsmUA", "Trade Inversion Fair Value Gaps (IFVG)"),
    ("3eVxTV_7L2U", "Complete Trading Framework"),
    ("FAKWJ-1NlLE", "4 Hour Power Of Three - OHLC"),
    ("8BWkRGhuj1k", "Phases of Price Action Blueprint"),
    ("07lOxv39LdY", "Blending Fractal & Unicorn Model"),
    ("Ibw4saRtYMk", "Advanced ICT MMXM Lesson"),
    ("caaS6_Q7O78", "Next Day Model - Bias"),
    ("4WCiIyCiBrQ", "Daily Profile - Seek & Destroy"),
    ("xdzyejskSKE", "Daily Profile - New York Reversal"),
    ("wWIHS_dxbEY", "Master PO3"),
    ("FGkb_50BfT8", "High vs Low Resistance Liquidity"),
    ("75S4vwD4P1U", "Breaker Blocks Simplified"),
    ("uDJI2AbyyCs", "Inversion Fair Value Gaps (IFVG) 2")
]

os.makedirs("transcripts_adv", exist_ok=True)

for video_id, title in advanced_videos:
    print(f"Processing Advanced: {title}")
    cmd = [
        "yt-dlp",
        "--write-auto-subs",
        "--skip-download",
        "--sub-langs", "en",
        "--output", f"transcripts_adv/{video_id}.%(ext)s",
        f"https://www.youtube.com/watch?v={video_id}"
    ]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

print("Advanced Extraction Complete.")