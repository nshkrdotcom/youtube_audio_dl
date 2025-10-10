defmodule YoutubeAudioDl.Audio.DrumSlicerV2 do
  @moduledoc """
  High-precision drum slicer using HFC analysis and attack slope detection.

  Stage 1: Find sharp attacks (staccato sounds)
    - Analyze high-frequency content in windowed frames
    - Calculate attack slope (rate of energy increase)
    - Only keep STEEP slopes (drum hits)

  Stage 2: Find zero-crossing to the LEFT of each peak
    - Search backward for sign change
    - This is the chop point
  """

  @doc """
  Find drum slice points in audio.

  Can be called with:
    - find_slice_points(file, options) - keyword list
    - find_slice_points(file, threshold, min_distance) - direct args
  """
  def find_slice_points(audio_file, threshold_or_opts \\ [], min_distance \\ nil)

  def find_slice_points(audio_file, threshold, min_distance)
      when is_number(threshold) and is_number(min_distance) do
    options = [slope_threshold: threshold, min_distance: min_distance]
    find_slice_points(audio_file, options, nil)
  end

  def find_slice_points(audio_file, options, _) when is_list(options) do
    # Frame size for HFC analysis (small windows to catch fast attacks)
    # ~10.7ms at 48kHz
    frame_size = Keyword.get(options, :frame_size, 512)
    # 50% overlap
    hop_size = Keyword.get(options, :hop_size, 256)

    # Attack slope threshold - higher = only sharp hits
    slope_threshold = Keyword.get(options, :slope_threshold, 0.01)

    # Minimum distance between hits
    # ~230ms at 48kHz
    min_distance = Keyword.get(options, :min_distance, 11025)

    with {:ok, audio_info} <- get_audio_info(audio_file),
         {:ok, waveform} <- extract_mono_waveform(audio_info) do
      # STAGE 1: Find sharp attacks
      hfc_curve = calculate_hfc_curve(waveform, frame_size, hop_size)
      attack_slopes = calculate_attack_slope(hfc_curve)
      peak_frames = find_steep_peaks(attack_slopes, slope_threshold, div(min_distance, hop_size))

      # Convert frame indices to sample positions
      peak_samples = Enum.map(peak_frames, fn frame_idx -> frame_idx * hop_size end)

      # STAGE 2: Find zero-crossings to the LEFT
      waveform_tuple = List.to_tuple(waveform)

      slice_points =
        Enum.map(peak_samples, fn sample_pos ->
          find_zero_crossing_left(waveform_tuple, sample_pos)
        end)

      # Always start at 0
      slice_points = [0 | slice_points] |> Enum.uniq() |> Enum.sort()

      {:ok, slice_points, audio_info}
    end
  end

  # Calculate High-Frequency Content for each frame
  # Drums have bursts of high-frequency energy at the attack
  defp calculate_hfc_curve(waveform, frame_size, hop_size) do
    waveform
    |> frame_audio(frame_size, hop_size)
    |> Enum.map(fn frame ->
      # HFC = sum of (magnitude * frequency_bin)
      # Higher frequencies weighted more heavily
      frame
      |> Enum.with_index()
      |> Enum.reduce(0.0, fn {sample, idx}, acc ->
        # Weight by frequency (higher index = higher freq)
        weight = (idx + 1) / frame_size
        acc + abs(sample) * weight
      end)
    end)
  end

  # Split waveform into overlapping frames (optimized)
  defp frame_audio(waveform, frame_size, hop_size) do
    # Convert to tuple for fast random access
    waveform_tuple = List.to_tuple(waveform)
    total_samples = tuple_size(waveform_tuple)

    # Calculate number of frames
    num_frames = div(total_samples - frame_size, hop_size) + 1

    # Extract frames using tuple access
    for frame_idx <- 0..(num_frames - 1) do
      start_idx = frame_idx * hop_size
      for i <- 0..(frame_size - 1), do: elem(waveform_tuple, start_idx + i)
    end
  end

  # Calculate attack slope (rate of increase in HFC)
  # Sharp drum hits = STEEP slope
  defp calculate_attack_slope(hfc_curve) do
    hfc_curve
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [prev, curr] ->
      # Only positive changes (attacks, not decays)
      max(curr - prev, 0.0)
    end)
  end

  # Find peaks in attack slope curve with minimum distance
  defp find_steep_peaks(slopes, threshold, min_distance_frames) do
    find_peaks_recursive(slopes, threshold, min_distance_frames, 1, [], 0)
    |> Enum.reverse()
  end

  defp find_peaks_recursive([prev, curr, next | rest], threshold, min_dist, idx, acc, last_peak) do
    # Peak: higher than neighbors, above threshold, far enough from last peak
    is_peak = curr > prev and curr > next
    is_steep = curr > threshold
    far_enough = idx - last_peak >= min_dist

    if is_peak and is_steep and far_enough do
      find_peaks_recursive([curr, next | rest], threshold, min_dist, idx + 1, [idx | acc], idx)
    else
      find_peaks_recursive([curr, next | rest], threshold, min_dist, idx + 1, acc, last_peak)
    end
  end

  defp find_peaks_recursive(_, _, _, _, acc, _), do: acc

  # Find nearest zero-crossing (search BOTH directions, pick closest)
  defp find_zero_crossing_left(_waveform_tuple, position) when position <= 0, do: 0

  defp find_zero_crossing_left(waveform_tuple, position) do
    max_len = tuple_size(waveform_tuple)
    # ~500ms at 48kHz - search MUCH further!
    search_range = 24000

    # Search backward
    back_start = max(0, position - search_range)
    backward_zc = search_backward(waveform_tuple, position, position - back_start)

    # Search forward
    fwd_end = min(max_len - 1, position + search_range)
    forward_zc = search_forward(waveform_tuple, position, fwd_end)

    # Pick closest to original position
    case {backward_zc, forward_zc} do
      {nil, nil} ->
        position

      {nil, fwd} ->
        fwd

      {back, nil} ->
        back

      {back, fwd} ->
        back_dist = position - back
        fwd_dist = fwd - position
        if back_dist <= fwd_dist, do: back, else: fwd
    end
  end

  # Search backward for zero-crossing
  defp search_backward(_waveform_tuple, idx, 0), do: nil
  defp search_backward(_waveform_tuple, 0, _), do: 0

  defp search_backward(waveform_tuple, idx, remaining) when idx > 0 do
    current = elem(waveform_tuple, idx)
    prev = elem(waveform_tuple, idx - 1)

    if (current >= 0 and prev < 0) or (current < 0 and prev >= 0) do
      idx
    else
      search_backward(waveform_tuple, idx - 1, remaining - 1)
    end
  end

  defp search_backward(_, _, _), do: nil

  # Search forward for zero-crossing
  defp search_forward(waveform_tuple, idx, end_idx) when idx >= end_idx, do: nil

  defp search_forward(waveform_tuple, idx, end_idx) do
    max_len = tuple_size(waveform_tuple)

    if idx + 1 >= max_len do
      nil
    else
      current = elem(waveform_tuple, idx)
      next = elem(waveform_tuple, idx + 1)

      if (current >= 0 and next < 0) or (current < 0 and next >= 0) do
        idx + 1
      else
        search_forward(waveform_tuple, idx + 1, end_idx)
      end
    end
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

  # Extract mono waveform at original sample rate
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
  Export slices to separate WAV files using SAMPLE-ACCURATE extraction.

  This extracts slices directly from the waveform using exact sample positions,
  ensuring zero-crossings are preserved perfectly.
  """
  def export_slices(audio_file, slice_points, output_dir) do
    File.mkdir_p!(output_dir)

    with {:ok, audio_info} <- get_audio_info(audio_file),
         {:ok, waveform} <- extract_mono_waveform(audio_info) do
      sample_rate = audio_info.sample_rate
      prefix = Path.basename(audio_file, Path.extname(audio_file))

      # SAMPLE-ACCURATE export using WavWriter
      files =
        slice_points
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.with_index(1)
        |> Enum.map(fn {[start_sample, end_sample], idx} ->
          output_file =
            Path.join(output_dir, "#{prefix}_#{String.pad_leading(to_string(idx), 3, "0")}.wav")

          # Write directly from waveform - SAMPLE-ACCURATE!
          case YoutubeAudioDl.Audio.WavWriter.write_slice(
                 waveform,
                 start_sample,
                 end_sample,
                 output_file,
                 sample_rate
               ) do
            :ok -> output_file
            _ -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      {:ok, files}
    end
  end
end
