defmodule Mix.Tasks.ExportAudacity do
  @moduledoc """
  Exports drum slice points to Audacity label format for visualization.

  Usage:
      mix export_audacity <audio_file> [options]

  Options:
      --threshold <float>   Detection threshold (default: 0.3)
      --min-dist <int>      Minimum distance between hits in samples (default: 20000)

  Example:
      mix export_audacity drums_section.mp3 --threshold 0.4

  This creates:
      - audacity_export/<filename>.wav (converted audio)
      - audacity_export/<filename>_chops.txt (Audacity labels)
      - audacity_export/OPEN_IN_AUDACITY.bat (Windows batch script)
  """
  use Mix.Task

  alias YoutubeAudioDl.Audio.DrumSlicerV2

  @shortdoc "Export drum slice points as Audacity labels"

  def run(args) do
    {opts, files, _} =
      OptionParser.parse(args,
        strict: [threshold: :float, min_dist: :integer],
        aliases: [t: :threshold, m: :min_dist]
      )

    case files do
      [audio_file | _] ->
        threshold = Keyword.get(opts, :threshold, 0.3)
        min_dist = Keyword.get(opts, :min_dist, 20000)

        export_for_audacity(audio_file, threshold, min_dist)

      [] ->
        IO.puts("Error: No audio file specified")
        IO.puts("\nUsage: mix export_audacity <audio_file> [--threshold 0.3] [--min-dist 20000]")
    end
  end

  defp export_for_audacity(audio_file, threshold, min_dist) do
    unless File.exists?(audio_file) do
      IO.puts("Error: File not found: #{audio_file}")
      System.halt(1)
    end

    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("  Exporting for Audacity Visualization")
    IO.puts("═══════════════════════════════════════════════════════════════\n")
    IO.puts("Audio file: #{audio_file}")
    IO.puts("Threshold: #{threshold}")
    IO.puts("Min distance: #{min_dist} samples\n")

    # Create output directory
    output_dir = "audacity_export"
    File.mkdir_p!(output_dir)

    # Step 1: Find chop points
    IO.puts("Step 1: Detecting drum hits...")

    case DrumSlicerV2.find_slice_points(audio_file, threshold, min_dist) do
      {:ok, slice_points, audio_info} ->
        IO.puts("✓ Found #{length(slice_points)} chop points\n")

        # Step 2: Convert audio to WAV if needed
        IO.puts("Step 2: Preparing audio file...")
        basename = Path.basename(audio_file, Path.extname(audio_file))
        wav_file = Path.join(output_dir, "#{basename}.wav")

        convert_to_wav(audio_file, wav_file)
        IO.puts("✓ Audio saved: #{wav_file}\n")

        # Step 3: Write Audacity labels
        IO.puts("Step 3: Creating Audacity labels...")
        label_file = Path.join(output_dir, "#{basename}_chops.txt")
        write_audacity_labels(slice_points, label_file, audio_info.sample_rate)
        IO.puts("✓ Labels saved: #{label_file}\n")

        # Step 4: Create Windows batch file
        IO.puts("Step 4: Creating batch script...")
        create_batch_script(output_dir, basename)
        IO.puts("✓ Batch script created\n")

        # Step 5: Print summary
        print_summary(output_dir, basename, slice_points, audio_info.sample_rate)

      {:error, reason} ->
        IO.puts("Error: #{reason}")
        System.halt(1)
    end
  end

  defp convert_to_wav(input_file, output_file) do
    System.cmd("ffmpeg", [
      "-i",
      input_file,
      "-y",
      "-v",
      "quiet",
      output_file
    ])
  end

  defp write_audacity_labels(slice_points, output_file, sample_rate) do
    # Audacity label format: start_time\tend_time\tlabel
    # For chop points, start and end are the same (point labels)
    labels =
      slice_points
      |> Enum.with_index(1)
      |> Enum.map(fn {sample, idx} ->
        time = sample / sample_rate
        # Format with exactly 6 decimal places
        time_str = :erlang.float_to_binary(time, decimals: 6)
        "#{time_str}\t#{time_str}\tChop#{idx}"
      end)
      |> Enum.join("\n")

    # Add final newline
    File.write!(output_file, labels <> "\n")
  end

  defp create_batch_script(output_dir, basename) do
    # Windows batch script to open in Audacity
    # Assumes Audacity is installed in default location
    batch_content = """
    @echo off
    echo Opening in Audacity...

    REM Try common Audacity install locations
    set AUDACITY="C:\\Program Files\\Audacity\\Audacity.exe"
    if not exist %AUDACITY% set AUDACITY="C:\\Program Files (x86)\\Audacity\\Audacity.exe"

    REM Get the directory where this batch file is located
    set SCRIPT_DIR=%~dp0

    REM Open audio file and labels
    %AUDACITY% "%SCRIPT_DIR%#{basename}.wav" "%SCRIPT_DIR%#{basename}_chops.txt"

    if errorlevel 1 (
        echo.
        echo ERROR: Could not find Audacity. Please install it or open these files manually:
        echo   Audio: %SCRIPT_DIR%#{basename}.wav
        echo   Labels: %SCRIPT_DIR%#{basename}_chops.txt
        echo.
        pause
    )
    """

    # Convert to Windows line endings
    batch_content = String.replace(batch_content, "\n", "\r\n")

    batch_file = Path.join(output_dir, "OPEN_IN_AUDACITY.bat")
    File.write!(batch_file, batch_content)
  end

  defp print_summary(output_dir, basename, slice_points, sample_rate) do
    # Convert WSL path to Windows path for display
    {:ok, cwd} = File.cwd()
    windows_path = convert_to_windows_path(Path.join(cwd, output_dir))

    IO.puts("═══════════════════════════════════════════════════════════════")
    IO.puts("  ✓ Export Complete!")
    IO.puts("═══════════════════════════════════════════════════════════════\n")
    IO.puts("Files created in: #{windows_path}")
    IO.puts("")
    IO.puts("📁 Files:")
    IO.puts("   • #{basename}.wav")
    IO.puts("   • #{basename}_chops.txt (#{length(slice_points)} chop points)")
    IO.puts("   • OPEN_IN_AUDACITY.bat")
    IO.puts("")
    IO.puts("📊 Chop Point Statistics:")

    if length(slice_points) > 1 do
      # Calculate average distance between chops
      distances =
        slice_points
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)

      avg_distance = Enum.sum(distances) / length(distances)
      avg_time = avg_distance / sample_rate

      IO.puts("   • Average spacing: #{:erlang.float_to_binary(avg_time * 1000, decimals: 1)}ms")
    end

    IO.puts("")
    IO.puts("🎯 To View in Audacity:")
    IO.puts("   1. Open Windows Explorer")
    IO.puts("   2. Navigate to: #{windows_path}")
    IO.puts("   3. Double-click: OPEN_IN_AUDACITY.bat")
    IO.puts("")
    IO.puts("   OR manually drag both files into Audacity:")
    IO.puts("      • #{basename}.wav")
    IO.puts("      • #{basename}_chops.txt")
    IO.puts("")
  end

  defp convert_to_windows_path(wsl_path) do
    # Convert /home/user/... to \\wsl.localhost\Ubuntu\home\user\...
    # or /mnt/c/... to C:\...
    cond do
      String.starts_with?(wsl_path, "/mnt/c/") ->
        String.replace(wsl_path, "/mnt/c/", "C:\\") |> String.replace("/", "\\")

      String.starts_with?(wsl_path, "/mnt/") ->
        drive = String.slice(wsl_path, 5, 1) |> String.upcase()
        rest = String.slice(wsl_path, 7..-1//1)
        "#{drive}:\\" <> String.replace(rest, "/", "\\")

      true ->
        # WSL path - use wsl.localhost network path
        "\\\\wsl.localhost\\Ubuntu" <> String.replace(wsl_path, "/", "\\")
    end
  end
end
