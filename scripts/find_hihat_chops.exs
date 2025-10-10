#!/usr/bin/env elixir

# Two-stage threshold chop point detector
# Usage: elixir find_chops.exs <wav_file>

defmodule ChopDetector do
  @moduledoc """
  Finds precise chop points using two-stage threshold crossing:
  1. Main detection: Find crossings above -40 dB from peak (above noise floor)
  2. Lead-in refinement: Look 40-400 samples back for -50 dB crossing
  """

  def find_chops(wav_file) do
    IO.puts("\n=== TWO-STAGE CHOP DETECTOR ===")
    IO.puts("File: #{wav_file}\n")

    # Extract waveform using ffmpeg
    {waveform, sample_rate} = extract_waveform(wav_file)

    num_samples = length(waveform)
    duration = num_samples / sample_rate

    IO.puts("Sample rate: #{sample_rate} Hz")
    IO.puts("Samples: #{num_samples}")
    IO.puts("Duration: #{Float.round(duration, 2)} seconds\n")

    # Find peak for threshold calculation
    peak = waveform |> Enum.map(&abs/1) |> Enum.max()
    peak_db = 20 * :math.log10(peak)

    IO.puts("Peak amplitude: #{Float.round(peak, 4)}")
    IO.puts("Peak level: #{Float.round(peak_db, 2)} dBFS\n")

    # Stage 1: Main detection threshold (-18 dB from peak)
    main_threshold_db = peak_db - 18
    main_threshold = :math.pow(10, main_threshold_db / 20)

    IO.puts("STAGE 1: Main Detection")

    IO.puts(
      "  Threshold: #{Float.round(main_threshold_db, 2)} dBFS (#{Float.round(main_threshold, 6)})"
    )

    # Find main threshold crossings with windowing
    main_crossings = find_threshold_crossings(waveform, main_threshold, sample_rate)

    IO.puts("  Found #{length(main_crossings)} initial crossings\n")

    # Stage 2: Lead-in refinement (-23 dB from peak)
    leadin_threshold_db = peak_db - 23
    leadin_threshold = :math.pow(10, leadin_threshold_db / 20)

    IO.puts("STAGE 2: Lead-in Refinement")

    IO.puts(
      "  Threshold: #{Float.round(leadin_threshold_db, 2)} dBFS (#{Float.round(leadin_threshold, 6)})"
    )

    IO.puts("  Search window: 40-400 samples back from main crossing")

    # Refine each crossing by looking backward
    chop_points = refine_crossings(waveform, main_crossings, leadin_threshold)

    IO.puts("  Refined to #{length(chop_points)} final chop points\n")

    # Display results
    display_results(chop_points, sample_rate)

    # Export to Audacity label format
    export_labels(chop_points, sample_rate, wav_file)

    {chop_points, sample_rate}
  end

  defp extract_waveform(wav_file) do
    IO.puts("Extracting waveform...")

    # Use ffmpeg to extract mono float samples
    args = [
      "-i",
      wav_file,
      # 32-bit float PCM
      "-f",
      "f32le",
      # Mono
      "-ac",
      "1",
      # 48kHz
      "-ar",
      "48000",
      # Suppress ffmpeg output
      "-v",
      "quiet",
      "pipe:1"
    ]

    {output, 0} = System.cmd("ffmpeg", args, stderr_to_stdout: false)

    # Parse binary float data
    samples = for <<sample::float-32-little <- output>>, do: sample

    {samples, 48000}
  end

  defp find_threshold_crossings(waveform, threshold, sample_rate) do
    # Window-based detection with 50% overlap
    # ~43ms at 48kHz
    window_size = 2048
    hop_size = div(window_size, 2)

    # Convert to list with indices for windowing
    indexed = Enum.with_index(waveform)

    # Find peak in each window
    window_peaks =
      0..(length(waveform) - window_size)
      |> Enum.take_every(hop_size)
      |> Enum.map(fn start_idx ->
        window = Enum.slice(waveform, start_idx, window_size)

        {max_val, max_offset} =
          window
          |> Enum.with_index()
          |> Enum.max_by(fn {sample, _idx} -> abs(sample) end)

        {start_idx + max_offset, abs(max_val)}
      end)
      |> Enum.filter(fn {_pos, amp} -> amp > threshold end)
      |> Enum.map(fn {pos, _amp} -> pos end)

    # Merge nearby crossings (within 100ms)
    # 100ms
    merge_distance = trunc(sample_rate * 0.1)
    merge_nearby(window_peaks, merge_distance)
  end

  defp merge_nearby(positions, min_distance) do
    positions
    |> Enum.sort()
    |> Enum.reduce([], fn pos, acc ->
      case acc do
        [] -> [pos]
        [last | rest] when pos - last < min_distance -> acc
        _ -> [pos | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp refine_crossings(waveform, main_crossings, leadin_threshold) do
    waveform_array = :array.from_list(waveform)

    main_crossings
    |> Enum.map(fn main_pos ->
      # Look backward 40-400 samples
      search_start = max(0, main_pos - 400)
      search_end = max(0, main_pos - 40)

      # Find FIRST crossing above leadin_threshold in this range
      refined_pos =
        search_start..search_end
        |> Enum.find(main_pos, fn pos ->
          sample = :array.get(pos, waveform_array)
          abs(sample) > leadin_threshold
        end)

      refined_pos
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp display_results(chop_points, sample_rate) do
    IO.puts("═══════════════════════════════════════════════════════")
    IO.puts("FINAL CHOP POINTS")
    IO.puts("═══════════════════════════════════════════════════════\n")

    chop_points
    |> Enum.with_index(1)
    |> Enum.take(20)
    |> Enum.each(fn {sample_pos, idx} ->
      time = sample_pos / sample_rate

      IO.puts(
        "  #{String.pad_leading(to_string(idx), 3)}. Sample #{sample_pos} (#{Float.round(time, 3)}s)"
      )
    end)

    if length(chop_points) > 20 do
      IO.puts("  ... and #{length(chop_points) - 20} more")
    end

    # Calculate average spacing
    if length(chop_points) > 1 do
      spacings =
        chop_points
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)

      avg_spacing = Enum.sum(spacings) / length(spacings)
      avg_time = avg_spacing / sample_rate

      IO.puts(
        "\nAverage spacing: #{Float.round(avg_spacing, 1)} samples (#{Float.round(avg_time * 1000, 1)}ms)"
      )
    end

    IO.puts("")
  end

  defp export_labels(chop_points, sample_rate, wav_file) do
    output_file = "chop_points_refined.txt"

    labels =
      chop_points
      |> Enum.with_index(1)
      |> Enum.map(fn {sample_pos, idx} ->
        time = sample_pos / sample_rate
        time_str = :erlang.float_to_binary(time, decimals: 6)
        "#{time_str}\t#{time_str}\tChop#{idx}"
      end)
      |> Enum.join("\n")

    File.write!(output_file, labels <> "\n")

    IO.puts("✓ Exported #{length(chop_points)} chop points to: #{output_file}")
    IO.puts("  Import in Audacity: File → Import → Labels\n")
  end
end

# Main execution
case System.argv() do
  [wav_file] ->
    if File.exists?(wav_file) do
      ChopDetector.find_chops(wav_file)
    else
      IO.puts("Error: File not found: #{wav_file}")
      System.halt(1)
    end

  _ ->
    IO.puts("Usage: elixir find_chops.exs <wav_file>")
    IO.puts("\nExample:")
    IO.puts("  elixir find_chops.exs simple_filter/simple_filter_demos/custom_hp_5000hz.wav")
    System.halt(1)
end
