defmodule YoutubeAudioDl.Audio.Examples do
  @moduledoc """
  Example usage patterns for the waveform slicing functionality.

  This module demonstrates how to use the WaveformSlicer to analyze and
  slice audio files, similar to Propellerhead ReCycle.
  """

  alias YoutubeAudioDl.Audio.WaveformSlicer

  @doc """
  Example 1: Basic transient detection on a downloaded audio file.

  This example shows how to find breakpoints in an audio file with
  default sensitivity settings.
  """
  def example_basic_slicing do
    # First, download an audio file (e.g., a drum loop)
    url = "https://www.youtube.com/watch?v=DRUM_LOOP_VIDEO_ID"

    case YoutubeAudioDl.download_audio(url) do
      {:ok, audio_file} ->
        IO.puts("Downloaded: #{audio_file}")
        IO.puts("Analyzing waveform for transients...")

        # Find breakpoints with medium sensitivity (0.5)
        case WaveformSlicer.find_breakpoints(audio_file, 0.5) do
          {:ok, breakpoints, info} ->
            IO.puts("\nFound #{length(breakpoints)} breakpoints!")
            IO.puts("Sample rate: #{info.sample_rate} Hz")
            IO.puts("Duration: #{Float.round(info.duration, 2)} seconds")
            IO.puts("\nBreakpoint samples: #{inspect(Enum.take(breakpoints, 10))}")

            # Convert sample numbers to timestamps
            timestamps =
              Enum.map(breakpoints, fn sample ->
                time_ms = sample / info.sample_rate * 1000
                Float.round(time_ms, 2)
              end)

            IO.puts("Breakpoint times (ms): #{inspect(Enum.take(timestamps, 10))}")

            {:ok, breakpoints, info}

          {:error, reason} ->
            IO.puts("Error analyzing audio: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 2: Slice and export audio segments.

  This example demonstrates how to slice an audio file at detected
  transients and export each segment as a separate WAV file.
  """
  def example_export_slices(audio_file, output_dir \\ "slices") do
    IO.puts("Analyzing: #{audio_file}")

    # Use lower sensitivity to detect more transients
    case WaveformSlicer.find_breakpoints(audio_file, 0.3) do
      {:ok, breakpoints, _info} ->
        IO.puts("Found #{length(breakpoints)} slices")
        IO.puts("Exporting to: #{output_dir}/")

        # Export each slice as a separate WAV file
        case WaveformSlicer.export_slices(audio_file, breakpoints, output_dir) do
          {:ok, exported_files} ->
            IO.puts("\n✓ Exported #{length(exported_files)} slices:")

            Enum.each(exported_files, fn file ->
              IO.puts("  - #{file}")
            end)

            {:ok, exported_files}

          {:error, reason} ->
            IO.puts("Export failed: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("Analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 3: Sensitivity comparison.

  This example demonstrates how different sensitivity settings affect
  the number of detected transients.
  """
  def example_sensitivity_comparison(audio_file) do
    sensitivities = [0.1, 0.3, 0.5, 0.7, 0.9]

    IO.puts("Comparing sensitivity levels for: #{audio_file}\n")

    results =
      Enum.map(sensitivities, fn sensitivity ->
        case WaveformSlicer.find_breakpoints(audio_file, sensitivity) do
          {:ok, breakpoints, _info} ->
            slice_count = length(breakpoints)
            IO.puts("Sensitivity #{sensitivity}: #{slice_count} slices")
            {sensitivity, slice_count, breakpoints}

          {:error, reason} ->
            IO.puts("Sensitivity #{sensitivity}: Error - #{inspect(reason)}")
            {sensitivity, 0, []}
        end
      end)

    IO.puts("\nRecommendations:")
    IO.puts("  - Low sensitivity (0.1-0.3): More slices, good for detailed editing")
    IO.puts("  - Medium sensitivity (0.4-0.6): Balanced, good for most loops")
    IO.puts("  - High sensitivity (0.7-0.9): Fewer slices, only major transients")

    results
  end

  @doc """
  Example 4: Advanced options - custom minimum distance between peaks.

  This shows how to control the minimum spacing between detected transients.
  """
  def example_custom_min_distance(audio_file) do
    # At 44.1kHz sample rate:
    # 4410 samples = ~100ms
    # 2205 samples = ~50ms
    # 8820 samples = ~200ms

    options = [
      # Minimum 200ms between slices
      min_distance: 8820,
      apply_filter: true,
      normalize: true
    ]

    case WaveformSlicer.find_breakpoints(audio_file, 0.5, options) do
      {:ok, breakpoints, info} ->
        IO.puts("Found #{length(breakpoints)} breakpoints")
        IO.puts("Minimum distance: ~200ms between slices")

        # Calculate actual distances between consecutive breakpoints
        distances =
          breakpoints
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.map(fn [a, b] ->
            distance_ms = (b - a) / info.sample_rate * 1000
            Float.round(distance_ms, 2)
          end)

        IO.puts("Actual distances (ms): #{inspect(Enum.take(distances, 10))}")

        {:ok, breakpoints}

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Example 5: Complete workflow - download, analyze, slice, export.

  This demonstrates a complete workflow from YouTube URL to exported slices.
  """
  def example_complete_workflow(youtube_url, sensitivity \\ 0.5) do
    IO.puts("=== Complete Waveform Slicing Workflow ===\n")

    # Step 1: Download audio
    IO.puts("Step 1: Downloading audio from YouTube...")

    case YoutubeAudioDl.download_audio(youtube_url) do
      {:ok, audio_file} ->
        IO.puts("✓ Downloaded: #{audio_file}\n")

        # Step 2: Get audio info
        IO.puts("Step 2: Analyzing audio file...")

        case WaveformSlicer.get_audio_info(audio_file) do
          {:ok, info} ->
            IO.puts("✓ Sample rate: #{info.sample_rate} Hz")
            IO.puts("✓ Channels: #{info.channels}")
            IO.puts("✓ Duration: #{Float.round(info.duration, 2)} seconds")
            IO.puts("✓ Codec: #{info.codec}\n")

            # Step 3: Find breakpoints
            IO.puts("Step 3: Detecting transients (sensitivity: #{sensitivity})...")

            case WaveformSlicer.find_breakpoints(audio_file, sensitivity) do
              {:ok, breakpoints, _info} ->
                IO.puts("✓ Found #{length(breakpoints)} transients\n")

                # Step 4: Export slices
                IO.puts("Step 4: Exporting slices...")
                output_dir = "slices_#{Path.basename(audio_file, ".mp3")}"

                case WaveformSlicer.export_slices(audio_file, breakpoints, output_dir) do
                  {:ok, exported_files} ->
                    IO.puts("✓ Exported #{length(exported_files)} slices to #{output_dir}/\n")

                    IO.puts("=== Workflow Complete ===")
                    IO.puts("Original file: #{audio_file}")
                    IO.puts("Slices directory: #{output_dir}/")
                    IO.puts("Total slices: #{length(exported_files)}")

                    {:ok,
                     %{
                       audio_file: audio_file,
                       output_dir: output_dir,
                       breakpoints: breakpoints,
                       exported_files: exported_files
                     }}

                  {:error, reason} ->
                    IO.puts("✗ Export failed: #{inspect(reason)}")
                    {:error, reason}
                end

              {:error, reason} ->
                IO.puts("✗ Transient detection failed: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, reason} ->
            IO.puts("✗ Could not read audio info: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("✗ Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
