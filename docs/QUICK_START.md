# Quick Start Guide

## Installation Complete! Now What?

### 1. Test the System

```bash
# See all available genres (104 total!)
./ytdl genres

# Browse lofi music (check durations first)
./ytdl browse lofi 5
```

### 2. Download Your First Track

**IMPORTANT**: Many search results are LONG (6+ hours). Check duration first!

```bash
# Browse and pick a SHORT one
./ytdl browse lofi 10

# Download a specific short track (example: 4th result if it's short)
./ytdl download lofi --index 4
```

### 3. Recommended: Use Duration Filters

```elixir
# In iex -S mix
# Get only 3-10 minute tracks
{:ok, tracks} = YoutubeAudioDl.Search.search("lofi beats", 
  min_duration: 180, 
  max_duration: 600,
  limit: 5
)

# Download first one
track = List.first(tracks)
YoutubeAudioDl.download_audio(track.url, category: "lofi")
```

## Simple Examples

### Browse Genres

```bash
./ytdl browse jazz 5
./ytdl browse classical 10  
./ytdl browse synthwave 5
```

### Download Single Track

```bash
# Browse first, then download by index
./ytdl browse rock 10
./ytdl download rock --index 3
```

### Download from URL

```bash
./ytdl get "https://www.youtube.com/watch?v=VIDEO_ID"
```

### Check Cache

```bash
./ytdl cache  # See what's downloaded
```

## Avoiding "Broken Pipe" Errors

✅ **DO THIS**:
- Browse first, check durations
- Download one at a time initially
- Use `--count 3` for small batches
- Filter by duration (3-10 min recommended)

❌ **AVOID**:
- Downloading 6+ hour livestreams
- Using `--count 20` without filtering
- Not checking durations first

## Example Session

```bash
# 1. Browse jazz (check durations)
$ ./ytdl browse jazz 10

# Output shows:
# 3. Smooth Jazz Mix
#    Duration: 5:32 | Views: 2.1M  <- Good! Short track
# 5. Jazz Radio - 24/7 Live
#    Duration: N/A | Views: 50M   <- Bad! Livestream

# 2. Download the short one (index 3)
$ ./ytdl download jazz --index 3

# 3. Check it cached properly
$ ./ytdl cache
```

## More Examples in Documentation

- See `MUSIC_EXAMPLES.md` for genre API usage
- See `CACHE_GUIDE.md` for cache management
- See `TROUBLESHOOTING.md` if issues arise

## Pro Tips

1. **Always browse first** - Check durations!
2. **Start small** - Download 1-3 tracks to test
3. **Use cache** - Second download instant (skipped)
4. **Filter duration** - Avoid livestreams
5. **Check stats** - `./ytdl cache` shows progress

Happy downloading! 🎵
