# Troubleshooting Guide

## Common Issues

### ❌ "Broken Pipe" Error

**Problem**: You get `ERROR: [Errno 32] Broken pipe` when downloading.

**Causes**:
1. **Long videos** - Downloading very long videos (hours) takes time
2. **Large search** - Searching for 20+ results can timeout
3. **Network issues** - Connection interrupted during download

**Solutions**:

#### 1. Filter by Duration (RECOMMENDED)

Many music genres return **long livestreams** (6+ hours). Use duration filters:

```bash
# Search for short tracks only (3-10 minutes = 180-600 seconds)
./ytdl search "lofi beats" 10 | grep -E "Duration: [0-9]:[0-9]{2}"

# Or in Elixir:
YoutubeAudioDl.Search.search("lofi", min_duration: 180, max_duration: 600, limit: 10)
```

#### 2. Start Small

```bash
# Instead of:
./ytdl download lofi --count 20  # ❌ May timeout

# Do this:
./ytdl download lofi --count 5   # ✅ Faster
```

#### 3. Use Specific Index

Download specific shorter videos:

```bash
# Browse first
./ytdl browse lofi 10

# Pick a short one (check duration)
./ytdl download lofi --index 5  # Download 5th result
```

### ⏳ Downloads Taking Forever

**Problem**: Downloads hang or take very long.

**Check Video Duration First**:

```bash
# Browse and check durations
./ytdl browse lofi 5

# Look for duration in output:
# Duration: 6:10:58  <- This is 6+ hours! ❌
# Duration: 3:45     <- This is 3 minutes ✅
```

**Solution**: Avoid long livestreams

```elixir
# Filter for reasonable lengths (under 30 minutes)
YoutubeAudioDl.Music.search(:lofi, limit: 10)
|> then(fn {:ok, videos} ->
  Enum.filter(videos, fn v -> v.duration && v.duration < 1800 end)
end)
```

### 📦 Unused Variable Warning

**Problem**: Warning about `mean` variable in transient_detector.ex

**Status**: Fixed in latest version. Run `mix compile` to clear.

## Best Practices

### ✅ DO:

1. **Use duration filters** for music searches
   ```elixir
   # Get 3-15 minute videos
   YoutubeAudioDl.Search.search("jazz", min_duration: 180, max_duration: 900)
   ```

2. **Start with small batches**
   ```bash
   ./ytdl download jazz --count 3  # Test first
   ```

3. **Browse before downloading**
   ```bash
   ./ytdl browse classical 10  # Check what's available
   ./ytdl download classical --index 3  # Download specific one
   ```

4. **Use cache** - Second downloads are instant
   ```bash
   ./ytdl download lofi  # Downloads
   ./ytdl download lofi  # Skips (cached) ✓
   ```

### ❌ DON'T:

1. **Download without checking duration**
   - Many lofi/ambient results are 24-hour livestreams!

2. **Request 20+ tracks at once** (first time)
   - Search takes longer
   - More likely to timeout
   - Start with 5-10

3. **Download livestreams** (duration: N/A or >1 hour)
   - They're huge
   - Take forever
   - Usually not what you want

## Recommended Workflows

### Download Short Tracks Only

```bash
# 1. Search with duration filter
mix run -e '
{:ok, short_tracks} = YoutubeAudioDl.Search.search("lofi beats",
  min_duration: 120,   # 2 min
  max_duration: 600,   # 10 min
  limit: 10
)

# 2. Download them
Enum.each(short_tracks, fn track ->
  YoutubeAudioDl.download_audio(track.url, category: "lofi_short")
end)
'
```

### Build Curated Playlist

```bash
# 1. Browse and note durations
./ytdl browse jazz 20

# 2. Download specific good ones
./ytdl download jazz --index 3
./ytdl download jazz --index 7
./ytdl download jazz --index 12
```

### Batch Download (Safe)

```bash
# Download in small batches
for i in {1..4}; do
  ./ytdl download classical --count 5
  sleep 2
done
```

## Performance Tips

### Cache Management

```bash
# Check what's cached
./ytdl cache

# Clear specific genre if needed
./ytdl clear lofi

# Fresh start
rm -rf downloads/.cache/
```

### Search Limits

- **5-10 results**: Fast, recommended
- **11-20 results**: Slower but works
- **20+ results**: May timeout, use batches

### Duration Sweet Spots

| Genre | Recommended Duration Range |
|-------|---------------------------|
| Lofi/Ambient | 3-15 minutes (180-900s) |
| Jazz/Classical | 3-30 minutes (180-1800s) |
| Rock/Pop | 2-10 minutes (120-600s) |
| Tutorials | 5-20 minutes (300-1200s) |

## Error Messages Explained

### "Broken pipe"
- yt-dlp process interrupted
- Usually from timeout or network issue
- **Fix**: Use smaller batches or duration filters

### "Already downloaded (cached)"
- Not an error! Feature working correctly
- Use `--force` to re-download if needed

### Compilation warnings
- Usually safe to ignore
- Fixed in latest version

## Still Having Issues?

1. **Check network**: `ping youtube.com`
2. **Update yt-dlp**: `~/.local/bin/uv tool install yt-dlp --force`
3. **Try direct URL**: `./ytdl get "https://youtube.com/watch?v=..."`
4. **Check cache**: `./ytdl cache` (maybe it's working!)

## Quick Reference

```bash
# Safe starter commands
./ytdl browse lofi 5              # Browse 5 results
./ytdl download lofi --index 2    # Download 2nd result
./ytdl download jazz --count 3    # Download 3 tracks
./ytdl cache                      # Check stats
./ytdl clear lofi                 # Clear cache
```

**Pro Tip**: Always check duration before mass downloads!
