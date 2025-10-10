# Music Discovery & Search Examples

This guide demonstrates how to use the new music discovery features.

## Quick Start

```elixir
# Start IEx with the project
$ iex -S mix

# Browse lofi music
iex> YoutubeAudioDl.Music.browse(:lofi)

# Search and download first result
iex> YoutubeAudioDl.Music.download(:jazz)

# Search custom query
iex> YoutubeAudioDl.Search.search("best piano music")
```

## Music Module - Simple Genre-Based Interface

### 1. List All Available Genres

```elixir
# See all 104 genres organized by category
YoutubeAudioDl.Music.print_genres()

# Get genre list as atoms
YoutubeAudioDl.Music.list_genres()
# => [:acoustic, :afrobeat, :african, :ambient, ...]
```

### 2. Browse Music by Genre

```elixir
# Browse lofi hip hop (default 5 results)
YoutubeAudioDl.Music.browse(:lofi)

# Browse 10 jazz tracks
YoutubeAudioDl.Music.browse(:jazz, limit: 10)

# Browse synthwave
YoutubeAudioDl.Music.browse(:synthwave)
```

### 3. Search by Genre (Get Metadata)

```elixir
# Search returns full metadata
{:ok, results} = YoutubeAudioDl.Music.search(:lofi, limit: 3)

# Access metadata
[first | _rest] = results
first.title        # => "lofi hip hop radio 📚"
first.url          # => "https://www.youtube.com/watch?v=..."
first.duration     # => 3600 (in seconds)
first.view_count   # => 49000000
first.channel      # => "Lofi Girl"
```

### 4. Get Just URLs

```elixir
# Get only URLs for a genre
{:ok, urls} = YoutubeAudioDl.Music.search_urls(:jazz, limit: 5)
# => ["https://www.youtube.com/watch?v=...", ...]

# Use with existing download function
[first_url | _] = urls
YoutubeAudioDl.download_audio(first_url)
```

### 5. Download by Genre

```elixir
# Download the first result for a genre
YoutubeAudioDl.Music.download(:lofi)
# => {:ok, "downloads/lofi_hip_hop_radio.mp3"}

# Download the 3rd result
YoutubeAudioDl.Music.download(:jazz, index: 3)

# Download to custom directory
YoutubeAudioDl.Music.download(:classical, output_dir: "./classical_music")
```

### 6. Download Multiple Tracks

```elixir
# Download 5 lofi tracks
YoutubeAudioDl.Music.download_multiple(:lofi, 5)

# Download 3 jazz tracks to custom directory
YoutubeAudioDl.Music.download_multiple(:jazz, 3, output_dir: "./jazz_collection")
```

## Search Module - Custom Queries

### 1. Basic Search

```elixir
# Search for anything
{:ok, results} = YoutubeAudioDl.Search.search("dark ambient music")

# Control number of results
{:ok, results} = YoutubeAudioDl.Search.search("piano covers", limit: 10)
```

### 2. Get URLs Only

```elixir
# Get just the URLs
{:ok, urls} = YoutubeAudioDl.Search.search_urls("best of beethoven", limit: 5)
```

### 3. Display Formatted Results

```elixir
# Search and display nicely
{:ok, results} = YoutubeAudioDl.Search.search("ambient study music")
YoutubeAudioDl.Search.print_results(results)
```

### 4. Access Detailed Metadata

```elixir
{:ok, [video | _]} = YoutubeAudioDl.Search.search("epic orchestral music")

# Available metadata fields:
video.url              # YouTube URL
video.id               # Video ID
video.title            # Video title
video.duration         # Duration in seconds
video.view_count       # View count
video.upload_date      # Upload date (YYYYMMDD format)
video.channel          # Channel name
video.channel_id       # Channel ID
video.description      # Full description
video.thumbnail        # Thumbnail URL
video.like_count       # Likes
video.comment_count    # Comments
video.tags             # List of tags
video.categories       # List of categories
```

### 5. Format Helpers

```elixir
# Format duration nicely
YoutubeAudioDl.Search.format_duration(3665)
# => "1:01:05"

# Format view counts
YoutubeAudioDl.Search.format_views(1234567)
# => "1.2M views"
```

## Popular Genre Examples

### Electronic & Chill

```elixir
# Lofi hip hop for studying
YoutubeAudioDl.Music.download(:lofi)

# Ambient music for relaxation
YoutubeAudioDl.Music.download(:ambient)

# Synthwave/retrowave
YoutubeAudioDl.Music.download(:synthwave)

# Chillwave
YoutubeAudioDl.Music.download(:chillwave)
```

### Classical & Instrumental

```elixir
# Classical music
YoutubeAudioDl.Music.download(:classical)

# Piano music
YoutubeAudioDl.Music.download(:piano)

# Baroque era
YoutubeAudioDl.Music.download(:baroque)

# Jazz
YoutubeAudioDl.Music.download(:jazz)
```

