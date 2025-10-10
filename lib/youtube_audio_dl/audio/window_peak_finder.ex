defmodule YoutubeAudioDl.Audio.WindowPeakFinder do
  @moduledoc """
  Window-based peak detection:
  1. Divide audio into windows (e.g. 100ms each)
  2. Find the highest peak in each window
  3. Take the top N windows by peak amplitude
  """

  def find_peaks(audio_file, window_ms \\ 100, num_peaks \\ 50) do
    IO.puts("\n=== WINDOW PEAK FINDER ===")
    IO.puts("Window size: #{window_ms}ms")
    IO.puts("Number of peaks: #{num_peaks}")

    with {:ok, audio_info} <- get_audio_info(audio_file),
         {:ok, waveform} <- extract_mono_waveform(audio_info) do
      sample_rate = audio_info.sample_rate
      window_size = trunc(sample_rate * window_ms / 1000)
      # 50% overlap
      hop_size = div(window_size, 2)

      IO.puts("Sample rate: #{sample_rate} Hz")
      IO.puts("Window size: #{window_size} samples (#{window_ms}ms)")
      IO.puts("Hop size: #{hop_size} samples (50% overlap)")
      IO.puts("Total samples: #{length(waveform)}")

      # Step 1: Divide into OVERLAPPING windows (50% hop) and find peak in each
      IO.puts("\nStep 1: Finding peak in each overlapping window...")

      window_peaks =
        create_overlapping_windows(waveform, window_size, hop_size)
        |> Enum.with_index()
        |> Enum.map(fn {window, window_idx} ->
          # Find max absolute amplitude in this window
          {peak_val, peak_offset} =
            window
            |> Enum.with_index()
            |> Enum.max_by(fn {sample, _idx} -> abs(sample) end)

          # Calculate absolute sample position
          sample_pos = window_idx * hop_size + peak_offset

          {sample_pos, abs(peak_val)}
        end)

      IO.puts("✓ Found peaks in #{length(window_peaks)} overlapping windows")

      # Step 2: Sort by amplitude and take more than needed (for deduplication)
      IO.puts("\nStep 2: Sorting by amplitude...")

      sorted_peaks =
        window_peaks
        |> Enum.sort_by(fn {_pos, amp} -> amp end, :desc)

      # Step 3: Deduplicate - if two peaks are within window_size samples, keep the higher one
      IO.puts("\nStep 3: Deduplicating peaks within #{window_ms}ms of each other...")
      deduplicated = deduplicate_peaks(sorted_peaks, window_size)
      IO.puts("✓ After deduplication: #{length(deduplicated)} unique peaks")

      # Step 4: Take top N
      IO.puts("\nStep 4: Selecting top #{num_peaks} peaks...")
      top_peaks = Enum.take(deduplicated, num_peaks)

      IO.puts("✓ Selected top #{length(top_peaks)} peaks")

      # Show top 20
      IO.puts("\n=== TOP #{min(20, length(top_peaks))} PEAKS ===")

      top_peaks
      |> Enum.take(20)
      |> Enum.with_index(1)
      |> Enum.each(fn {{pos, amp}, rank} ->
        time = pos / sample_rate

        IO.puts(
          "#{String.pad_leading(to_string(rank), 3)}. Amp: #{:erlang.float_to_binary(amp, decimals: 4)}  Time: #{Float.round(time, 3)}s"
        )
      end)

      # Step 5: Find attack onset for each peak (look backward for rapid rise)
      IO.puts("\nStep 5: Finding attack onset for each peak...")
      waveform_tuple = List.to_tuple(waveform)

      attack_positions =
        top_peaks
        |> Enum.map(fn {peak_pos, _amp} ->
          find_attack_onset(waveform_tuple, peak_pos, sample_rate)
        end)
        |> Enum.sort()

      IO.puts("✓ Found attack onsets for #{length(attack_positions)} peaks")

      {:ok, attack_positions, audio_info}
    end
  end

  def export_to_audacity(audio_file, peak_positions, sample_rate, output_dir \\ "audacity_export") do
    File.mkdir_p!(output_dir)

    basename = Path.basename(audio_file, Path.extname(audio_file))
    label_file = Path.join(output_dir, "#{basename}_window_peaks.txt")

    labels =
      peak_positions
      |> Enum.with_index(1)
      |> Enum.map(fn {sample, idx} ->
        time = sample / sample_rate
        time_str = :erlang.float_to_binary(time, decimals: 6)
        "#{time_str}\t#{time_str}\tPeak#{idx}"
      end)
      |> Enum.join("\n")

    File.write!(label_file, labels <> "\n")

    IO.puts("\n✓ Exported #{length(peak_positions)} peaks to: #{label_file}")
    {:ok, label_file}
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
    case System.cmd("ffmpeg", [
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
         ]) do
      {binary_data, 0} ->
        samples = for <<s::float-32-little <- binary_data>>, do: s
        {:ok, samples}

      _ ->
        {:error, "Failed to extract waveform"}
    end
  end

  # Create overlapping windows with 50% hop size
  defp create_overlapping_windows(waveform, window_size, hop_size) do
    waveform
    |> Enum.chunk_every(window_size, hop_size, :discard)
  end

  # Deduplicate peaks - if two peaks are close together, keep only the higher one
  defp deduplicate_peaks(sorted_peaks, min_distance) do
    # Already sorted by amplitude descending
    # For each peak, check if any previously kept peak is too close
    {kept, _} =
      Enum.reduce(sorted_peaks, {[], []}, fn {pos, amp}, {kept, kept_positions} ->
        # Check if this peak is too close to any already kept peak
        too_close =
          Enum.any?(kept_positions, fn kept_pos ->
            abs(pos - kept_pos) < min_distance
          end)

        if too_close do
          # Skip this peak (it's a duplicate of a higher peak)
          {kept, kept_positions}
        else
          # Keep this peak
          {[{pos, amp} | kept], [pos | kept_positions]}
        end
      end)

    Enum.reverse(kept)
  end

  # Find attack onset by searching backward from peak for rapid rise
  defp find_attack_onset(waveform_tuple, peak_pos, sample_rate) do
    # Search up to 100ms backward
    max_search = min(peak_pos, trunc(sample_rate * 0.1))

    # Get peak amplitude to use as reference
    peak_amp = abs(elem(waveform_tuple, peak_pos))

    # Find where amplitude drops below 10% of peak (start of the attack)
    threshold = peak_amp * 0.1

    # Search backward for the quiet point
    attack = search_backward_for_quiet(waveform_tuple, peak_pos, max_search, threshold)

    # If we found a quiet point, the attack is right after it
    attack || peak_pos
  end

  # Search backward for a quiet point (where attack begins)
  defp search_backward_for_quiet(waveform_tuple, current_pos, remaining_search, threshold) do
    cond do
      remaining_search <= 0 or current_pos <= 1 ->
        nil

      true ->
        current_sample = abs(elem(waveform_tuple, current_pos))

        if current_sample < threshold do
          # Found quiet point - return the next sample (start of rise)
          current_pos + 1
        else
          # Keep searching backward
          search_backward_for_quiet(
            waveform_tuple,
            current_pos - 1,
            remaining_search - 1,
            threshold
          )
        end
    end
  end
end
