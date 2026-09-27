# Re-shooting the demo

The 54 second Origin Weekend demo is three beats, per the Chewbacca demo skill's
one-to-three-features rule: a request typed in plain words and built live, Ruth
adding a prayer from her phone, and it landing on the owner's screen.

1. Create a demo owner and circle on production, and write the owner key to
   `/tmp/demo.key` (see `make.py` for the circle it expects).
2. `nice -n 19 python3 make.py` records the build. It makes a real, paid build.
3. Seed two prayers from other members, then `nice -n 19 python3 share.py`.
4. Assemble with ffmpeg: the build is sped up 8x between 10s and 58.5s, the
   laptop and phone clips are stacked side by side, and `endcard.html` closes it.

Generated tools differ between builds: the prayer box was `#newPrayer` in one build and `#text` in the next, and one listed newest first while the other listed oldest first. Read the new tool's source (`get_tool_source` over MCP) before recording, and wait for the added entry to appear on the owner's screen before scrolling to it, because the owner's view picks it up on a 4 second poll.

In zsh, write `${G}[v]` rather than `$G[v]` inside an ffmpeg filter string, and
never keep flags in a variable: zsh does not word-split, and both cost a render.
