defmodule YoutubeAudioDl.Music do
  @moduledoc """
  Simplified interface for discovering and downloading music by genre.
  Provides curated search queries for various musical genres.
  """

  alias YoutubeAudioDl.Search

  @genres %{
    # Electronic & Dance
    lofi: "lofi hip hop beats to study relax",
    edm: "electronic dance music mix",
    techno: "techno mix",
    house: "house music mix",
    trance: "trance music mix",
    dubstep: "dubstep mix",
    drum_and_bass: "drum and bass mix",
    chillwave: "chillwave electronic",
    synthwave: "synthwave retrowave mix",
    vaporwave: "vaporwave aesthetic mix",
    ambient: "ambient music relaxing",
    downtempo: "downtempo chill beats",

    # Hip Hop & Rap
    hip_hop: "hip hop mix",
    rap: "rap music mix",
    trap: "trap music mix",
    boom_bap: "boom bap hip hop beats",
    underground_hip_hop: "underground hip hop",
    old_school_hip_hop: "old school hip hop 90s",

    # Jazz & Blues
    jazz: "jazz music smooth",
    smooth_jazz: "smooth jazz instrumental",
    jazz_fusion: "jazz fusion",
    bebop: "bebop jazz",
    cool_jazz: "cool jazz",
    blues: "blues music",
    delta_blues: "delta blues guitar",
    chicago_blues: "chicago blues",

    # Rock & Metal
    rock: "rock music",
    classic_rock: "classic rock hits",
    alternative_rock: "alternative rock",
    indie_rock: "indie rock",
    punk_rock: "punk rock",
    hard_rock: "hard rock",
    progressive_rock: "progressive rock",
    metal: "metal music",
    heavy_metal: "heavy metal",
    death_metal: "death metal",
    black_metal: "black metal",
    doom_metal: "doom metal",
    thrash_metal: "thrash metal",
    power_metal: "power metal",

    # Classical & Orchestral
    classical: "classical music",
    baroque: "baroque classical music",
    romantic: "romantic era classical",
    contemporary_classical: "contemporary classical music",
    piano: "classical piano music",
    violin: "classical violin music",
    orchestra: "orchestral music",
    chamber_music: "chamber music",
    opera: "opera arias",

    # Folk & Traditional
    folk: "folk music",
    acoustic: "acoustic music",
    bluegrass: "bluegrass music",
    country: "country music",
    celtic: "celtic music",
    irish_folk: "irish folk music",
    americana: "americana folk",

    # World Music
    world: "world music",
    reggae: "reggae music",
    ska: "ska music",
    afrobeat: "afrobeat music",
    bossa_nova: "bossa nova brazilian",
    samba: "samba music",
    flamenco: "flamenco guitar",
    latin: "latin music",
    salsa: "salsa music",
    cumbia: "cumbia music",
    african: "african music traditional",
    indian_classical: "indian classical music",
    arabic: "arabic music traditional",

    # Pop & Contemporary
    pop: "pop music",
    indie_pop: "indie pop",
    synth_pop: "synth pop 80s",
    dream_pop: "dream pop shoegaze",
    k_pop: "kpop korean pop",
    j_pop: "jpop japanese pop",

    # R&B, Soul & Funk
    rnb: "r&b music",
    soul: "soul music",
    funk: "funk music",
    disco: "disco music 70s",
    motown: "motown classics",
    neo_soul: "neo soul",

    # Experimental & Niche
    experimental: "experimental music",
    noise: "noise music experimental",
    drone: "drone ambient music",
    industrial: "industrial music",
    post_rock: "post rock instrumental",
    math_rock: "math rock",
    shoegaze: "shoegaze music",

    # Relaxation & Focus
    meditation: "meditation music relaxing",
    sleep: "sleep music deep relaxation",
    nature_sounds: "nature sounds relaxing",
    spa: "spa music massage relaxation",
    yoga: "yoga music peaceful",
    study: "study music focus concentration",
    piano_relaxing: "relaxing piano music",
    guitar_relaxing: "relaxing guitar music",

    # Seasonal & Mood
    christmas: "christmas music",
    halloween: "halloween music spooky",
    summer: "summer music vibes",
    sad: "sad emotional music",
    happy: "happy upbeat music",
    chill: "chill music mix",
    workout: "workout music motivation",
    party: "party music mix"
  }

  @doc """
  Lists all available music genres.

  ## Examples

      iex> YoutubeAudioDl.Music.list_genres()
      [:lofi, :jazz, :rock, :classical, ...]

  """
  def list_genres do
    Map.keys(@genres) |> Enum.sort()
  end

  @doc """
  Gets the search query for a specific genre.

  ## Examples

      iex> YoutubeAudioDl.Music.get_genre_query(:lofi)
      "lofi hip hop beats to study relax"

  """
  def get_genre_query(genre) when is_atom(genre) do
    Map.get(@genres, genre)
  end

  @doc """
  Searches for music by genre.
  Returns video metadata including URLs, titles, duration, etc.

  ## Parameters
    - genre: Genre atom (e.g., :lofi, :jazz, :rock)
    - opts: Keyword list of options
      - :limit - Number of results (default: 5)

  ## Examples

      iex> YoutubeAudioDl.Music.search(:lofi)
      {:ok, [%{url: "...", title: "...", duration: 3600, ...}, ...]}

      iex> YoutubeAudioDl.Music.search(:jazz, limit: 10)
      {:ok, [...]}

  """
  def search(genre, opts \\ []) when is_atom(genre) do
    case get_genre_query(genre) do
      nil ->
        {:error, "Unknown genre: #{genre}. Use list_genres() to see available genres."}

      query ->
        Search.search(query, opts)
    end
  end

  @doc """
  Searches for music by genre and returns only URLs.

  ## Examples

      iex> YoutubeAudioDl.Music.search_urls(:lofi, limit: 3)
      {:ok, ["https://...", "https://...", "https://..."]}

  """
  def search_urls(genre, opts \\ []) when is_atom(genre) do
    case search(genre, opts) do
      {:ok, videos} ->
        urls = Enum.map(videos, & &1.url)
        {:ok, urls}

      error ->
        error
    end
  end

  @doc """
  Searches for music by genre and downloads the first result.

  ## Parameters
    - genre: Genre atom
    - opts: Keyword list of options
      - :output_dir - Output directory (default: "downloads")
      - :index - Which search result to download (default: 1)
      - :force - Skip cache check and re-download (default: false)

  ## Examples

      iex> YoutubeAudioDl.Music.download(:lofi)
      {:ok, "downloads/lofi_hip_hop_beats.mp3"}

      iex> YoutubeAudioDl.Music.download(:jazz, index: 2, output_dir: "./music")
      {:ok, "./music/smooth_jazz.mp3"}

      iex> YoutubeAudioDl.Music.download(:lofi, force: true)
      {:ok, "downloads/lofi_hip_hop_beats.mp3"}

  """
  def download(genre, opts \\ []) when is_atom(genre) do
    index = Keyword.get(opts, :index, 1)
    output_dir = Keyword.get(opts, :output_dir, "downloads")
    force = Keyword.get(opts, :force, false)
    search_limit = Keyword.get(opts, :limit, index)

    with {:ok, videos} <- search(genre, limit: search_limit),
         video when not is_nil(video) <- Enum.at(videos, index - 1) do
      IO.puts("\nDownloading: #{video.title}")
      IO.puts("Channel: #{video.channel}")
      IO.puts("Duration: #{Search.format_duration(video.duration)}\n")

      # Use genre as cache category
      category = to_string(genre)

      YoutubeAudioDl.download_audio(video.url,
        output_dir: output_dir,
        force: force,
        category: category
      )
    else
      nil ->
        {:error, "No video found at index #{index}"}

      error ->
        error
    end
  end

  @doc """
  Searches and displays results for a genre in a nice format.

  ## Examples

      iex> YoutubeAudioDl.Music.browse(:lofi)
      # Displays formatted search results

      iex> YoutubeAudioDl.Music.browse(:jazz, limit: 10)
      # Displays 10 jazz music results

  """
  def browse(genre, opts \\ []) when is_atom(genre) do
    limit = Keyword.get(opts, :limit, 5)

    case search(genre, limit: limit) do
      {:ok, videos} ->
        IO.puts("\n🎵 Genre: #{genre |> to_string() |> String.upcase()}")
        Search.print_results(videos)
        {:ok, videos}

      error ->
        error
    end
  end

  @doc """
  Downloads multiple tracks from a genre.
  Skips already downloaded tracks by default (uses cache).

  ## Parameters
    - genre: Genre atom
    - count: Number of tracks to download
    - opts: Keyword list of options
      - :output_dir - Output directory (default: "downloads")
      - :force - Skip cache check and re-download all (default: false)

  ## Examples

      iex> YoutubeAudioDl.Music.download_multiple(:lofi, 3)
      {:ok, ["downloads/track1.mp3", "downloads/track2.mp3", "downloads/track3.mp3"]}

      iex> YoutubeAudioDl.Music.download_multiple(:jazz, 5, force: true)
      {:ok, [...]}

  """
  def download_multiple(genre, count, opts \\ []) when is_atom(genre) and is_integer(count) do
    output_dir = Keyword.get(opts, :output_dir, "downloads")
    force = Keyword.get(opts, :force, false)

    # Warn about large searches
    if count > 10 do
      IO.puts("\n⏳ Searching for #{count} videos may take a while...")
    end

    IO.puts("🔍 Searching for #{count} #{genre} tracks...")

    case search(genre, limit: count) do
      {:ok, videos} ->
        actual_count = length(videos)

        if actual_count < count do
          IO.puts("⚠️  Only found #{actual_count} videos (requested #{count})")
        else
          IO.puts("✓ Found #{actual_count} videos")
        end

        # Use genre as cache category
        category = to_string(genre)

        results =
          videos
          |> Enum.with_index(1)
          |> Enum.map(fn {video, idx} ->
            IO.puts("\n[#{idx}/#{actual_count}] Downloading: #{video.title}")

            YoutubeAudioDl.download_audio(video.url,
              output_dir: output_dir,
              force: force,
              category: category
            )
          end)

        successful = Enum.filter(results, fn result -> match?({:ok, _}, result) end)

        skipped =
          Enum.count(results, fn result -> match?({:error, :already_downloaded}, result) end)

        failed = actual_count - length(successful) - skipped

        IO.puts("\n" <> String.duplicate("=", 60))
        IO.puts("📊 Summary:")
        IO.puts("   ✓ Downloaded: #{length(successful)}")
        if skipped > 0, do: IO.puts("   ⏭️  Skipped (cached): #{skipped}")
        if failed > 0, do: IO.puts("   ✗ Failed: #{failed}")
        IO.puts(String.duplicate("=", 60))

        {:ok, Enum.map(successful, fn {:ok, path} -> path end)}

      {:error, reason} ->
        IO.puts("\n✗ Search failed: #{inspect(reason)}")
        {:error, reason}

      error ->
        error
    end
  end

  @doc """
  Prints all available genres organized by category.
  """
  def print_genres do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Available Music Genres")
    IO.puts(String.duplicate("=", 80))

    categories = [
      {"Electronic & Dance",
       [
         :lofi,
         :edm,
         :techno,
         :house,
         :trance,
         :dubstep,
         :drum_and_bass,
         :chillwave,
         :synthwave,
         :vaporwave,
         :ambient,
         :downtempo
       ]},
      {"Hip Hop & Rap",
       [
         :hip_hop,
         :rap,
         :trap,
         :boom_bap,
         :underground_hip_hop,
         :old_school_hip_hop
       ]},
      {"Jazz & Blues",
       [
         :jazz,
         :smooth_jazz,
         :jazz_fusion,
         :bebop,
         :cool_jazz,
         :blues,
         :delta_blues,
         :chicago_blues
       ]},
      {"Rock & Metal",
       [
         :rock,
         :classic_rock,
         :alternative_rock,
         :indie_rock,
         :punk_rock,
         :hard_rock,
         :progressive_rock,
         :metal,
         :heavy_metal,
         :death_metal,
         :black_metal,
         :doom_metal,
         :thrash_metal,
         :power_metal
       ]},
      {"Classical & Orchestral",
       [
         :classical,
         :baroque,
         :romantic,
         :contemporary_classical,
         :piano,
         :violin,
         :orchestra,
         :chamber_music,
         :opera
       ]},
      {"Folk & Traditional",
       [
         :folk,
         :acoustic,
         :bluegrass,
         :country,
         :celtic,
         :irish_folk,
         :americana
       ]},
      {"World Music",
       [
         :world,
         :reggae,
         :ska,
         :afrobeat,
         :bossa_nova,
         :samba,
         :flamenco,
         :latin,
         :salsa,
         :cumbia,
         :african,
         :indian_classical,
         :arabic
       ]},
      {"Pop & Contemporary",
       [
         :pop,
         :indie_pop,
         :synth_pop,
         :dream_pop,
         :k_pop,
         :j_pop
       ]},
      {"R&B, Soul & Funk",
       [
         :rnb,
         :soul,
         :funk,
         :disco,
         :motown,
         :neo_soul
       ]},
      {"Experimental & Niche",
       [
         :experimental,
         :noise,
         :drone,
         :industrial,
         :post_rock,
         :math_rock,
         :shoegaze
       ]},
      {"Relaxation & Focus",
       [
         :meditation,
         :sleep,
         :nature_sounds,
         :spa,
         :yoga,
         :study,
         :piano_relaxing,
         :guitar_relaxing
       ]},
      {"Seasonal & Mood",
       [
         :christmas,
         :halloween,
         :summer,
         :sad,
         :happy,
         :chill,
         :workout,
         :party
       ]}
    ]

    Enum.each(categories, fn {category, genres} ->
      IO.puts("\n#{category}:")

      genres
      |> Enum.chunk_every(4)
      |> Enum.each(fn chunk ->
        line = chunk |> Enum.map(&"  :#{&1}") |> Enum.join(", ")
        IO.puts(line)
      end)
    end)

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Total: #{length(list_genres())} genres available")
    IO.puts(String.duplicate("=", 80) <> "\n")
  end
end
