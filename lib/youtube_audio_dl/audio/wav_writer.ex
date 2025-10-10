defmodule YoutubeAudioDl.Audio.WavWriter do
  @moduledoc """
  Sample-accurate WAV file writer.

  Writes raw PCM samples directly to WAV files without going through FFmpeg.
  This ensures SAMPLE-ACCURATE slicing - no time-based rounding errors!
  """

  @doc """
  Write samples to a WAV file.

  ## Parameters
    - samples: List of floats (-1.0 to 1.0) representing the audio
    - output_file: Path to write the WAV file
    - sample_rate: Sample rate in Hz (e.g., 48000)
    - channels: Number of channels (1 = mono, 2 = stereo)
  """
  def write_wav(samples, output_file, sample_rate, channels \\ 1) do
    # Convert float samples to 16-bit PCM
    pcm_data = samples_to_pcm16(samples)

    # Build WAV file
    wav_data = build_wav(pcm_data, sample_rate, channels)

    # Write to file
    File.write!(output_file, wav_data)
    :ok
  end

  # Convert float samples (-1.0 to 1.0) to 16-bit signed integers
  defp samples_to_pcm16(samples) do
    for sample <- samples, into: <<>> do
      # Clamp to -1.0 to 1.0
      clamped = max(-1.0, min(1.0, sample))

      # Convert to 16-bit signed integer (-32768 to 32767)
      pcm_value = round(clamped * 32767)

      # Write as little-endian 16-bit integer
      <<pcm_value::little-signed-16>>
    end
  end

  # Build complete WAV file with headers
  defp build_wav(pcm_data, sample_rate, channels) do
    bits_per_sample = 16
    byte_rate = sample_rate * channels * div(bits_per_sample, 8)
    block_align = channels * div(bits_per_sample, 8)
    data_size = byte_size(pcm_data)

    # RIFF header
    riff_header = <<
      "RIFF"::binary,
      # File size - 8
      36 + data_size::little-32,
      "WAVE"::binary
    >>

    # Format chunk
    fmt_chunk = <<
      "fmt "::binary,
      # Chunk size
      16::little-32,
      # Audio format (1 = PCM)
      1::little-16,
      # Number of channels
      channels::little-16,
      # Sample rate
      sample_rate::little-32,
      # Byte rate
      byte_rate::little-32,
      # Block align
      block_align::little-16,
      # Bits per sample
      bits_per_sample::little-16
    >>

    # Data chunk
    data_chunk = <<
      "data"::binary,
      # Data size
      data_size::little-32,
      # Actual audio data
      pcm_data::binary
    >>

    # Combine all chunks
    <<riff_header::binary, fmt_chunk::binary, data_chunk::binary>>
  end

  @doc """
  Extract a slice from a waveform and write to WAV file.

  SAMPLE-ACCURATE extraction - uses exact sample positions.

  ## Parameters
    - waveform: Full waveform as list of floats
    - start_sample: Starting sample index
    - end_sample: Ending sample index
    - output_file: Output WAV file path
    - sample_rate: Sample rate in Hz
  """
  def write_slice(waveform, start_sample, end_sample, output_file, sample_rate) do
    # Extract the exact samples (SAMPLE-ACCURATE!)
    slice = Enum.slice(waveform, start_sample, end_sample - start_sample)

    # Write as WAV
    # Mono
    write_wav(slice, output_file, sample_rate, 1)
  end
end
