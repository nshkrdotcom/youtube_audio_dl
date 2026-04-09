defmodule YoutubeAudioDl.MixProject do
  use Mix.Project

  @source_url "https://github.com/nshkrdotcom/youtube_audio_dl"

  def project do
    [
      app: :youtube_audio_dl,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:exyt_dlp, "~> 0.1.6"},
      {:jason, "~> 1.4"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
