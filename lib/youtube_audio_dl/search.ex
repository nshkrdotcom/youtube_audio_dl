defmodule YoutubeAudioDl.Search do
  @moduledoc """
  Search for YouTube videos and retrieve metadata.
  Uses yt-dlp's built-in search functionality.
  """

  @doc """
  Searches YouTube for videos matching the query.
  Returns a list of video metadata maps.

  ## Parameters
    - query: Search query string
    - opts: Keyword list of options
      - :limit - Number of results to return (default: 5)
      - :min_duration - Minimum duration in seconds (optional)
      - :max_duration - Maximum duration in seconds (optional)

  ## Returns
    {:ok, [%{url: "...", title: "...", duration: 123, ...}]}
    {:error, reason}

  ## Examples

      iex> YoutubeAudioDl.Search.search("lofi hip hop")
      {:ok, [
        %{
          url: "https://www.youtube.com/watch?v=...",
          title: "lofi hip hop radio",
          duration: 3600,
          view_count: 1000000,
          upload_date: "20231015",
          channel: "Lofi Girl"
        },
        ...
      ]}

      iex> YoutubeAudioDl.Search.search("jazz music", limit: 10)
      {:ok, [...]}

      iex> YoutubeAudioDl.Search.search("piano", min_duration: 180, max_duration: 600)
      {:ok, [...]}  # Only 3-10 minute videos

  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    min_duration = Keyword.get(opts, :min_duration)
    max_duration = Keyword.get(opts, :max_duration)

    # Fetch more results if filtering by duration
    # to compensate for filtered-out videos
    fetch_limit = if min_duration || max_duration, do: limit * 3, else: limit
    search_query = "ytsearch#{fetch_limit}:#{query}"

    # Use yt-dlp to search and dump JSON metadata
    params = [
      "--dump-json",
      "--no-warnings",
      "--skip-download"
    ]

    case Exyt.ytdlp(params, search_query) do
      {:ok, output} ->
        videos =
          output
          |> parse_search_results()
          |> filter_by_duration(min_duration, max_duration)
          |> Enum.take(limit)

        {:ok, videos}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches YouTube and returns only video URLs.

  ## Parameters
    - query: Search query string
    - opts: Keyword list of options
      - :limit - Number of results to return (default: 5)

  ## Examples

      iex> YoutubeAudioDl.Search.search_urls("lofi hip hop", limit: 3)
      {:ok, [
        "https://www.youtube.com/watch?v=abc123",
        "https://www.youtube.com/watch?v=def456",
        "https://www.youtube.com/watch?v=ghi789"
      ]}

  """
  def search_urls(query, opts \\ []) do
    case search(query, opts) do
      {:ok, videos} ->
        urls = Enum.map(videos, & &1.url)
        {:ok, urls}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Filters videos by duration
  defp filter_by_duration(videos, nil, nil), do: videos

  defp filter_by_duration(videos, min_duration, max_duration) do
    Enum.filter(videos, fn video ->
      duration = video.duration

      # Skip videos without duration info
      if duration == nil do
        false
      else
        min_ok = if min_duration, do: duration >= min_duration, else: true
        max_ok = if max_duration, do: duration <= max_duration, else: true
        min_ok && max_ok
      end
    end)
  end

  # Parses the JSON output from yt-dlp search
  defp parse_search_results(output) do
    output
    |> String.trim()
    |> String.split("\n")
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&parse_video_json/1)
    |> Enum.filter(&(&1 != nil))
  end

  # Parses a single JSON line into a video metadata map
  defp parse_video_json(json_line) do
    case Jason.decode(json_line) do
      {:ok, data} ->
        %{
          url: "https://www.youtube.com/watch?v=#{data["id"]}",
          id: data["id"],
          title: data["title"],
          duration: data["duration"],
          view_count: data["view_count"],
          upload_date: data["upload_date"],
          channel: data["channel"] || data["uploader"],
          channel_id: data["channel_id"] || data["uploader_id"],
          description: data["description"],
          thumbnail: data["thumbnail"],
          # Additional useful metadata
          like_count: data["like_count"],
          comment_count: data["comment_count"],
          age_limit: data["age_limit"],
          categories: data["categories"],
          tags: data["tags"]
        }

      {:error, _} ->
        nil
    end
  end

  @doc """
  Formats video duration from seconds to human-readable string.

  ## Examples

      iex> YoutubeAudioDl.Search.format_duration(3665)
      "1:01:05"

      iex> YoutubeAudioDl.Search.format_duration(125)
      "2:05"

  """
  def format_duration(nil), do: "N/A"

  def format_duration(seconds) when is_integer(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{String.pad_leading(to_string(minutes), 2, "0")}:#{String.pad_leading(to_string(secs), 2, "0")}"
    else
      "#{minutes}:#{String.pad_leading(to_string(secs), 2, "0")}"
    end
  end

  @doc """
  Formats view count to human-readable string.

  ## Examples

      iex> YoutubeAudioDl.Search.format_views(1234567)
      "1.2M views"

      iex> YoutubeAudioDl.Search.format_views(12345)
      "12.3K views"

  """
  def format_views(nil), do: "N/A"

  def format_views(count) when count >= 1_000_000 do
    "#{Float.round(count / 1_000_000, 1)}M views"
  end

  def format_views(count) when count >= 1_000 do
    "#{Float.round(count / 1_000, 1)}K views"
  end

  def format_views(count) do
    "#{count} views"
  end

  @doc """
  Prints search results in a nice formatted table.

  ## Examples

      iex> {:ok, results} = YoutubeAudioDl.Search.search("lofi")
      iex> YoutubeAudioDl.Search.print_results(results)

  """
  def print_results(videos) when is_list(videos) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("Search Results (#{length(videos)} videos)")
    IO.puts(String.duplicate("=", 80))

    videos
    |> Enum.with_index(1)
    |> Enum.each(fn {video, idx} ->
      IO.puts("\n#{idx}. #{video.title}")
      IO.puts("   Channel: #{video.channel}")

      IO.puts(
        "   Duration: #{format_duration(video.duration)} | Views: #{format_views(video.view_count)}"
      )

      IO.puts("   URL: #{video.url}")
    end)

    IO.puts("\n" <> String.duplicate("=", 80))
  end
end
