defmodule YoutubeAudioDl.Audio.SimplePeakFinder do
  @moduledoc """
  Dead simple: find the N highest amplitude samples. Period.
  No filtering, no distance constraints, just raw peaks.
  """

  def find_top_peaks(audio_file, num_peaks \\ 50) do
    IO.puts("\n=== SIMPLE PEAK FINDER ===")
    IO.puts("Finding top #{num_peaks} highest amplitude samples...")

    with {:ok, audio_info} <- get_audio_info(audio_file),
         {:ok, waveform} <- extract_mono_waveform(audio_info) do
      sample_rate = audio_info.sample_rate

      IO.puts("Total samples: #{length(waveform)}")

      # Just sort ALL samples by absolute amplitude, take top N
      top_peaks =
        waveform
        |> Enum.with_index()
        |> Enum.map(fn {sample, idx} -> {idx, abs(sample)} end)
        |> Enum.sort_by(fn {_idx, amp} -> amp end, :desc)
        |> Enum.take(num_peaks)

      IO.puts("\n=== TOP #{num_peaks} SAMPLES BY AMPLITUDE ===")

      top_peaks
      |> Enum.with_index(1)
      |> Enum.each(fn {{idx, amp}, rank} ->
        time = idx / sample_rate

        IO.puts(
          "#{String.pad_leading(to_string(rank), 3)}. Amp: #{:erlang.float_to_binary(amp, decimals: 4)}  Time: #{Float.round(time, 6)}s  Sample: #{idx}"
        )
      end)

      # Extract just the sample indices, sort by time
      peak_positions =
        top_peaks
        |> Enum.map(fn {idx, _amp} -> idx end)
        |> Enum.sort()

      {:ok, peak_positions, audio_info}
    end
  end

  def export_to_audacity(audio_file, peak_positions, sample_rate, output_dir \\ "audacity_export") do
    File.mkdir_p!(output_dir)

    basename = Path.basename(audio_file, Path.extname(audio_file))
    label_file = Path.join(output_dir, "#{basename}_peaks.txt")

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
end
