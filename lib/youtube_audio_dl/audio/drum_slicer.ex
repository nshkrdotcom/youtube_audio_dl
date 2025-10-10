defmodule YoutubeAudioDl.Audio.DrumSlicer do
  @moduledoc """
  Simple drum slicer that finds sharp transient peaks and slices at zero-crossings.

  Algorithm:
  1. Find sharp peaks (high amplitude, quick rise/fall)
  2. For each peak, find zero-crossing to the LEFT
  3. That's the chop point
  """

  @doc """
  Find drum slice points in audio.

  Returns list of sample positions where slices should occur.
  """
  def find_slice_points(audio_file, options \\ []) do
    # Peak must be > this amplitude
    threshold = Keyword.get(options, :threshold, 0.3)
    # ~250ms at 44.1kHz
    min_distance = Keyword.get(options, :min_distance, 11025)

    with {:ok, audio_info} <- get_audio_info(audio_file),
         {:ok, waveform} <- extract_mono_waveform(audio_info) do
      # Find sharp peaks
      peaks = find_sharp_peaks(waveform, threshold, min_distance)

      # Convert to tuple ONCE for fast zero-crossing search
      waveform_tuple = List.to_tuple(waveform)

      # For each peak, find zero-crossing to the left
      slice_points =
        Enum.map(peaks, fn peak_pos ->
          find_zero_crossing_left(waveform_tuple, peak_pos)
        end)

      # Always start at 0
      slice_points = [0 | slice_points] |> Enum.uniq() |> Enum.sort()

      {:ok, slice_points, audio_info}
    end
  end

  # Find sharp transient peaks (staccato - quick spike up and down)
  # Optimized: use recursive approach instead of Enum operations
  defp find_sharp_peaks(waveform, threshold, min_distance) do
    find_peaks_recursive(waveform, threshold, min_distance, 1, [], 0)
    |> Enum.reverse()
  end

  # Recursive peak finder - much faster than Enum operations on huge lists
  defp find_peaks_recursive(
         [prev, curr, next | rest],
         threshold,
         min_distance,
         idx,
         acc,
         last_peak
       ) do
    # Check if this is a peak
    is_peak = abs(curr) > abs(prev) and abs(curr) > abs(next)
    is_loud = abs(curr) > threshold
    is_sharp = abs(curr - prev) > threshold * 0.5
    far_enough = idx - last_peak >= min_distance

    if is_peak and is_loud and is_sharp and far_enough do
      find_peaks_recursive(
        [curr, next | rest],
        threshold,
        min_distance,
        idx + 1,
        [idx | acc],
        idx
      )
    else
      find_peaks_recursive([curr, next | rest], threshold, min_distance, idx + 1, acc, last_peak)
    end
  end

  defp find_peaks_recursive(_, _, _, _, acc, _), do: acc

  # Keep only peaks that are at least min_distance apart
  defp filter_by_min_distance(peaks, min_distance) do
    peaks
    |> Enum.reduce([], fn peak, acc ->
      if acc == [] do
        [peak]
      else
        last = hd(acc)

        if peak - last >= min_distance do
          [peak | acc]
        else
          # Keep the one with higher amplitude? For now just keep first
          acc
        end
      end
    end)
    |> Enum.reverse()
  end

  # Find zero-crossing to the LEFT of position
  # Expects waveform_tuple (already converted to tuple)
  defp find_zero_crossing_left(_waveform_tuple, position) when position <= 0, do: 0

  defp find_zero_crossing_left(waveform_tuple, position) do
    # ~42ms at 48kHz
    max_search = min(position, 2000)
    # Search backward for zero-crossing
    search_backward(waveform_tuple, position, max_search)
  end

  # Recursive backward search - fast O(1) tuple access
  # Searched enough, give up
  defp search_backward(waveform_tuple, idx, 0), do: idx
  defp search_backward(_waveform_tuple, 0, _), do: 0

  defp search_backward(waveform_tuple, idx, remaining) when idx > 0 do
    current = elem(waveform_tuple, idx)
    prev = elem(waveform_tuple, idx - 1)

    # Check for zero crossing (sign change)
    if (current >= 0 and prev < 0) or (current < 0 and prev >= 0) do
      # Found it!
      idx
    else
      search_backward(waveform_tuple, idx - 1, remaining - 1)
    end
  end

  defp search_backward(_, idx, _), do: idx

  # Get audio info
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

  # Extract mono waveform at original sample rate
  defp extract_mono_waveform(audio_info) do
    case System.cmd(
           "ffmpeg",
           [
             "-i",
             audio_info.file_path,
             "-f",
             "f32le",
             # Mono
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
  Export slices to separate files.
  """
  def export_slices(audio_file, slice_points, output_dir) do
    File.mkdir_p!(output_dir)

    with {:ok, audio_info} <- get_audio_info(audio_file) do
      sample_rate = audio_info.sample_rate
      prefix = Path.basename(audio_file, Path.extname(audio_file))

      slice_points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index(1)
      |> Enum.map(fn {[start_sample, end_sample], idx} ->
        output_file =
          Path.join(output_dir, "#{prefix}_#{String.pad_leading(to_string(idx), 3, "0")}.wav")

        start_time = start_sample / sample_rate
        duration = (end_sample - start_sample) / sample_rate

        # Extract with FFmpeg - NO FADE
        case System.cmd("ffmpeg", [
               "-ss",
               to_string(start_time),
               "-i",
               audio_file,
               "-t",
               to_string(duration),
               "-y",
               "-v",
               "quiet",
               output_file
             ]) do
          {_, 0} -> output_file
          _ -> nil
        end
      end)
      |> Enum.filter(&(&1 != nil))
      |> then(fn files -> {:ok, files} end)
    end
  end
end
