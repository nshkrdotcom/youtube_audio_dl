defmodule YoutubeAudioDl.Audio.PeakChopper do
  @moduledoc """
  Simple, systematic peak-based chopper.

  Algorithm:
  1. Normalize waveform (max amplitude = 1.0)
  2. Find ALL peaks (sample > both neighbors)
  3. Filter peaks: keep only if no peak within threshold distance before it
  4. Sort by amplitude (descending) - biggest peaks first
  5. Find zero-crossing to the LEFT of each peak

  This finds MAJOR drum hits, not every tiny fluctuation.
  """

  @doc """
  Find chop points using peak-based detection.

  ## Parameters
    - audio_file: Path to audio file
    - min_distance_ms: Minimum milliseconds between peaks (default: 200)
    - max_peaks: Maximum number of peaks to return (default: 50)

  ## Returns
    - {:ok, slice_points, audio_info}
  """
  def find_chops(audio_file, min_distance_ms \\ 200, max_peaks \\ 50) do
    IO.puts("\n=== Peak-Based Chopper ===")
    IO.puts("Min distance: #{min_distance_ms}ms")
    IO.puts("Max peaks: #{max_peaks}")

    with {:ok, audio_info} <- get_audio_info(audio_file),
         {:ok, raw_waveform} <- extract_mono_waveform(audio_info) do
      sample_rate = audio_info.sample_rate
      min_distance_samples = trunc(min_distance_ms * sample_rate / 1000)

      IO.puts("\nStep 1: Normalizing waveform...")
      normalized = normalize(raw_waveform)
      IO.puts("✓ Normalized (max = 1.0)")

      IO.puts("\nStep 2: Finding all peaks...")
      all_peaks = find_all_peaks(normalized)
      IO.puts("✓ Found #{length(all_peaks)} raw peaks")

      IO.puts("\nStep 3: Filtering by minimum distance (#{min_distance_ms}ms)...")
      filtered_peaks = filter_by_distance(all_peaks, min_distance_samples)
      IO.puts("✓ Filtered to #{length(filtered_peaks)} peaks")

      IO.puts("\nStep 4: Sorting by amplitude (descending)...")
      sorted_peaks = Enum.sort_by(filtered_peaks, fn {_idx, amp} -> amp end, :desc)
      top_peaks = Enum.take(sorted_peaks, max_peaks)
      IO.puts("✓ Top #{length(top_peaks)} peaks selected")

      # Show ALL peaks sorted by amplitude
      IO.puts("\n=== ALL #{length(top_peaks)} PEAKS (sorted by amplitude) ===")

      top_peaks
      |> Enum.with_index(1)
      |> Enum.each(fn {{idx, amp}, rank} ->
        time = idx / sample_rate

        IO.puts(
          "#{String.pad_leading(to_string(rank), 3)}. Amp: #{:erlang.float_to_binary(amp, decimals: 4)}  Time: #{Float.round(time, 3)}s"
        )
      end)

      IO.puts("\nStep 5: Extracting peak positions...")

      # Just use the peak positions directly (not zero-crossings)
      peak_positions =
        top_peaks
        |> Enum.map(fn {peak_idx, _amp} -> peak_idx end)
        |> Enum.sort()
        |> Enum.uniq()

      # Always start at 0
      chop_points = if 0 in peak_positions, do: peak_positions, else: [0 | peak_positions]

      IO.puts("✓ Using #{length(chop_points)} peak positions as chop points\n")

      {:ok, chop_points, audio_info}
    end
  end

  # Step 1: Normalize waveform to [-1.0, 1.0]
  defp normalize(waveform) do
    abs_max =
      waveform
      |> Enum.map(&abs/1)
      |> Enum.max()

    if abs_max > 0 do
      Enum.map(waveform, fn sample -> sample / abs_max end)
    else
      waveform
    end
  end

  # Step 2: Find ALL peaks (sample > both neighbors)
  defp find_all_peaks(waveform) do
    waveform_tuple = List.to_tuple(waveform)
    max_idx = tuple_size(waveform_tuple) - 1

    # Scan through waveform, find peaks
    1..(max_idx - 1)
    |> Enum.filter(fn idx ->
      curr = elem(waveform_tuple, idx)
      prev = elem(waveform_tuple, idx - 1)
      next = elem(waveform_tuple, idx + 1)

      # Peak: higher than both neighbors, and positive
      curr > prev and curr > next and curr > 0
    end)
    |> Enum.map(fn idx ->
      {idx, elem(waveform_tuple, idx)}
    end)
  end

  # Step 3: Filter peaks - keep FIRST peak, skip any within min_distance after it
  defp filter_by_distance(peaks, min_distance) do
    # Sort by position first
    sorted = Enum.sort_by(peaks, fn {idx, _amp} -> idx end)

    # Keep FIRST peak in each cluster, skip subsequent ones within min_distance
    {filtered, _} =
      Enum.reduce(sorted, {[], -999_999}, fn {idx, amp}, {acc, last_kept_idx} ->
        if idx - last_kept_idx >= min_distance do
          # Far enough from last kept peak - keep this one
          {[{idx, amp} | acc], idx}
        else
          # Too close to previous peak - skip it (it's part of the same transient)
          {acc, last_kept_idx}
        end
      end)

    Enum.reverse(filtered)
  end

  # Step 5: Find zero-crossing to the LEFT of peak
  defp find_zero_crossing_left(waveform_tuple, position) when position <= 0, do: 0

  defp find_zero_crossing_left(waveform_tuple, position) do
    # ~200ms at 48kHz
    max_search = min(position, 9600)

    # Search backward for zero crossing
    result =
      Enum.find(position..max(0, position - max_search)//-1, fn idx ->
        if idx > 0 do
          current = elem(waveform_tuple, idx)
          prev = elem(waveform_tuple, idx - 1)

          # Zero crossing = sign change
          (current >= 0 and prev < 0) or (current < 0 and prev >= 0)
        else
          # Use 0 if we reach the start
          true
        end
      end)

    result || position
  end

  # Get audio metadata
  defp get_audio_info(audio_file) do
    unless File.exists?(audio_file) do
      {:error, "File not found"}
    else
      case System.cmd("ffprobe", [
             "-v",
             "quiet",
             "-print_format",
             "json",
             "-show_format",
             "-show_streams",
             audio_file
           ]) do
        {output, 0} ->
          parse_audio_info(output, audio_file)

        _ ->
          {:error, "Failed to read audio file"}
      end
    end
  end

  defp parse_audio_info(json, audio_file) do
    case Jason.decode(json) do
      {:ok, data} ->
        stream = Enum.find(data["streams"], fn s -> s["codec_type"] == "audio" end)

        if stream do
          {:ok,
           %{
             file_path: audio_file,
             sample_rate: String.to_integer(stream["sample_rate"] || "44100"),
             duration: String.to_float(stream["duration"] || data["format"]["duration"] || "0")
           }}
        else
          {:error, "No audio stream"}
        end

      _ ->
        {:error, "Failed to parse audio info"}
    end
  end

  # Extract mono waveform
  defp extract_mono_waveform(audio_info) do
    case System.cmd(
           "ffmpeg",
           [
             "-i",
             audio_info.file_path,
             "-f",
             "f32le",
             "-ac",
             "1",
             "-ar",
             to_string(audio_info.sample_rate),
             "-v",
             "quiet",
             "pipe:1"
           ],
           stderr_to_stdout: true
         ) do
      {binary_data, 0} ->
        samples = for <<s::float-32-little <- binary_data>>, do: s
        {:ok, samples}

      _ ->
        {:error, "Failed to extract waveform"}
    end
  end

  @doc """
  Export chop points to Audacity label format.
  """
  def export_to_audacity(audio_file, chop_points, sample_rate, output_dir \\ "audacity_export") do
    File.mkdir_p!(output_dir)

    basename = Path.basename(audio_file, Path.extname(audio_file))
    label_file = Path.join(output_dir, "#{basename}_chops.txt")

    # Write labels
    labels =
      chop_points
      |> Enum.with_index(1)
      |> Enum.map(fn {sample, idx} ->
        time = sample / sample_rate
        time_str = :erlang.float_to_binary(time, decimals: 6)
        "#{time_str}\t#{time_str}\tChop#{idx}"
      end)
      |> Enum.join("\n")

    File.write!(label_file, labels <> "\n")

    IO.puts("\n✓ Exported #{length(chop_points)} chops to: #{label_file}")
    {:ok, label_file}
  end
end
