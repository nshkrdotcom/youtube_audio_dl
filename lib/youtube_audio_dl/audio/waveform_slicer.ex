defmodule YoutubeAudioDl.Audio.WaveformSlicer do
  @moduledoc """
  Waveform slicing module for deconstructing audio into samples at transient points.

  This module provides functionality similar to Propellerhead ReCycle, allowing you to:
  - Analyze audio files for transient events
  - Find breakpoints where audio can be sliced
  - Extract individual samples from audio loops
  - Export sliced audio segments

  ## Features

  - Transient detection using onset analysis
  - Adjustable sensitivity for detecting peaks
  - Support for mono and stereo audio
  - FFmpeg-based audio reading
  - Multiple output formats

  ## Example Usage

      # Find breakpoints in an audio file
      {:ok, breakpoints} = WaveformSlicer.find_breakpoints("downloads/drumloop.mp3", 0.5)

      # Export sliced segments
      WaveformSlicer.export_slices("downloads/drumloop.mp3", breakpoints, "output_dir")

  """

  alias YoutubeAudioDl.Audio.TransientDetector

  @doc """
  Analyzes an audio file and returns breakpoint sample numbers.

  This is the main function that implements the ReCycle-style waveform analysis.
  It reads the audio file, processes it to find transients, and returns the
  sample positions where the audio should be sliced.

  ## Parameters
    - audio_file: Path to the audio file (supports formats: mp3, wav, flac, m4a, ogg)
    - sensitivity: Threshold for transient detection (0.0 to 1.0)
                   - 0.0 = very sensitive, detects many transients
                   - 0.5 = balanced
                   - 1.0 = less sensitive, only prominent transients
    - options: Keyword list of options
      - `:mode` - Detection mode: :general or :drums (default: :general)
                  :drums uses sharp transient detection optimized for kicks/snares
      - `:min_distance` - Minimum samples between peaks (default: 4410 = ~100ms at 44.1kHz)
      - `:apply_filter` - Apply high-pass filter to emphasize transients (default: true)
      - `:normalize` - Normalize audio before processing (default: true)

  ## Returns
    - `{:ok, breakpoints}` - List of sample numbers where transients occur
    - `{:error, reason}` - If the file cannot be read or processed

  ## Examples

      iex> {:ok, breakpoints} = WaveformSlicer.find_breakpoints("drum_loop.mp3", 0.5)
      {:ok, [0, 4410, 8820, 13230, 17640]}

      # More sensitive detection (more slices)
      iex> {:ok, breakpoints} = WaveformSlicer.find_breakpoints("drum_loop.mp3", 0.2)
      {:ok, [0, 2205, 4410, 6615, 8820, ...]}

      # Less sensitive (fewer slices)
      iex> {:ok, breakpoints} = WaveformSlicer.find_breakpoints("drum_loop.mp3", 0.8)
      {:ok, [0, 8820, 17640]}
  """
  def find_breakpoints(audio_file, sensitivity \\ 0.5, options \\ []) do
    mode = Keyword.get(options, :mode, :general)
    min_distance = Keyword.get(options, :min_distance, 4410)
    apply_filter = Keyword.get(options, :apply_filter, true)
    normalize = Keyword.get(options, :normalize, true)

    # Different settings for drum detection vs general
    {window_size, hop_size} =
      case mode do
        # Small windows, high overlap for sharp transients
        :drums -> {256, 64}
        # Larger windows for general use
        _ -> {512, 256}
      end

    with {:ok, audio_info} <- read_audio_file(audio_file),
         {:ok, raw_waveform} <- extract_waveform(audio_info),
         processed_waveform <- preprocess_waveform(raw_waveform, apply_filter, normalize),
         novelty_curve <- get_novelty_curve(processed_waveform, mode, window_size),
         threshold <- TransientDetector.calculate_adaptive_threshold(novelty_curve, sensitivity),
         peaks <-
           TransientDetector.find_peaks(novelty_curve, threshold, div(min_distance, hop_size)) do
      # Map peak indices from novelty curve back to original waveform sample indices
      raw_breakpoints = Enum.map(peaks, fn {idx, _val} -> idx * hop_size end)

      # Find zero-crossings in RAW waveform (mono, unprocessed)
      zero_crossing_breakpoints =
        Enum.map(raw_breakpoints, fn position ->
          TransientDetector.find_zero_crossing(raw_waveform, position, 500)
        end)

      # Always include sample 0 as the first breakpoint if not already present
      breakpoints =
        if 0 in zero_crossing_breakpoints,
          do: zero_crossing_breakpoints,
          else: [0 | zero_crossing_breakpoints]

      {:ok, breakpoints, audio_info}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Get novelty curve based on mode
  defp get_novelty_curve(waveform, :drums, window_size) do
    TransientDetector.detect_sharp_transients(waveform, window_size)
  end

  defp get_novelty_curve(waveform, _mode, window_size) do
    TransientDetector.calculate_energy_novelty(waveform, window_size)
  end

  # Fast zero-crossing finder for stereo/mono waveforms
  # For stereo: waveform is [L, R, L, R, ...], position is in MONO frames
  defp find_zero_crossing_fast(waveform_tuple, mono_position, channels, search_range) do
    # For stereo, convert mono position to stereo sample index
    # mono_position refers to frame number, stereo index = frame * channels
    stereo_length = tuple_size(waveform_tuple)

    # Map mono frame position to stereo samples
    if channels == 2 do
      find_stereo_zero_crossing(waveform_tuple, mono_position, stereo_length, search_range)
    else
      find_mono_zero_crossing(waveform_tuple, mono_position, stereo_length, search_range)
    end
  end

  # Find zero-crossing in stereo (interleaved) waveform
  defp find_stereo_zero_crossing(waveform_tuple, mono_pos, stereo_length, search_range) do
    # Search in FRAMES, not samples (each frame = 2 samples for stereo)
    max_frames = div(stereo_length, 2) - 1
    mono_pos = max(0, min(mono_pos, max_frames))

    search_start = max(0, mono_pos - search_range)
    search_end = min(max_frames, mono_pos + search_range)

    # Search forward for a frame where BOTH channels are near zero
    fwd =
      Enum.find(mono_pos..(search_end - 1), fn frame ->
        left_idx = frame * 2
        right_idx = frame * 2 + 1
        next_left = (frame + 1) * 2
        next_right = (frame + 1) * 2 + 1

        if next_right < stereo_length do
          left = elem(waveform_tuple, left_idx)
          right = elem(waveform_tuple, right_idx)
          next_l = elem(waveform_tuple, next_left)
          next_r = elem(waveform_tuple, next_right)

          # Both channels cross zero
          left_crosses = (left >= 0 and next_l < 0) or (left < 0 and next_l >= 0)
          right_crosses = (right >= 0 and next_r < 0) or (right < 0 and next_r >= 0)

          # At least one channel crosses, and both are small
          (left_crosses or right_crosses) and abs(left) + abs(right) < 0.1
        else
          false
        end
      end)

    # Search backward
    back =
      Enum.find(mono_pos..search_start//-1, fn frame ->
        if frame > 0 do
          left_idx = frame * 2
          right_idx = frame * 2 + 1
          prev_left = (frame - 1) * 2
          prev_right = (frame - 1) * 2 + 1

          left = elem(waveform_tuple, left_idx)
          right = elem(waveform_tuple, right_idx)
          prev_l = elem(waveform_tuple, prev_left)
          prev_r = elem(waveform_tuple, prev_right)

          left_crosses = (left >= 0 and prev_l < 0) or (left < 0 and prev_l >= 0)
          right_crosses = (right >= 0 and prev_r < 0) or (right < 0 and prev_r >= 0)

          (left_crosses or right_crosses) and abs(left) + abs(right) < 0.1
        else
          false
        end
      end)

    # Return closest zero-crossing (in mono frames)
    case {fwd, back} do
      {nil, nil} ->
        mono_pos

      {nil, b} ->
        b

      {f, nil} ->
        f + 1

      {f, b} ->
        if abs(f + 1 - mono_pos) <= abs(b - mono_pos),
          do: f + 1,
          else: b
    end
  end

  # Find zero-crossing in mono waveform
  defp find_mono_zero_crossing(waveform_tuple, position, length, search_range) do
    position = max(0, min(position, length - 1))
    search_start = max(0, position - search_range)
    search_end = min(length - 1, position + search_range)

    # Search forward
    fwd =
      Enum.find(position..(search_end - 1), fn i ->
        current = elem(waveform_tuple, i)
        next = elem(waveform_tuple, i + 1)
        (current >= 0 and next < 0) or (current < 0 and next >= 0)
      end)

    # Search backward
    back =
      Enum.find(position..search_start//-1, fn i ->
        if i > 0 do
          current = elem(waveform_tuple, i)
          prev = elem(waveform_tuple, i - 1)
          (current >= 0 and prev < 0) or (current < 0 and prev >= 0)
        else
          false
        end
      end)

    # Return closest
    case {fwd, back} do
      {nil, nil} ->
        position

      {nil, b} ->
        b

      {f, nil} ->
        if f, do: f + 1, else: position

      {f, b} ->
        if abs(f + 1 - position) <= abs(b - position),
          do: f + 1,
          else: b
    end
  end

  @doc """
  Exports individual sliced segments to separate audio files.

  Takes the breakpoints found by `find_breakpoints/3` and exports each
  segment between breakpoints as a separate audio file.

  ## Parameters
    - audio_file: Path to the original audio file
    - breakpoints: List of sample numbers (from `find_breakpoints/3`)
    - output_dir: Directory where sliced files will be saved
    - options: Keyword list of options
      - `:format` - Output format (default: "wav")
      - `:prefix` - Filename prefix (default: basename of audio_file)
      - `:fade_ms` - Fade duration in milliseconds (default: 0)
                     Set to 5-10 if zero-crossing detection fails

  ## Returns
    - `{:ok, exported_files}` - List of exported file paths
    - `{:error, reason}` - If export fails

  ## Examples

      iex> {:ok, breakpoints, _info} = WaveformSlicer.find_breakpoints("loop.mp3", 0.5)
      iex> WaveformSlicer.export_slices("loop.mp3", breakpoints, "slices")
      {:ok, ["slices/loop_001.wav", "slices/loop_002.wav", ...]}

      # Export with crossfades to prevent clicks
      iex> WaveformSlicer.export_slices("loop.mp3", breakpoints, "slices", fade_ms: 10)
      {:ok, ["slices/loop_001.wav", ...]}
  """
  def export_slices(audio_file, breakpoints, output_dir, options \\ []) do
    format = Keyword.get(options, :format, "wav")
    prefix = Keyword.get(options, :prefix, Path.basename(audio_file, Path.extname(audio_file)))
    # No fade by default - rely on zero-crossing
    fade_ms = Keyword.get(options, :fade_ms, 0)

    File.mkdir_p!(output_dir)

    with {:ok, audio_info} <- read_audio_file(audio_file) do
      sample_rate = audio_info.sample_rate

      # Create pairs of consecutive breakpoints to define segments
      segments = Enum.chunk_every(breakpoints, 2, 1, :discard)

      exported_files =
        segments
        |> Enum.with_index(1)
        |> Enum.map(fn {[start_sample, end_sample], index} ->
          output_file =
            Path.join(
              output_dir,
              "#{prefix}_#{String.pad_leading(to_string(index), 3, "0")}.#{format}"
            )

          # Convert samples to time
          start_time = start_sample / sample_rate
          duration = (end_sample - start_sample) / sample_rate

          # Use FFmpeg to extract the segment with optional crossfade
          case extract_segment(audio_file, output_file, start_time, duration, fade_ms) do
            :ok -> output_file
            {:error, _} -> nil
          end
        end)
        |> Enum.filter(&(&1 != nil))

      {:ok, exported_files}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Returns information about an audio file.

  ## Parameters
    - audio_file: Path to the audio file

  ## Returns
    - `{:ok, info}` - Map containing sample_rate, duration, channels, etc.
    - `{:error, reason}` - If the file cannot be read
  """
  def get_audio_info(audio_file) do
    read_audio_file(audio_file)
  end

  # Private Functions

  # Reads audio file metadata using FFprobe
  defp read_audio_file(audio_file) do
    unless File.exists?(audio_file) do
      {:error, "File not found: #{audio_file}"}
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
          parse_ffprobe_output(output, audio_file)

        {_output, _code} ->
          {:error, "Failed to read audio file with ffprobe"}
      end
    end
  end

  # Parses FFprobe JSON output
  defp parse_ffprobe_output(output, audio_file) do
    case Jason.decode(output) do
      {:ok, data} ->
        audio_stream =
          Enum.find(data["streams"], fn stream ->
            stream["codec_type"] == "audio"
          end)

        if audio_stream do
          info = %{
            file_path: audio_file,
            sample_rate: String.to_integer(audio_stream["sample_rate"] || "44100"),
            channels: audio_stream["channels"] || 2,
            duration:
              String.to_float(audio_stream["duration"] || data["format"]["duration"] || "0"),
            codec: audio_stream["codec_name"],
            bit_rate: audio_stream["bit_rate"]
          }

          {:ok, info}
        else
          {:error, "No audio stream found in file"}
        end

      {:error, _} ->
        {:error, "Failed to parse ffprobe output"}
    end
  end

  # Extracts raw waveform data from audio file
  # Returns RAW STEREO waveform at original sample rate (for accurate zero-crossing detection)
  defp extract_waveform(audio_info) do
    audio_file = audio_info.file_path
    sample_rate = audio_info.sample_rate
    channels = audio_info.channels

    # Extract RAW MONO waveform at ORIGINAL sample rate
    # MUST be mono so sample positions match when we slice
    case System.cmd(
           "ffmpeg",
           [
             "-i",
             audio_file,
             # 32-bit float PCM, little-endian
             "-f",
             "f32le",
             # MONO - sample positions must match original
             "-ac",
             "1",
             # Keep ORIGINAL sample rate
             "-ar",
             to_string(sample_rate),
             "-v",
             "quiet",
             "pipe:1"
           ],
           stderr_to_stdout: true
         ) do
      {binary_data, 0} ->
        # Simple extraction
        samples = for <<s::float-32-little <- binary_data>>, do: s
        {:ok, samples}

      {_output, _code} ->
        {:error, "Failed to extract waveform data"}
    end
  end

  # Preprocesses the waveform (filter, normalize) - already mono from extract
  defp preprocess_waveform(waveform, apply_filter, normalize) do
    waveform
    |> then(fn w -> if normalize, do: TransientDetector.normalize_waveform(w), else: w end)
    |> then(fn w -> if apply_filter, do: TransientDetector.high_pass_filter(w, 0.95), else: w end)
  end

  # Extracts a segment from audio file using FFmpeg with optional crossfade
  defp extract_segment(input_file, output_file, start_time, duration, fade_ms) do
    fade_seconds = fade_ms / 1000.0

    # Build FFmpeg command with optional fade filters
    args =
      if fade_ms > 0 and duration > fade_seconds * 2 do
        # Only apply fade if segment is long enough (at least 2x fade duration)
        # Calculate fade-out start time (relative to segment start)
        fade_out_start = max(0.0, duration - fade_seconds)

        # Apply both fade-in and fade-out
        # Format floats to 3 decimal places to avoid precision issues
        filter =
          "afade=t=in:st=0:d=#{:erlang.float_to_binary(fade_seconds, decimals: 3)},afade=t=out:st=#{:erlang.float_to_binary(fade_out_start, decimals: 3)}:d=#{:erlang.float_to_binary(fade_seconds, decimals: 3)}"

        [
          # MUST be BEFORE -i for filters to work correctly
          "-ss",
          to_string(start_time),
          "-i",
          input_file,
          "-t",
          to_string(duration),
          # Audio filter for crossfade
          "-af",
          filter,
          # Overwrite output file
          "-y",
          "-v",
          "quiet",
          output_file
        ]
      else
        # No fade, standard extraction
        [
          # MUST be BEFORE -i
          "-ss",
          to_string(start_time),
          "-i",
          input_file,
          "-t",
          to_string(duration),
          "-y",
          "-v",
          "quiet",
          output_file
        ]
      end

    case System.cmd("ffmpeg", args) do
      {_output, 0} -> :ok
      {_output, _code} -> {:error, "Failed to extract segment"}
    end
  end
end
