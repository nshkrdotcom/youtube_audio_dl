defmodule YoutubeAudioDl.Cache do
  @moduledoc """
  Simple DETS-based cache to prevent duplicate downloads.
  Tracks URLs that have been successfully downloaded.
  Supports separate cache files per category (e.g., per genre).
  """

  @cache_dir "downloads/.cache"
  @default_category "general"

  @doc """
  Initializes the cache for a specific category.
  Opens or creates the DETS table for that category.

  ## Parameters
    - category: Category name (e.g., "lofi", "jazz", "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.init("lofi")
      :ok

  """
  def init(category \\ @default_category) do
    # Ensure cache directory exists
    File.mkdir_p!(@cache_dir)

    table_name = table_name(category)
    cache_file = cache_file_path(category)

    case :dets.open_file(table_name, file: String.to_charlist(cache_file), type: :set) do
      {:ok, _table} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if a URL has already been downloaded in a specific category.

  ## Parameters
    - url: YouTube URL
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.downloaded?("https://youtube.com/watch?v=abc123", "lofi")
      false

      iex> YoutubeAudioDl.Cache.mark_downloaded("https://youtube.com/watch?v=abc123", "lofi")
      iex> YoutubeAudioDl.Cache.downloaded?("https://youtube.com/watch?v=abc123", "lofi")
      true

  """
  def downloaded?(url, category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    case :dets.lookup(table, url) do
      [{^url, _timestamp}] -> true
      [] -> false
    end
  end

  @doc """
  Marks a URL as downloaded with current timestamp in a specific category.

  ## Parameters
    - url: YouTube URL
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.mark_downloaded("https://youtube.com/watch?v=abc123", "jazz")
      :ok

  """
  def mark_downloaded(url, category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    :dets.insert(table, {url, timestamp})
    # Ensure it's written to disk
    :dets.sync(table)
    :ok
  end

  @doc """
  Gets information about a downloaded URL (when it was downloaded).

  ## Parameters
    - url: YouTube URL
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.get_info("https://youtube.com/watch?v=abc123", "lofi")
      {:ok, %{url: "...", downloaded_at: 1696867200, category: "lofi"}}

  """
  def get_info(url, category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    case :dets.lookup(table, url) do
      [{^url, timestamp}] ->
        {:ok, %{url: url, downloaded_at: timestamp, category: category}}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Removes a URL from the cache (if you want to re-download it).

  ## Parameters
    - url: YouTube URL
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.remove("https://youtube.com/watch?v=abc123", "lofi")
      :ok

  """
  def remove(url, category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    :dets.delete(table, url)
    :dets.sync(table)
    :ok
  end

  @doc """
  Clears the cache for a specific category.
  Use with caution!

  ## Parameters
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.clear_all("lofi")
      :ok

  """
  def clear_all(category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    :dets.delete_all_objects(table)
    :dets.sync(table)
    :ok
  end

  @doc """
  Returns statistics about the cache for a specific category.

  ## Parameters
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.stats("lofi")
      %{total_downloads: 42, cache_file: "downloads/.cache/lofi", category: "lofi"}

  """
  def stats(category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    info = :dets.info(table)
    size = Keyword.get(info, :size, 0)

    %{
      total_downloads: size,
      cache_file: cache_file_path(category),
      category: category,
      table_name: table
    }
  end

  @doc """
  Lists all cache categories (based on existing cache files).

  ## Examples

      iex> YoutubeAudioDl.Cache.list_categories()
      ["general", "lofi", "jazz", "rock"]

  """
  def list_categories do
    if File.exists?(@cache_dir) do
      File.ls!(@cache_dir)
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Returns aggregate statistics across all cache categories.

  ## Examples

      iex> YoutubeAudioDl.Cache.all_stats()
      %{
        total_categories: 5,
        total_downloads: 150,
        categories: [
          %{category: "lofi", total_downloads: 42},
          %{category: "jazz", total_downloads: 35},
          ...
        ]
      }

  """
  def all_stats do
    categories = list_categories()

    category_stats =
      categories
      |> Enum.map(fn cat ->
        stat = stats(cat)
        %{category: cat, total_downloads: stat.total_downloads}
      end)

    total_downloads = Enum.sum(Enum.map(category_stats, & &1.total_downloads))

    %{
      total_categories: length(categories),
      total_downloads: total_downloads,
      categories: category_stats
    }
  end

  @doc """
  Lists all cached URLs with their timestamps for a specific category.

  ## Parameters
    - category: Category name (default: "general")

  ## Examples

      iex> YoutubeAudioDl.Cache.list_all("lofi")
      [
        %{url: "https://...", downloaded_at: 1696867200, category: "lofi"},
        ...
      ]

  """
  def list_all(category \\ @default_category) do
    ensure_open(category)
    table = table_name(category)

    :dets.match_object(table, :"$1")
    |> Enum.map(fn {url, timestamp} ->
      %{url: url, downloaded_at: timestamp, category: category}
    end)
  end

  @doc """
  Closes the DETS table for a specific category.
  Usually not needed as DETS handles this automatically.

  ## Parameters
    - category: Category name (default: "general")

  """
  def close(category \\ @default_category) do
    table = table_name(category)
    :dets.close(table)
  end

  @doc """
  Closes all open DETS tables.
  """
  def close_all do
    list_categories()
    |> Enum.each(&close/1)
  end

  # Private helper functions

  # Ensures the DETS table for a category is open
  defp ensure_open(category) do
    table = table_name(category)

    case :dets.info(table) do
      :undefined -> init(category)
      _ -> :ok
    end
  end

  # Generates table name atom for a category
  defp table_name(category) do
    String.to_atom("youtube_cache_#{category}")
  end

  # Generates cache file path for a category
  defp cache_file_path(category) do
    "#{@cache_dir}/#{category}"
  end
end
