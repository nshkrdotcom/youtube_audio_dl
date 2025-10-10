#!/usr/bin/env python3
"""
ML-Based Chop Point Detection using Madmom RNN
Uses pre-trained neural network for onset detection - NO GPU REQUIRED
"""

import sys
import madmom
from madmom.features.onsets import RNNOnsetProcessor, OnsetPeakPickingProcessor

def detect_chops(audio_file, threshold=0.5, output_file="chops_ml.txt"):
    """
    Detect chop points using pre-trained RNN onset detector.

    Args:
        audio_file: Path to WAV file
        threshold: Onset activation threshold (0.0-1.0, default 0.5)
                  Lower = more sensitive, more chops
                  Higher = less sensitive, fewer chops
        output_file: Output file for Audacity labels

    Returns:
        List of onset times in seconds
    """

    print("=" * 60)
    print("ML-BASED CHOP DETECTOR (Madmom RNN)")
    print("=" * 60)
    print(f"Input: {audio_file}")
    print(f"Threshold: {threshold}")
    print()

    # Stage 1: RNN onset activation function
    print("Stage 1: Running neural network onset detection...")
    processor = RNNOnsetProcessor()
    activations = processor(audio_file)
    print(f"✓ Generated {len(activations)} activation frames\n")

    # Stage 2: Peak picking from activation function
    print("Stage 2: Picking peaks from activation function...")
    peak_picker = OnsetPeakPickingProcessor(
        threshold=threshold,
        smooth=0.05,  # Smoothing window (seconds)
        fps=100,      # Frames per second
        pre_max=0.03, # Pre-max window (seconds)
        post_max=0.03 # Post-max window (seconds)
    )
    onsets = peak_picker(activations)
    print(f"✓ Found {len(onsets)} onset peaks\n")

    # Display results
    print("=" * 60)
    print("DETECTED CHOP POINTS")
    print("=" * 60)
    print()

    for i, onset_time in enumerate(onsets[:20], 1):
        print(f"  {i:3d}. {onset_time:8.3f} seconds")

    if len(onsets) > 20:
        print(f"  ... and {len(onsets) - 20} more")

    print()

    # Calculate average spacing
    if len(onsets) > 1:
        spacings = [onsets[i+1] - onsets[i] for i in range(len(onsets)-1)]
        avg_spacing = sum(spacings) / len(spacings)
        print(f"Average spacing: {avg_spacing*1000:.1f} ms")
        print()

    # Export to Audacity label format
    with open(output_file, 'w') as f:
        for i, onset_time in enumerate(onsets, 1):
            f.write(f"{onset_time:.6f}\t{onset_time:.6f}\tChop{i}\n")

    print(f"✓ Exported {len(onsets)} chop points to: {output_file}")
    print("  Import in Audacity: File → Import → Labels")
    print()

    return onsets

def main():
    if len(sys.argv) < 2:
        print("Usage: python chop_ml.py <audio.wav> [threshold] [output.txt]")
        print()
        print("Examples:")
        print("  python chop_ml.py drums.wav")
        print("  python chop_ml.py drums.wav 0.3          # More sensitive")
        print("  python chop_ml.py drums.wav 0.7          # Less sensitive")
        print("  python chop_ml.py drums.wav 0.5 out.txt  # Custom output")
        print()
        print("Threshold guide:")
        print("  0.3 = Very sensitive (many chops)")
        print("  0.5 = Balanced (recommended)")
        print("  0.7 = Conservative (major hits only)")
        sys.exit(1)

    audio_file = sys.argv[1]
    threshold = float(sys.argv[2]) if len(sys.argv) > 2 else 0.5
    output_file = sys.argv[3] if len(sys.argv) > 3 else "chops_ml.txt"

    onsets = detect_chops(audio_file, threshold, output_file)

    print("=" * 60)
    print("DONE!")
    print("=" * 60)

if __name__ == '__main__':
    main()
