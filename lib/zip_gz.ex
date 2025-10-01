defmodule ZipGz do
  @moduledoc """
  `ZipGz` provides an API for working with ZIP and GZIP streams, enabling efficient
  handling of large files.

  `ZipGz` is designed to work with streams, allowing you to compress data on-the-fly.
  It supports both ZIP and GZIP formats, with options for customizing compression
  levels and chunk sizes.

  ## Examples

  ### Creating a ZIP stream with a custom chunk size

      iex> ZipGz.stream([%{path: "rel/path/file.txt", source: ["content"]}], chunk_size: 10)

  ### Creating a ZIP stream with GZIP compression

      iex> text = Enum.map_join(1..1_024, "", fn _ -> String.duplicate("A", 1_024 * 1_024) end)
      ...> ZipGz.stream([%{path: "rel/path/file.txt", source: [text]}], chunk_size: 10)

  ### Streaming data from an enumerable source

      iex> stream = Stream.map(1..100, fn _ -> 1_024 * 1_024 |> :crypto.strong_rand_bytes() |> Base.encode64() end)
      ...> ZipGz.stream([%{path: "rel/path/file.txt", source: stream}])
  """

  @best_compression :best_compression

  # 32 MB - 549,453,824 bytes
  @thirty_two_mib 32 * 1_024 * 1_024

  @doc """
  Creates a stream for compressing data into a ZIP archive, with optional GZIP compression.

  This function processes a list of entries into a ZIP stream and optionally applies
  GZIP compression. The resulting stream can be consumed to generate compressed data
  on-the-fly.

  ## Options

    * `:chunk_size` - The maximum size of each chunk in bytes (default: 32 MiB).
    * `:gzip` - Enables GZIP compression. Accepts:
      - `true` (default): Applies GZIP with default settings.
      - `false`: Disables GZIP compression.
      - A keyword list: Customizes GZIP options (e.g., `:level` for compression level).

  ## Examples

      # Compress a single file with a chunk size of 10 bytes
      iex> ZipGz.stream([%{path: "rel/path/file.txt", source: ["content"]}], chunk_size: 10)

      # Compress a large string with GZIP and a chunk size of 10 bytes
      iex> text = Enum.map_join(1..1_024, "", fn _ -> String.duplicate("A", 1_024 * 1_024) end)
      ...> ZipGz.stream([%{path: "rel/path/file.txt", source: [text]}], chunk_size: 10)

      # Stream random data and compress it into a ZIP archive
      iex> stream = Stream.map(1..100, fn _ -> 1_024 * 1_024 |> :crypto.strong_rand_bytes() |> Base.encode64() end)
      ...> ZipGz.stream([%{path: "rel/path/file.txt", source: stream}])
  """
  @spec stream(entries :: list(), opts :: keyword()) :: any()
  def stream(entries, opts \\ []) do
    max = Keyword.get(opts, :chunk_size, @thirty_two_mib)

    entries
    |> normalize_entries()
    |> Zstream.zip()
    |> maybe_gzip_stream(opts)
    |> ZipGz.Util.content_byte_stream(max)
  end

  defp maybe_gzip_stream(stream, opts) do
    case Keyword.get(opts, :gzip, true) do
      nil -> stream
      false -> stream
      true -> StreamGzip.gzip(stream, level: @best_compression)
      gzip_opts -> StreamGzip.gzip(stream, Keyword.put_new(gzip_opts, :level, @best_compression))
    end
  end

  defp normalize_entries(list) when is_list(list) do
    if Keyword.keyword?(list) do
      [list |> Map.new() |> to_entry()]
    else
      Enum.map(list, &to_entry/1)
    end
  end

  defp normalize_entries(params) when is_map(params) and not is_struct(params) do
    [to_entry(params)]
  end

  defp normalize_entries(enum) do
    Stream.map(enum, &to_entry/1)
  end

  defp to_entry(params) do
    opts =
      params
      |> Map.get(:options, [])
      |> Keyword.put_new(:coder, Zstream.Coder.Stored)

    Zstream.entry(params.path, params.source, opts)
  end
end
