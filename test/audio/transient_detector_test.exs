defmodule YoutubeAudioDl.Audio.TransientDetectorTest do
  use ExUnit.Case, async: true
  alias YoutubeAudioDl.Audio.TransientDetector

  describe "calculate_novelty_curve/1" do
    test "returns empty list for empty waveform" do
      assert TransientDetector.calculate_novelty_curve([]) == []
    end

    test "first sample has zero novelty" do
      waveform = [0.5, 0.3, 0.7]
      novelty = TransientDetector.calculate_novelty_curve(waveform)
      assert hd(novelty) == 0.0
    end

    test "calculates rate of change correctly" do
      waveform = [0.0, 0.5, 0.2]
      novelty = TransientDetector.calculate_novelty_curve(waveform)

      # First sample: 0.0
      # Second sample: abs(0.5 - 0.0) = 0.5
      # Third sample: abs(0.2 - 0.5) = 0.3
      assert novelty == [0.0, 0.5, 0.3]
    end

    test "returns same length as input" do
      waveform = [0.0, 0.1, 0.2, 0.3, 0.4]
      novelty = TransientDetector.calculate_novelty_curve(waveform)
      assert length(novelty) == length(waveform)
    end
  end

  describe "high_pass_filter/2" do
    test "filters constant signal to near zero" do
      waveform = List.duplicate(0.5, 100)
      filtered = TransientDetector.high_pass_filter(waveform, 0.95)

      # After filtering, constant signal should decay to near zero
      last_values = Enum.take(filtered, -10)
      assert Enum.all?(last_values, fn v -> abs(v) < 0.1 end)
    end

    test "preserves transient peaks" do
      # Create a signal with a sharp peak
      waveform = List.duplicate(0.0, 10) ++ [0.8] ++ List.duplicate(0.0, 10)
      filtered = TransientDetector.high_pass_filter(waveform, 0.95)

      # The peak area should have significant values
      peak_area = Enum.slice(filtered, 9, 5)
      assert Enum.any?(peak_area, fn v -> abs(v) > 0.3 end)
    end
  end

  describe "find_peaks/3" do
    test "finds peaks above threshold" do
      # Create novelty curve with clear peaks
      novelty = [0.0, 0.1, 0.5, 0.1, 0.0, 0.8, 0.1, 0.0]
      peaks = TransientDetector.find_peaks(novelty, 0.3, 1)

      # Should find peaks at indices 2 (0.5) and 5 (0.8)
      peak_indices = Enum.map(peaks, fn {idx, _val} -> idx end)
      assert 2 in peak_indices
      assert 5 in peak_indices
    end

    test "respects minimum threshold" do
      novelty = [0.0, 0.1, 0.2, 0.1, 0.0]

      # With high threshold, should find no peaks
      peaks_high = TransientDetector.find_peaks(novelty, 0.5, 1)
      assert peaks_high == []

      # With low threshold, should find peak at index 2
      peaks_low = TransientDetector.find_peaks(novelty, 0.1, 1)
      assert length(peaks_low) > 0
    end

    test "respects minimum distance between peaks" do
      # Create peaks close together
      novelty = [0.0, 0.5, 0.0, 0.5, 0.0, 0.5, 0.0]

      # With min_distance = 1, should find multiple peaks
      peaks_close = TransientDetector.find_peaks(novelty, 0.3, 1)
      assert length(peaks_close) >= 2

      # With min_distance = 3, should find fewer peaks
      peaks_far = TransientDetector.find_peaks(novelty, 0.3, 3)
      assert length(peaks_far) < length(peaks_close)
    end

    test "returns peaks with their values" do
      novelty = [0.0, 0.1, 0.7, 0.1, 0.0]
      peaks = TransientDetector.find_peaks(novelty, 0.5, 1)

      assert length(peaks) == 1
      assert {2, 0.7} in peaks
    end
  end

  describe "normalize_waveform/1" do
    test "normalizes to peak of 1.0" do
      waveform = [0.0, 0.25, -0.5, 0.3, -0.4]
      normalized = TransientDetector.normalize_waveform(waveform)

      max_value = Enum.max_by(normalized, &abs/1) |> abs()
      assert_in_delta max_value, 1.0, 0.001
    end

    test "preserves relative amplitudes" do
      waveform = [0.0, 0.5, 1.0]
      normalized = TransientDetector.normalize_waveform(waveform)

      # Ratios should be preserved
      assert_in_delta Enum.at(normalized, 1) / Enum.at(normalized, 2), 0.5, 0.001
    end

    test "handles all-zero waveform" do
      waveform = [0.0, 0.0, 0.0]
      normalized = TransientDetector.normalize_waveform(waveform)
      assert normalized == waveform
    end
  end

  describe "stereo_to_mono/2" do
    test "averages left and right channels" do
      left = [1.0, 0.5, 0.0]
      right = [0.0, 0.5, 1.0]
      mono = TransientDetector.stereo_to_mono(left, right)

      assert mono == [0.5, 0.5, 0.5]
    end

    test "handles different channel values" do
      left = [0.8, 0.2]
      right = [0.2, 0.8]
      mono = TransientDetector.stereo_to_mono(left, right)

      assert_in_delta Enum.at(mono, 0), 0.5, 0.001
      assert_in_delta Enum.at(mono, 1), 0.5, 0.001
    end
  end

  describe "calculate_adaptive_threshold/2" do
    test "returns higher threshold for higher sensitivity" do
      novelty = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]

      threshold_low = TransientDetector.calculate_adaptive_threshold(novelty, 0.2)
      threshold_high = TransientDetector.calculate_adaptive_threshold(novelty, 0.8)

      assert threshold_high > threshold_low
    end

    test "returns positive threshold" do
      novelty = [0.0, 0.1, 0.2, 0.1, 0.0]
      threshold = TransientDetector.calculate_adaptive_threshold(novelty, 0.5)

      assert threshold > 0
    end

    test "adapts to signal characteristics" do
      # Quiet signal
      quiet_novelty = [0.01, 0.02, 0.01, 0.02, 0.01]
      quiet_threshold = TransientDetector.calculate_adaptive_threshold(quiet_novelty, 0.5)

      # Loud signal
      loud_novelty = [0.5, 0.6, 0.7, 0.6, 0.5]
      loud_threshold = TransientDetector.calculate_adaptive_threshold(loud_novelty, 0.5)

      # Loud signal should have higher threshold
      assert loud_threshold > quiet_threshold
    end
  end
end