### Rock & Metal

```elixir
# Classic rock
YoutubeAudioDl.Music.download(:classic_rock)

# Heavy metal
YoutubeAudioDl.Music.download(:heavy_metal)

# Progressive rock
YoutubeAudioDl.Music.download(:progressive_rock)
```

### World Music

```elixir
# Bossa nova
YoutubeAudioDl.Music.download(:bossa_nova)

# Reggae
YoutubeAudioDl.Music.download(:reggae)

# Flamenco guitar
YoutubeAudioDl.Music.download(:flamenco)

# Indian classical
YoutubeAudioDl.Music.download(:indian_classical)
```

### Focus & Relaxation

```elixir
# Study music
YoutubeAudioDl.Music.download(:study)

# Meditation
YoutubeAudioDl.Music.download(:meditation)

# Sleep music
YoutubeAudioDl.Music.download(:sleep)

# Nature sounds
YoutubeAudioDl.Music.download(:nature_sounds)
```

## Command Line Examples

```bash
# Browse genres
mix run -e 'YoutubeAudioDl.Music.print_genres()'

# Browse lofi music
mix run -e 'YoutubeAudioDl.Music.browse(:lofi, limit: 5)'

# Download jazz
mix run -e 'YoutubeAudioDl.Music.download(:jazz)'

# Custom search
mix run -e 'results = YoutubeAudioDl.Search.search("epic music"); YoutubeAudioDl.Search.print_results(elem(results, 1))'

# Download multiple tracks
mix run -e 'YoutubeAudioDl.Music.download_multiple(:lofi, 3)'
```

## Workflow Examples

### Create a Genre Playlist

```elixir
# Download a curated collection
genres = [:lofi, :jazz, :classical, :ambient]

Enum.each(genres, fn genre ->
  IO.puts("\\nDownloading from genre: #{genre}")
  YoutubeAudioDl.Music.download(genre)
end)
```

### Build a Study Music Collection

```elixir
# Download 3 tracks from study-friendly genres
study_genres = [:lofi, :classical, :piano, :ambient, :study]

Enum.each(study_genres, fn genre ->
  YoutubeAudioDl.Music.download_multiple(genre, 3, output_dir: "./study_music")
end)
```

### Browse Before Downloading

```elixir
# 1. Browse to see what's available
{:ok, results} = YoutubeAudioDl.Music.browse(:synthwave, limit: 10)

# 2. Pick a specific one (e.g., the 4th result)
YoutubeAudioDl.Music.download(:synthwave, index: 4)
```

### Custom Search and Download

```elixir
# Search for something specific
{:ok, videos} = YoutubeAudioDl.Search.search("dark jazz noir", limit: 5)

# Display results
YoutubeAudioDl.Search.print_results(videos)

# Download the one you want
video = Enum.at(videos, 2)  # 3rd result
YoutubeAudioDl.download_audio(video.url)
```

## Tips

1. **Browse First**: Use `browse/2` to see what's available before downloading
2. **Custom Queries**: Use `Search.search/2` for specific searches beyond genre presets
3. **Metadata**: All search functions return full metadata, not just URLs
4. **Batch Downloads**: Use `download_multiple/3` for creating collections
5. **Organized Files**: Downloaded files are automatically sanitized and organized

## Full Genre List (104 genres)

- **Electronic**: lofi, edm, techno, house, trance, dubstep, drum_and_bass, chillwave, synthwave, vaporwave, ambient, downtempo
- **Hip Hop**: hip_hop, rap, trap, boom_bap, underground_hip_hop, old_school_hip_hop
- **Jazz**: jazz, smooth_jazz, jazz_fusion, bebop, cool_jazz
- **Blues**: blues, delta_blues, chicago_blues
- **Rock**: rock, classic_rock, alternative_rock, indie_rock, punk_rock, hard_rock, progressive_rock
- **Metal**: metal, heavy_metal, death_metal, black_metal, doom_metal, thrash_metal, power_metal
- **Classical**: classical, baroque, romantic, contemporary_classical, piano, violin, orchestra, chamber_music, opera
- **Folk**: folk, acoustic, bluegrass, country, celtic, irish_folk, americana
- **World**: world, reggae, ska, afrobeat, bossa_nova, samba, flamenco, latin, salsa, cumbia, african, indian_classical, arabic
- **Pop**: pop, indie_pop, synth_pop, dream_pop, k_pop, j_pop
- **R&B/Soul**: rnb, soul, funk, disco, motown, neo_soul
- **Experimental**: experimental, noise, drone, industrial, post_rock, math_rock, shoegaze
- **Relaxation**: meditation, sleep, nature_sounds, spa, yoga, study, piano_relaxing, guitar_relaxing
- **Mood**: christmas, halloween, summer, sad, happy, chill, workout, party
