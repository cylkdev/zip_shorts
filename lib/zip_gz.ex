defmodule ZipGz do
  @moduledoc """
  `ZipGz` provides tools for creating ZIP and GZIP streams, enabling efficient handling
  of large files through streaming.

  This module is designed to work with streams, allowing you to compress data on-the-fly.
  It supports both ZIP and GZIP formats, with options for customizing compression levels
  and chunk sizes.

  ## Examples

  ### Creating a ZIP stream with a custom chunk size

      iex> entries = [%{path: "rel/path/file.txt", source: ["content"]}]
      ...> ZipGz.stream(entries, chunk_size: 10)

  ### Creating a ZIP stream with GZIP compression

      iex> text = Enum.map_join(1..10, "", fn _ -> String.duplicate("A", 1_024 * 1_024) end)
      ...> entries = [%{path: "rel/path/file.txt", source: [text]}]
      ...> ZipGz.stream(entries, chunk_size: 10, gzip: true)

  ### Streaming data from an enumerable source

      iex> stream = Stream.map(1..10, fn _ -> :crypto.strong_rand_bytes(1_024 * 1_024) end)
      ...> entries = [%{path: "rel/path/file.txt", source: stream}]
      ...> ZipGz.stream(entries)

  """

  @best_compression :best_compression
  @five_mib 5 * 1_024 * 1_024

  @doc """
  Creates a stream for compressing data into a ZIP archive, with optional GZIP compression.

  This function processes a list of entries into a ZIP stream and optionally applies
  GZIP compression. The resulting stream can be consumed to generate compressed data
  on-the-fly.

  ## Options

    * `:chunk_size` - Specifies the target size, in bytes, for each chunk of data in
      the stream (default: 5 MiB). The stream will attempt to produce chunks of at
      least this size. However, if the input data is smaller than the specified chunk
      size, the stream will emit smaller chunks to ensure all data is processed. This
      behavior ensures that no data is delayed or lost, even when the input size is
      less than the target chunk size.

    * `:gzip` - Enables GZIP compression. Accepts:

      - `true` (default): Applies GZIP with default settings.
      - `false`: Disables GZIP compression.
      - A keyword list: Customizes GZIP options (e.g., `:level` for compression level).

  ## Examples

      # Compress a single file with a chunk size of 10 bytes
      iex> entries = [%{path: "rel/path/file.txt", source: ["content"]}]
      ...> stream = ZipGz.stream(entries, chunk_size: 10)
      ...> Enum.to_list(stream)

      # Compress a large string with GZIP and a chunk size of 10 bytes
      iex> text = Enum.map_join(1..1_024, "", fn _ -> String.duplicate("A", 1_024 * 1_024) end)
      ...> entries = [%{path: "rel/path/file.txt", source: [text]}]
      ...> stream = ZipGz.stream(entries, chunk_size: 10, gzip: true)
      ...> Enum.to_list(stream)

      # Stream random data and compress it into a ZIP archive
      iex> stream = Stream.map(1..10, fn _ -> :crypto.strong_rand_bytes(1_024 * 1_024) end)
      ...> entries = [%{path: "rel/path/file.txt", source: stream}]
      ...> stream = ZipGz.stream(entries)
      ...> Enum.to_list(stream)
  """
  @spec stream(entries :: list(), opts :: keyword()) :: any()
  def stream(entries, opts \\ []) do
    entries
    |> normalize_entries()
    |> Zstream.zip()
    |> maybe_gzip_stream(opts)
    |> maybe_chunk_stream(opts)
  end

  defp maybe_chunk_stream(stream, opts) do
    case Keyword.get(opts, :chunk_size, @five_mib) do
      :infinity -> stream
      chunk_size -> ElixirUtils.Binary.chunk_stream(stream, chunk_size)
    end
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
      [to_entry(list)]
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

  defp to_entry(opts) when is_map(opts) do
    opts |> Map.to_list() |> to_entry()
  end

  defp to_entry(opts) do
    {path, o1} = Keyword.pop!(opts, :path)
    {source, o2} = Keyword.pop!(o1, :source)
    entry_opts = Keyword.put_new(o2, :coder, Zstream.Coder.Deflate)
    Zstream.entry(path, source, entry_opts)
  end
end
