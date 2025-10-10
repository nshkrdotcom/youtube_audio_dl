defmodule YoutubeAudioDl.Audio.TransientDetector do
  @moduledoc """
  Transient detection module for identifying onset points in audio waveforms.

  This module implements algorithms to detect sudden changes (transients) in audio signals,
  such as drum hits, note onsets, and other percussive events. Similar to the classic
  Propellerhead ReCycle software, it finds breakpoints where audio can be sliced.
  """

  @doc """
  Detects SHARP transients (drums, kicks, snares) using attack slope analysis.

  This method is optimized for detecting percussive events with fast attacks.
  Uses small windows, calculates attack speed, NO SMOOTHING.

  ## Parameters
    - waveform: List of audio samples (floats between -1.0 and 1.0)
    - window_size: Size of energy calculation window (default: 256 samples = ~5.8ms at 44.1kHz)

  ## Returns
    - List of {attack_slope, energy} tuples for peak detection

  ## Examples

      iex> waveform = [0.0, 0.1, 0.8, 0.2, 0.0]
      iex> slopes = TransientDetector.detect_sharp_transients(waveform)
      iex> length(slopes) > 0
      true
  """
  def detect_sharp_transients(waveform, window_size \\ 256) do
    # 75% overlap for precision
    hop_size = div(window_size, 4)

    # Calculate energy for each window
    energy_curve =
      waveform
      |> Enum.chunk_every(window_size, hop_size, :discard)
      |> Enum.map(fn window ->
        # RMS energy (root mean square)
        sum_squares =
          Enum.reduce(window, 0.0, fn sample, acc ->
            acc + sample * sample
          end)

        :math.sqrt(sum_squares / length(window))
      end)

    # Calculate ATTACK SLOPE (rate of energy increase)
    # This is the KEY to detecting sharp drum hits
    {attack_slopes, _} =
      Enum.reduce(energy_curve, {[], 0.0}, fn current_energy, {slopes, prev_energy} ->
        # Only positive slopes (attacks), ignore decay
        slope = max(current_energy - prev_energy, 0.0)
        {[slope | slopes], current_energy}
      end)

    Enum.reverse(attack_slopes)
  end

  @doc """
  Calculates an energy-based novelty curve from waveform data (general purpose).

  Uses windowed energy difference for better transient detection.
  This method is more robust than simple amplitude difference.
  For DRUM detection, use `detect_sharp_transients/2` instead.

  ## Parameters
    - waveform: List of audio samples (floats between -1.0 and 1.0)
    - window_size: Size of energy calculation window (default: 512 samples)

  ## Returns
    - List of novelty values
  """
  def calculate_energy_novelty(waveform, window_size \\ 512) do
    half_window = div(window_size, 2)

    waveform
    |> Enum.chunk_every(window_size, half_window, :discard)
    |> Enum.map(fn window ->
      # Calculate energy of window (sum of squares)
      Enum.reduce(window, 0.0, fn sample, acc ->
        acc + sample * sample
      end) / length(window)
    end)
    |> calculate_simple_novelty()
    # Smooth to reduce noise
    |> smooth_curve(3)
  end

  @doc """
  Calculates a simple novelty curve from waveform data (legacy method).

  The novelty curve represents the rate of change in the audio signal.
  For better results, use `calculate_energy_novelty/2`.

  ## Parameters
    - waveform: List of audio samples (floats between -1.0 and 1.0)

  ## Returns
    - List of novelty values, same length as input waveform
  """
  def calculate_novelty_curve([]), do: []

  def calculate_novelty_curve([first | rest]) do
    # First sample has no previous sample, so novelty is 0
    {novelty_curve, _} =
      Enum.reduce(rest, {[0.0], first}, fn current_sample, {curve, prev_sample} ->
        # Calculate the absolute difference (rate of change)
        novelty = abs(current_sample - prev_sample)
        {[novelty | curve], current_sample}
      end)

    Enum.reverse(novelty_curve)
  end

  # Calculates rate of change from energy values
  defp calculate_simple_novelty([]), do: []

  defp calculate_simple_novelty([first | rest]) do
    {novelty, _} =
      Enum.reduce(rest, {[0.0], first}, fn current, {acc, prev} ->
        # Only positive changes (onsets)
        diff = max(current - prev, 0.0)
        {[diff | acc], current}
      end)

    Enum.reverse(novelty)
  end

  # Smooths a curve using moving average
  defp smooth_curve(curve, window_size) when window_size > 0 do
    if length(curve) < window_size do
      curve
    else
      curve
      |> Enum.chunk_every(window_size, 1, :discard)
      |> Enum.map(fn window ->
        Enum.sum(window) / length(window)
      end)
    end
  end

  @doc """
  Applies a simple high-pass filter to emphasize transients.

  This filter removes low-frequency content and emphasizes the sharp attacks
  of transient events.

  ## Parameters
    - waveform: List of audio samples
    - alpha: Filter coefficient (0.0 to 1.0), higher values = more filtering

  ## Returns
    - Filtered waveform
  """
  def high_pass_filter(waveform, alpha \\ 0.95) do
    {filtered, _, _} =
      Enum.reduce(waveform, {[], 0.0, 0.0}, fn sample, {result, prev_sample, prev_filtered} ->
        # Simple high-pass filter formula
        filtered_sample = alpha * (prev_filtered + sample - prev_sample)
        {[filtered_sample | result], sample, filtered_sample}
      end)

    Enum.reverse(filtered)
  end

  @doc """
  Finds peaks in the novelty curve above a minimum threshold.

  A peak is defined as a point where the value is higher than both
  its neighbors and exceeds the minimum threshold.

  ## Parameters
    - novelty_curve: List of novelty values
    - min_threshold: Minimum value to be considered a peak (0.0 to 1.0)
    - min_distance: Minimum number of samples between peaks (default: 4410, ~100ms at 44.1kHz)

  ## Returns
    - List of tuples: {sample_index, peak_value}

  ## Examples

      iex> novelty = [0.0, 0.1, 0.5, 0.1, 0.0, 0.8, 0.1]
      iex> peaks = TransientDetector.find_peaks(novelty, 0.3, 1)
      iex> Enum.map(peaks, fn {idx, _val} -> idx end)
      [2, 5]
  """
  def find_peaks(novelty_curve, min_threshold \\ 0.1, min_distance \\ 4410) do
    novelty_curve
    |> Enum.with_index()
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.reduce([], fn chunk, peaks ->
      case chunk do
        # Check if middle element is a peak
        [{prev_val, _}, {current_val, current_idx}, {next_val, _}] ->
          if current_val > prev_val and current_val > next_val and current_val > min_threshold do
            # Check minimum distance from previous peak
            case peaks do
              [] ->
                [{current_idx, current_val} | peaks]

              [{last_idx, _} | _] when current_idx - last_idx >= min_distance ->
                [{current_idx, current_val} | peaks]

              _ ->
                peaks
            end
          else
            peaks
          end

        _ ->
          peaks
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Calculates the adaptive threshold for peak detection.

  Uses the median and median absolute deviation (MAD) of the novelty curve
  to automatically determine an appropriate threshold.

  ## Parameters
    - novelty_curve: List of novelty values
    - sensitivity: Multiplier for the threshold (0.0 to 1.0)
                   Lower values = more peaks detected
                   Higher values = fewer, more prominent peaks

  ## Returns
    - Threshold value
  """
  def calculate_adaptive_threshold(novelty_curve, sensitivity \\ 0.5) do
    sorted = Enum.sort(novelty_curve)
    max_val = List.last(sorted) || 1.0

    # Use percentile-based threshold
    # Lower sensitivity = lower percentile = more peaks detected
    # Higher sensitivity = higher percentile = fewer peaks
    # Range: 50-90th percentile
    percentile_value = 50 + sensitivity * 40
    threshold = percentile(sorted, trunc(percentile_value))

    # Ensure threshold is reasonable relative to the data
    # At least 10% of max value for very sensitive, up to 50% for less sensitive
    min_threshold = max_val * (0.1 + sensitivity * 0.4)
    max(threshold, min_threshold)
  end

  @doc """
  Converts mono waveform to normalized samples.

  Normalizes the audio so the peak amplitude is 1.0.

  ## Parameters
    - waveform: List of audio samples

  ## Returns
    - Normalized waveform
  """
  def normalize_waveform(waveform) do
    max_amplitude =
      waveform
      |> Enum.map(&abs/1)
      |> Enum.max(fn -> 1.0 end)

    if max_amplitude > 0 do
      Enum.map(waveform, fn sample -> sample / max_amplitude end)
    else
      waveform
    end
  end

  @doc """
  Converts stereo waveform to mono by averaging channels.

  ## Parameters
    - left_channel: List of left channel samples
    - right_channel: List of right channel samples

  ## Returns
    - Mono waveform
  """
  def stereo_to_mono(left_channel, right_channel) do
    Enum.zip(left_channel, right_channel)
    |> Enum.map(fn {left, right} -> (left + right) / 2.0 end)
  end

  @doc """
  Finds the nearest zero-crossing point near a given sample position.

  This prevents clicks/pops by ensuring cuts happen where the waveform crosses zero,
  not at peak energy points. Essential for clean audio slicing.

  ## Parameters
    - waveform: List of audio samples
    - position: Target sample position
    - search_range: How many samples to search forward/backward (default: 500)

  ## Returns
    - Sample index of nearest zero crossing, or original position if none found

  ## Examples

      iex> waveform = [0.5, 0.3, 0.1, -0.1, -0.3]  # Zero crossing at index 3
      iex> TransientDetector.find_zero_crossing(waveform, 2, 5)
      3
  """
  def find_zero_crossing(waveform, position, search_range \\ 500) do
    waveform_length = length(waveform)

    # Clamp position to valid range
    position = max(0, min(position, waveform_length - 1))

    # OPTIMIZATION: Convert to tuple for O(1) access instead of O(n) Enum.at()
    waveform_tuple = List.to_tuple(waveform)

    # Define search boundaries
    search_start = max(0, position - search_range)
    search_end = min(waveform_length - 1, position + search_range)

    # Search for zero crossings in both directions
    forward_crossing = find_crossing_forward_fast(waveform_tuple, position, search_end)
    backward_crossing = find_crossing_backward_fast(waveform_tuple, position, search_start)

    # Return the closest zero crossing
    case {forward_crossing, backward_crossing} do
      {nil, nil} ->
        # No zero crossing found, use original
        position

      {nil, back} ->
        back

      {fwd, nil} ->
        fwd

      {fwd, back} ->
        # Choose the closest one
        fwd_dist = abs(fwd - position)
        back_dist = abs(back - position)
        if fwd_dist <= back_dist, do: fwd, else: back
    end
  end

  # Fast forward search using tuple access
  defp find_crossing_forward_fast(waveform_tuple, start_pos, end_pos) do
    Enum.find(start_pos..(end_pos - 1), fn i ->
      current = elem(waveform_tuple, i)
      next = elem(waveform_tuple, i + 1)

      # Check for sign change (zero crossing)
      (current >= 0 and next < 0) or (current < 0 and next >= 0)
    end)
    |> case do
      nil -> nil
      # Return the point after crossing
      idx -> idx + 1
    end
  end

  # Fast backward search using tuple access
  defp find_crossing_backward_fast(waveform_tuple, start_pos, end_pos) do
    Enum.find(start_pos..end_pos//-1, fn i ->
      if i > 0 do
        current = elem(waveform_tuple, i)
        prev = elem(waveform_tuple, i - 1)

        # Check for sign change
        (current >= 0 and prev < 0) or (current < 0 and prev >= 0)
      else
        false
      end
    end)
  end

  # Private helper to calculate percentile
  defp percentile(sorted_list, percent) when percent >= 0 and percent <= 100 do
    len = length(sorted_list)

    if len == 0 do
      0.0
    else
      index = trunc(len * percent / 100)
      index = min(index, len - 1)
      Enum.at(sorted_list, index)
    end
  end
end
