defmodule Mix.Tasks.CheckClicks do
  @moduledoc """
  Checks WAV files in a directory for potential clicks/pops at the beginning or end.

  A click/pop is detected when the waveform starts or ends with a large amplitude
  (not near zero), which would cause an audible discontinuity.

  ## Usage

      mix check_clicks <directory>
      mix check_clicks lofi_drums_zc

  ## Options

      --threshold FLOAT    Amplitude threshold for click detection (default: 0.05)
      --samples N          Number of edge samples to check (default: 10)

  ## Examples

      # Check all WAV files in lofi_drums_zc/
      mix check_clicks lofi_drums_zc

      # Use stricter threshold
      mix check_clicks lofi_drums_zc --threshold 0.02

      # Check more samples at edges
      mix check_clicks lofi_drums_zc --samples 20
  """

  use Mix.Task

  @shortdoc "Check WAV files for clicks/pops at start or end"

  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [threshold: :float, samples: :integer],
        aliases: [t: :threshold, s: :samples]
      )

    threshold = Keyword.get(opts, :threshold, 0.05)
    edge_samples = Keyword.get(opts, :samples, 10)

    case args do
      [directory] ->
        check_directory(directory, threshold, edge_samples)

      _ ->
        IO.puts("""
        Usage: mix check_clicks <directory> [options]

        Options:
          --threshold FLOAT    Amplitude threshold (default: 0.05)
          --samples N          Edge samples to check (default: 10)

        Example:
          mix check_clicks lofi_drums_zc
        """)
    end
  end

  defp check_directory(directory, threshold, edge_samples) do
    unless File.dir?(directory) do
      IO.puts("Error: Directory not found: #{directory}")
      System.halt(1)
    end

    wav_files = Path.wildcard("#{directory}/*.wav")

    if Enum.empty?(wav_files) do
      IO.puts("No WAV files found in: #{directory}")
      System.halt(0)
    end

    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("  Click/Pop Detection Report")
    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("")
    IO.puts("Directory: #{directory}")
    IO.puts("Files: #{length(wav_files)}")
    IO.puts("Threshold: #{threshold}")
    IO.puts("Edge samples checked: #{edge_samples}")
    IO.puts("")

    results =
      Enum.map(wav_files, fn file ->
        check_wav_file(file, threshold, edge_samples)
      end)

    # Summarize
    files_with_clicks = Enum.count(results, fn {_, has_click} -> has_click end)
    clean_files = length(results) - files_with_clicks

    IO.puts("")
    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("  Summary")
    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("")
    IO.puts("✓ Clean files: #{clean_files}")
    IO.puts("✗ Files with possible clicks: #{files_with_clicks}")

    if files_with_clicks > 0 do
      IO.puts("")
      IO.puts("Files with issues:")

      Enum.each(results, fn {file, has_click} ->
        if has_click do
          IO.puts("  - #{Path.basename(file)}")
        end
      end)
    end

    IO.puts("")
  end

  defp check_wav_file(file, threshold, edge_samples) do
    case read_wav_samples(file, edge_samples) do
      {:ok, {start_samples, end_samples}} ->
        start_issue = has_click?(start_samples, threshold)
        end_issue = has_click?(end_samples, threshold)

        display_result(file, start_issue, end_issue, start_samples, end_samples)

        {file, start_issue || end_issue}

      {:error, reason} ->
        IO.puts("✗ #{Path.basename(file)}: Error - #{reason}")
        {file, false}
    end
  end

  defp read_wav_samples(file, edge_samples) do
    # Use FFmpeg to extract first and last N samples as raw PCM
    # First samples
    case System.cmd(
           "ffmpeg",
           [
             "-i",
             file,
             "-f",
             "f32le",
             "-ac",
             "1",
             "-ar",
             "44100",
             # First ~44 samples
             "-t",
             "0.001",
             "-v",
             "quiet",
             "pipe:1"
           ],
           stderr_to_stdout: true
         ) do
      {binary_start, 0} ->
        start_samples = for <<sample::float-32-little <- binary_start>>, do: sample
        start_samples = Enum.take(start_samples, edge_samples)

        # Last samples - get last 0.001 seconds
        case System.cmd(
               "ffmpeg",
               [
                 "-sseof",
                 "-0.001",
                 "-i",
                 file,
                 "-f",
                 "f32le",
                 "-ac",
                 "1",
                 "-ar",
                 "44100",
                 "-v",
                 "quiet",
                 "pipe:1"
               ],
               stderr_to_stdout: true
             ) do
          {binary_end, 0} ->
            end_samples = for <<sample::float-32-little <- binary_end>>, do: sample
            end_samples = Enum.take(end_samples, -edge_samples)

            {:ok, {start_samples, end_samples}}

          _ ->
            {:error, "Failed to read end samples"}
        end

      _ ->
        {:error, "Failed to read start samples"}
    end
  end

  defp has_click?(samples, threshold) do
    if Enum.empty?(samples) do
      false
    else
      # Check if any sample exceeds threshold
      max_abs = samples |> Enum.map(&abs/1) |> Enum.max()
      max_abs > threshold
    end
  end

  defp display_result(file, start_issue, end_issue, start_samples, end_samples) do
    basename = Path.basename(file)

    case {start_issue, end_issue} do
      {false, false} ->
        IO.puts("✓ #{basename}: Clean")

      {true, false} ->
        max_start = start_samples |> Enum.map(&abs/1) |> Enum.max() |> Float.round(4)
        IO.puts("✗ #{basename}: START click (max: #{max_start})")

      {false, true} ->
        max_end = end_samples |> Enum.map(&abs/1) |> Enum.max() |> Float.round(4)
        IO.puts("✗ #{basename}: END click (max: #{max_end})")

      {true, true} ->
        max_start = start_samples |> Enum.map(&abs/1) |> Enum.max() |> Float.round(4)
        max_end = end_samples |> Enum.map(&abs/1) |> Enum.max() |> Float.round(4)
        IO.puts("✗ #{basename}: BOTH clicks (start: #{max_start}, end: #{max_end})")
    end
  end
end
