alias YoutubeAudioDl.Audio.WaveformSlicer

IO.puts("""
═══════════════════════════════════════════════════════════════
  ReCycle-Style Parameters Demo
═══════════════════════════════════════════════════════════════

Our implementation has 4 main parameters, similar to ReCycle:

1. SENSITIVITY (0.0 - 1.0)
   - Like ReCycle's "Sensitivity" slider
   - 0.0 = Very sensitive (many slices, detects subtle transients)
   - 0.5 = Balanced (medium number of slices)
   - 1.0 = Less sensitive (fewer slices, only prominent hits)

2. MIN_DISTANCE (samples)
   - Like ReCycle's "Resolution" setting
   - Minimum time between slices (prevents over-slicing)
   - 4410 samples = ~100ms at 44.1kHz
   - 22050 samples = ~500ms at 44.1kHz

3. APPLY_FILTER (true/false)
   - Like ReCycle's "HiQ" mode
   - Applies high-pass filter to emphasize transients
   - Removes low-frequency content for better detection

4. NORMALIZE (true/false)
   - Like ReCycle's "Auto Gain"
   - Normalizes audio before processing
   - Ensures consistent detection across different levels

═══════════════════════════════════════════════════════════════
""")

audio_file = "test_10sec.mp3"

# Demo 1: SENSITIVITY Parameter
IO.puts("\n📊 DEMO 1: SENSITIVITY Parameter (like ReCycle's Sensitivity slider)")
IO.puts("─────────────────────────────────────────────────────────────────\n")

Enum.each([0.2, 0.5, 0.8], fn sens ->
  {:ok, breakpoints, _} =
    WaveformSlicer.find_breakpoints(
      audio_file,
      sens,
      min_distance: 10000
    )

  IO.puts(
    "  Sensitivity #{sens}: #{String.pad_leading(to_string(length(breakpoints)), 3)} slices"
  )
end)

# Demo 2: MIN_DISTANCE Parameter
IO.puts("\n\n📊 DEMO 2: MIN_DISTANCE Parameter (like ReCycle's Resolution)")
IO.puts("─────────────────────────────────────────────────────────────────\n")

Enum.each(
  [
    {2205, "~50ms"},
    {4410, "~100ms"},
    {8820, "~200ms"},
    {22050, "~500ms"}
  ],
  fn {min_dist, time_desc} ->
    {:ok, breakpoints, _} =
      WaveformSlicer.find_breakpoints(
        audio_file,
        0.5,
        min_distance: min_dist
      )

    IO.puts(
      "  Min distance #{String.pad_leading(time_desc, 6)}: #{String.pad_leading(to_string(length(breakpoints)), 3)} slices"
    )
  end
)

# Demo 3: FILTER Parameter
IO.puts("\n\n📊 DEMO 3: APPLY_FILTER Parameter (like ReCycle's HiQ mode)")
IO.puts("─────────────────────────────────────────────────────────────────\n")

{:ok, breakpoints_no_filter, _} =
  WaveformSlicer.find_breakpoints(
    audio_file,
    0.5,
    min_distance: 10000,
    apply_filter: false
  )

{:ok, breakpoints_with_filter, _} =
  WaveformSlicer.find_breakpoints(
    audio_file,
    0.5,
    min_distance: 10000,
    apply_filter: true
  )

IO.puts("  Without high-pass filter: #{length(breakpoints_no_filter)} slices")
IO.puts("  With high-pass filter:    #{length(breakpoints_with_filter)} slices")

# Demo 4: Combined Parameters
IO.puts("\n\n📊 DEMO 4: COMBINED Parameters (like ReCycle workflow)")
IO.puts("─────────────────────────────────────────────────────────────────\n")

IO.puts("  Tight slicing (for detailed editing):")

{:ok, bp1, _} =
  WaveformSlicer.find_breakpoints(
    audio_file,
    0.2,
    min_distance: 4410,
    apply_filter: true,
    normalize: true
  )

IO.puts("    sensitivity: 0.2, min_distance: 100ms → #{length(bp1)} slices\n")

IO.puts("  Standard slicing (balanced):")

{:ok, bp2, _} =
  WaveformSlicer.find_breakpoints(
    audio_file,
    0.5,
    min_distance: 8820,
    apply_filter: true,
    normalize: true
  )

IO.puts("    sensitivity: 0.5, min_distance: 200ms → #{length(bp2)} slices\n")

IO.puts("  Loose slicing (major hits only):")

{:ok, bp3, _} =
  WaveformSlicer.find_breakpoints(
    audio_file,
    0.8,
    min_distance: 22050,
    apply_filter: true,
    normalize: true
  )

IO.puts("    sensitivity: 0.8, min_distance: 500ms → #{length(bp3)} slices\n")

IO.puts("""

═══════════════════════════════════════════════════════════════
  Usage Examples
═══════════════════════════════════════════════════════════════

# Basic usage (ReCycle defaults)
{:ok, breakpoints, _info} = WaveformSlicer.find_breakpoints(
  "loop.mp3",
  0.5  # sensitivity
)

# Advanced usage (all parameters)
{:ok, breakpoints, _info} = WaveformSlicer.find_breakpoints(
  "loop.mp3",
  0.3,  # sensitivity: more sensitive
  min_distance: 8820,      # ~200ms minimum between slices
  apply_filter: true,      # use high-pass filter
  normalize: true          # normalize levels
)

# Export slices
WaveformSlicer.export_slices("loop.mp3", breakpoints, "slices")

═══════════════════════════════════════════════════════════════
""")
