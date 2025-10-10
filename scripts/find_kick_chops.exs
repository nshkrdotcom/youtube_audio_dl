#!/usr/bin/env elixir

# Kick drum chop detector - optimized for low frequencies
# Use on 90Hz lowpass filtered audio
# Thresholds: -5dB main detection, -19dB lead-in refinement

defmodule KickChopDetector do
  @moduledoc """
  Finds kick drum chop points using two-stage threshold crossing:
  1. Main detection: -5 dB from peak (strong kick hits)
  2. Lead-in refinement: -19 dB from peak (attack onset)
  """

  def find_chops(wav_file) do
    IO.puts("\n=== KICK DRUM CHOP DETECTOR ===")
    IO.puts("File: #{wav_file}\n")

    # Extract waveform
    {waveform, sample_rate} = extract_waveform(wav_file)

    num_samples = length(waveform)
    duration = num_samples / sample_rate

    IO.puts("Sample rate: #{sample_rate} Hz")
    IO.puts("Samples: #{num_samples}")
    IO.puts("Duration: #{Float.round(duration, 2)} seconds\n")

    # Find peak
    peak = waveform |> Enum.map(&abs/1) |> Enum.max()
    peak_db = 20 * :math.log10(peak)

    IO.puts("Peak amplitude: #{Float.round(peak, 4)}")
    IO.puts("Peak level: #{Float.round(peak_db, 2)} dBFS\n")

    # Try multiple threshold combinations
    # {main_db, leadin_db, label}
    threshold_tests = [
      # Very aggressive (find everything)
      {10, 30, "aggressive_wide"},
      {10, 20, "aggressive_tight"},

      # Moderate
      {8, 25, "moderate_wide"},
      {8, 20, "moderate_mid"},
      {8, 15, "moderate_tight"},

      # Conservative (default range)
      {5, 25, "conservative_wide"},
      {5, 20, "conservative_mid"},
      {5, 15, "conservative_tight"},

      # Very selective
      {3, 20, "selective_mid"},
      {3, 15, "selective_tight"}
    ]

    for {main_db, leadin_db, label} <- threshold_tests do
      IO.puts("\n" <> String.duplicate("=", 60))
      IO.puts("TEST: Main -#{main_db}dB, Lead-in -#{leadin_db}dB (#{label})")
      IO.puts(String.duplicate("=", 60))

      main_threshold_db = peak_db - main_db
      main_threshold = :math.pow(10, main_threshold_db / 20)

      IO.puts("\nSTAGE 1: Main Detection -#{main_db}dB")
      IO.puts("  Threshold: #{Float.round(main_threshold_db, 2)} dBFS")

      main_crossings = find_threshold_crossings(waveform, main_threshold, sample_rate)
      IO.puts("  Found #{length(main_crossings)} crossings")

      leadin_threshold_db = peak_db - leadin_db
      leadin_threshold = :math.pow(10, leadin_threshold_db / 20)

      IO.puts("\nSTAGE 2: Lead-in Refinement -#{leadin_db}dB")
      IO.puts("  Threshold: #{Float.round(leadin_threshold_db, 2)} dBFS")

      refined_chops = refine_crossings(waveform, main_crossings, leadin_threshold)
      IO.puts("  Refined to #{length(refined_chops)} chops")

      output_file = "kick_#{label}.txt"

      export_both_stages(
        main_crossings,
        refined_chops,
        sample_rate,
        output_file,
        main_db,
        leadin_db
      )
    end

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("ALL TESTS COMPLETE - Check kick_*.txt files")
    IO.puts(String.duplicate("=", 60))

    :ok
  end

  defp extract_waveform(wav_file) do
    IO.puts("Extracting waveform...")

    args = ["-i", wav_file, "-f", "f32le", "-ac", "1", "-ar", "48000", "-v", "quiet", "pipe:1"]
    {output, 0} = System.cmd("ffmpeg", args, stderr_to_stdout: false)

    samples = for <<sample::float-32-little <- output>>, do: sample
    {samples, 48000}
  end

  defp find_threshold_crossings(waveform, threshold, sample_rate) do
    window_size = 2048
    hop_size = div(window_size, 2)

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

    merge_distance = trunc(sample_rate * 0.1)
    merge_nearby(window_peaks, merge_distance)
  end

  defp merge_nearby(positions, min_distance) do
    positions
    |> Enum.sort()
    |> Enum.reduce([], fn pos, acc ->
      case acc do
        [] -> [pos]
        [last | _rest] when pos - last < min_distance -> acc
        _ -> [pos | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp refine_crossings(waveform, main_crossings, leadin_threshold) do
    waveform_array = :array.from_list(waveform)

    main_crossings
    |> Enum.map(fn main_pos ->
      search_start = max(0, main_pos - 400)
      search_end = max(0, main_pos - 40)

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
    IO.puts("KICK DRUM CHOP POINTS")
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

  defp export_both_stages(
         main_crossings,
         refined_chops,
         sample_rate,
         output_file,
         main_db,
         leadin_db
       ) do
    # Export both stage 1 (main) and stage 2 (refined) to same file
    all_labels = []

    # Add stage 1 markers
    stage1_labels =
      main_crossings
      |> Enum.with_index(1)
      |> Enum.map(fn {sample_pos, idx} ->
        time = sample_pos / sample_rate
        time_str = :erlang.float_to_binary(time, decimals: 6)
        "#{time_str}\t#{time_str}\tS1_#{main_db}dB_#{idx}"
      end)

    # Add stage 2 markers
    stage2_labels =
      refined_chops
      |> Enum.with_index(1)
      |> Enum.map(fn {sample_pos, idx} ->
        time = sample_pos / sample_rate
        time_str = :erlang.float_to_binary(time, decimals: 6)
        "#{time_str}\t#{time_str}\tS2_#{leadin_db}dB_#{idx}"
      end)

    all_labels = (stage1_labels ++ stage2_labels) |> Enum.join("\n")

    File.write!(output_file, all_labels <> "\n")

    IO.puts("✓ Exported to: #{output_file}")
    IO.puts("  Stage 1 (main): #{length(main_crossings)} markers labeled S1_#{main_db}dB_N")
    IO.puts("  Stage 2 (refined): #{length(refined_chops)} markers labeled S2_#{leadin_db}dB_N")
  end
end

# Main execution
case System.argv() do
  [wav_file] ->
    if File.exists?(wav_file) do
      KickChopDetector.find_chops(wav_file)
    else
      IO.puts("Error: File not found: #{wav_file}")
      System.halt(1)
    end

  _ ->
    IO.puts("Usage: elixir find_kick_chops.exs <wav_file>")
    IO.puts("\nExample:")
    IO.puts("  elixir find_kick_chops.exs simple_filter/simple_filter_demos/custom_lp_90hz.wav")
    System.halt(1)
end
