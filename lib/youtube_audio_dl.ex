defmodule YoutubeAudioDl do
  @moduledoc """
  Download high-quality audio from YouTube videos using exyt_dlp.
  """

  @downloads_dir "downloads"

  @doc """
  Sanitizes a filename by replacing spaces and special characters.
  Only keeps alphanumeric characters, hyphens, and underscores.

  ## Examples

      iex> YoutubeAudioDl.sanitize_filename("Intelligence Isn't What You Think")
      "intelligence_isnt_what_you_think"

  """
  def sanitize_filename(filename) do
    filename
    |> String.downcase()
    # Remove apostrophes entirely
    |> String.replace("'", "")
    # Replace other special chars with underscore
    |> String.replace(~r/[^a-z0-9\-_]/, "_")
    # Collapse multiple underscores
    |> String.replace(~r/_+/, "_")
    # Remove leading/trailing underscores
    |> String.trim("_")
  end

  @doc """
  Downloads audio from a YouTube URL as high-quality MP3.
  Files are saved to the downloads/ directory with sanitized filenames.

  ## Parameters
    - url: YouTube video URL
    - opts: Keyword list of options
      - :output_dir - Output directory (default: "downloads")
      - :force - Skip cache check and re-download (default: false)
      - :category - Cache category/genre (default: "general")

  ## Examples

      iex> YoutubeAudioDl.download_audio("https://www.youtube.com/watch?v=K18Gmp2oXIM")
      {:ok, "downloads/intelligence_isnt_what_you_think.mp3"}

      iex> YoutubeAudioDl.download_audio("https://www.youtube.com/watch?v=abc123", force: true)
      {:ok, "downloads/video_title.mp3"}

      iex> YoutubeAudioDl.download_audio("https://www.youtube.com/watch?v=xyz", category: "lofi")
      {:ok, "downloads/lofi_track.mp3"}

  """
  def download_audio(url, opts \\ [])

  # Support old API: download_audio(url, "output_dir")
  def download_audio(url, output_dir) when is_binary(output_dir) do
    download_audio(url, output_dir: output_dir)
  end

  # New API: download_audio(url, output_dir: "path", force: true, category: "lofi")
  def download_audio(url, opts) when is_list(opts) do
    output_dir = Keyword.get(opts, :output_dir, @downloads_dir)
    force = Keyword.get(opts, :force, false)
    category = Keyword.get(opts, :category, "general")

    # Ensure output directory exists
    File.mkdir_p!(output_dir)

    # Check cache unless force is true
    if not force and YoutubeAudioDl.Cache.downloaded?(url, category) do
      IO.puts("⏭️  Already downloaded (cached in #{category}): #{url}")
      IO.puts("   Use `force: true` to re-download")
      {:error, :already_downloaded}
    else
      do_download(url, output_dir, category)
    end
  end

  # Performs the actual download
  defp do_download(url, output_dir, category) do
    IO.puts("Fetching video title...")

    # Get the video title first
    case Exyt.get_title(url) do
      {:ok, title} ->
        original_title = String.trim(title)
        sanitized_title = sanitize_filename(original_title)
        temp_output = "#{output_dir}/%(title)s.%(ext)s"
        final_filename = "#{output_dir}/#{sanitized_title}.mp3"

        IO.puts("Downloading: #{original_title}")
        IO.puts("Saving as: #{final_filename}")

        # Download with yt-dlp
        options = [
          {:format, "bestaudio/best"},
          :"extract-audio",
          {:"audio-format", "mp3"},
          {:"audio-quality", "0"},
          {:output, temp_output}
        ]

        case Exyt.download(url, options) do
          {:ok, downloaded_file} ->
            # The file might have the original title with spaces
            cleaned_file = String.trim(downloaded_file)

            # Find and rename the MP3 file
            mp3_files = Path.wildcard("#{output_dir}/*.mp3")

            actual_file =
              cond do
                File.exists?(cleaned_file) ->
                  cleaned_file

                length(mp3_files) == 1 ->
                  hd(mp3_files)

                true ->
                  # Find the most recently modified MP3
                  mp3_files
                  |> Enum.map(fn f -> {f, File.stat!(f).mtime} end)
                  |> Enum.sort_by(fn {_, mtime} -> mtime end, :desc)
                  |> List.first()
                  |> case do
                    {file, _} -> file
                    nil -> nil
                  end
              end

            # Rename to sanitized filename
            if actual_file && actual_file != final_filename do
              File.rename!(actual_file, final_filename)
            end

            # Clean up intermediate files (pass both original and sanitized names)
            cleanup_intermediate_files(output_dir, original_title, sanitized_title)

            # Mark as downloaded in cache for this category
            YoutubeAudioDl.Cache.mark_downloaded(url, category)

            IO.puts("\n✓ Download complete!")
            IO.puts("✓ Saved to: #{final_filename}")
            IO.puts("✓ Cached in category: #{category}")
            {:ok, final_filename}

          {:error, reason} ->
            IO.puts("\n✗ Download failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("\n✗ Failed to fetch video title: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Cleans up intermediate files created during download.
  # Only removes files related to the current download, preserves other MP3s.
  defp cleanup_intermediate_files(output_dir, original_title, sanitized_title) do
    # Build patterns to match files from this specific download
    original_base = "#{output_dir}/#{original_title}"
    sanitized_base = "#{output_dir}/#{sanitized_title}"

    Path.wildcard("#{output_dir}/*")
    |> Enum.filter(fn file ->
      basename = Path.basename(file)

      # Delete intermediate files and files with the unsanitized title
      # but keep the final sanitized MP3
      cond do
        # Keep the final sanitized MP3
        file == "#{sanitized_base}.mp3" -> false
        # Delete files with original title (any extension)
        String.starts_with?(file, original_base) -> true
        # Delete intermediate/temporary file types
        String.contains?(basename, ".part") -> true
        String.contains?(basename, ".ytdl") -> true
        String.ends_with?(basename, ".webm") -> true
        String.ends_with?(basename, ".m4a") -> true
        String.ends_with?(basename, ".opus") -> true
        String.ends_with?(basename, ".temp") -> true
        # Keep everything else (other MP3s, etc.)
        true -> false
      end
    end)
    |> Enum.each(fn file ->
      File.rm(file)
      IO.puts("✓ Cleaned up: #{Path.basename(file)}")
    end)
  end
end
