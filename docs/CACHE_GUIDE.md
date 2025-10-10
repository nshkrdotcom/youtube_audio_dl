# Cache System Guide

The cache system prevents duplicate downloads using **separate DETS files per genre/category**.

## How It Works

### Automatic Genre-Based Caching

When you download music by genre, each genre gets its own cache file:

```elixir
# Downloads are cached per genre automatically
YoutubeAudioDl.Music.download(:lofi)
# Creates: downloads/.cache/lofi

YoutubeAudioDl.Music.download(:jazz)
# Creates: downloads/.cache/jazz

YoutubeAudioDl.Music.download(:rock)
# Creates: downloads/.cache/rock
```

### File Structure

```
downloads/
├── .cache/              # Cache directory
│   ├── lofi            # DETS file for lofi downloads
│   ├── jazz            # DETS file for jazz downloads
│   ├── rock            # DETS file for rock downloads
│   └── general         # Default category
└── *.mp3               # Your downloaded music files
```

## Benefits of Per-Genre Caching

1. **Organization** - Easy to see which genres you've downloaded
2. **Performance** - Smaller DETS files = faster lookups
3. **Flexibility** - Clear cache for specific genres without affecting others
4. **Isolation** - Same video in different genres won't conflict

## Usage Examples

### Basic Download (Auto-Caching)

```elixir
# First time - downloads the file
YoutubeAudioDl.Music.download(:lofi)
# => {:ok, "downloads/lofi_hip_hop_beats.mp3"}

# Second time - skips (cached)
YoutubeAudioDl.Music.download(:lofi)
# => {:error, :already_downloaded}
```

### Force Re-Download

```elixir
# Skip cache check and re-download
YoutubeAudioDl.Music.download(:lofi, force: true)
# => {:ok, "downloads/lofi_hip_hop_beats.mp3"}
```

### Download Multiple (Smart Caching)

```elixir
# Download 5 lofi tracks
YoutubeAudioDl.Music.download_multiple(:lofi, 5)
# First run: Downloads all 5

# Run again immediately
YoutubeAudioDl.Music.download_multiple(:lofi, 5)
# Skips all 5 (already cached)
# Output: "📊 Summary: 0 downloaded, 5 skipped (already cached)"
```

### Custom Downloads with Category

```elixir
# Direct download with custom category
url = "https://www.youtube.com/watch?v=abc123"
YoutubeAudioDl.download_audio(url, category: "my_playlist")
# Creates: downloads/.cache/my_playlist
```

## Cache Management

### Check Cache Stats

```elixir
# Stats for specific genre
YoutubeAudioDl.Cache.stats("lofi")
# => %{
#      total_downloads: 42,
#      cache_file: "downloads/.cache/lofi",
#      category: "lofi"
#    }

# Aggregate stats across all genres
YoutubeAudioDl.Cache.all_stats()
# => %{
#      total_categories: 5,
#      total_downloads: 150,
#      categories: [
#        %{category: "lofi", total_downloads: 42},
#        %{category: "jazz", total_downloads: 35},
#        ...
#      ]
#    }
```

### List All Categories

```elixir
# See what genres you've downloaded
YoutubeAudioDl.Cache.list_categories()
# => ["general", "jazz", "lofi", "rock"]
```

### View Cached URLs

```elixir
# See all URLs cached for a genre
YoutubeAudioDl.Cache.list_all("lofi")
# => [
#      %{url: "https://...", downloaded_at: 1696867200, category: "lofi"},
#      ...
#    ]
```

### Clear Cache

```elixir
# Clear cache for specific genre
YoutubeAudioDl.Cache.clear_all("lofi")

# Remove specific URL from cache
YoutubeAudioDl.Cache.remove("https://youtube.com/watch?v=abc", "lofi")
```

### Manual Cache Operations

```elixir
# Check if URL is cached in a genre
YoutubeAudioDl.Cache.downloaded?("https://...", "lofi")
# => true/false

# Manually mark as downloaded
YoutubeAudioDl.Cache.mark_downloaded("https://...", "jazz")

# Get info about cached URL
YoutubeAudioDl.Cache.get_info("https://...", "lofi")
# => {:ok, %{url: "...", downloaded_at: 1696867200, category: "lofi"}}
```

## Command Line Usage

```bash
# Download with caching (per genre)
mix run -e 'YoutubeAudioDl.Music.download(:lofi)'

# Force re-download
mix run -e 'YoutubeAudioDl.Music.download(:lofi, force: true)'

# Check cache stats
mix run -e 'IO.inspect(YoutubeAudioDl.Cache.all_stats())'

# Clear lofi cache
mix run -e 'YoutubeAudioDl.Cache.clear_all("lofi")'

# List all categories
mix run -e 'IO.inspect(YoutubeAudioDl.Cache.list_categories())'
```

## Technical Details

### DETS Files

- **Technology**: Erlang's DETS (Disk-based Erlang Term Storage)
- **Type**: Key-value store on disk
- **Max size**: 2GB per file (way more than you'll need)
- **Structure**: `{url, timestamp}` tuples
- **Persistence**: Automatic, survives restarts

### Performance

- **Lookup speed**: O(log n) for most operations
- **File size**: ~6KB per file with minimal entries
- **Concurrent access**: Single writer, multiple readers
- **Memory footprint**: Minimal (only active tables stay in memory)

### Isolation

Each genre's cache is completely isolated:

```elixir
# Same URL in different genres = different cache entries
YoutubeAudioDl.download_audio(url, category: "lofi")   # Cached in lofi
YoutubeAudioDl.download_audio(url, category: "jazz")   # NOT cached in jazz
```

## Workflow Examples

### Build a Music Library

```elixir
# Download from multiple genres
genres = [:lofi, :jazz, :classical, :ambient]

Enum.each(genres, fn genre ->
  YoutubeAudioDl.Music.download_multiple(genre, 10)
end)

# Check what you've downloaded
YoutubeAudioDl.Cache.all_stats()
```

### Incremental Downloads

```elixir
# Download 5 lofi tracks today
YoutubeAudioDl.Music.download_multiple(:lofi, 5)

# Download 5 more tomorrow (gets next 5, skips first 5)
YoutubeAudioDl.Music.download_multiple(:lofi, 10)
# Will skip first 5, download next 5
```

### Fresh Start for a Genre

```elixir
# Clear lofi cache to start fresh
YoutubeAudioDl.Cache.clear_all("lofi")

# Now can re-download everything
YoutubeAudioDl.Music.download_multiple(:lofi, 10)
```

## Troubleshooting

### Cache not preventing duplicates?

Check if you're using the correct category:

```elixir
# These use DIFFERENT caches
YoutubeAudioDl.download_audio(url, category: "lofi")
YoutubeAudioDl.download_audio(url, category: "jazz")
```

### Want to see what's cached?

```elixir
# List all cached URLs for a genre
YoutubeAudioDl.Cache.list_all("lofi")
```

### Need to reset everything?

```bash
# Remove all cache files
rm -rf downloads/.cache/
```

Or in Elixir:

```elixir
# Clear each category
YoutubeAudioDl.Cache.list_categories()
|> Enum.each(&YoutubeAudioDl.Cache.clear_all/1)
```

## Notes

- Cache is stored in `downloads/.cache/` directory
- Each genre/category gets its own DETS file
- Files are created automatically on first use
- No manual initialization needed - it's automatic!
- Safe to delete cache files if you want a fresh start
