defmodule ZipShorts do
  @best_compression :best_compression
  @sixty_four_mebibytes 64 * 1024 * 1024

  @default_gzip_options [level: @best_compression]

  @doc """
  Builds a zip file from the given entries and writes it to the specified path.

  ## Examples

      iex> [%{path: "examples/hello_world.txt", source: ["Hello world!"]}]
      ...> |> ZipShorts.Zip.stream()
      ...> |> ZipShorts.write_zip("example.zip")

      iex> [%{path: "examples/hello_world.txt", source: ["Hello world!"]}]
      ...> |> ZipShorts.Zip.stream()
      ...> |> ZipShorts.write_zip("example.zip", segment: true)
  """
  def write_zip(entries, path, opts \\ []) do
    if opts[:segment] do
      entries
      |> stream_zip(opts)
      |> file_segmented_write(path, opts)
    else
      entries
      |> stream_zip(opts)
      |> file_write(path, opts)
    end
  end

  defp file_write(source, path, opts) do
    priv_dir = Path.expand("priv/", File.cwd!())
    cwd = Keyword.get(opts, :cwd, priv_dir)
    abs_path = cwd |> Path.join(path) |> abs_path()

    File.mkdir_p!(Path.dirname(abs_path))

    out = source |> Enum.to_list() |> :erlang.iolist_to_binary()

    File.write!(abs_path, out, [:binary, {:delayed_write, 64_000, 20}])
  end

  defp file_segmented_write(source, path, opts) do
    priv_dir = Path.expand("priv/", File.cwd!())
    cwd = Keyword.get(opts, :cwd, priv_dir)
    abs_path = cwd |> Path.join(path) |> abs_path()

    File.mkdir_p!(Path.dirname(abs_path))

    async_opts =
      opts
      |> Keyword.put_new(:max_concurrency, 10)
      |> Keyword.put_new(:ordered, false)

    source
    |> Stream.with_index()
    |> Stream.map(fn {chunk, idx} ->
      sid = idx |> to_string() |> String.pad_leading(5, "0")
      dest = "#{path}.#{sid}"
      {chunk, dest}
    end)
    |> Task.async_stream(
      fn {chunk, dest} ->
        File.write!(dest, chunk, [:binary, {:delayed_write, 64_000, 20}])
      end,
      async_opts
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, _ -> {:cont, :ok}
      {:exit, reason}, _ -> raise "failed to write segment: #{inspect(reason)}"
    end)
  end

  defp abs_path(path) do
    case Path.type(path) do
      :absolute -> path
      _ -> "/" <> String.trim_leading(path, "/")
    end
  end

  @doc """
  Builds a zip file from the given entries and uploads it.

  ## Examples

      iex> [%{path: "examples/hello_world.txt", source: [String.duplicate("A", 5_242_880)]}]
      ...> |> ZipShorts.Zip.stream()
      ...> |> ZipShorts.S3.multipart_upload("myapp-bucket", "hello.txt", [s3: [access_key_id: "XXX", secret_access_key: "XXX"]])

      iex> [%{path: "zip_shorts/guides/hello_world.txt", source: ["Hello world!"]}]
      ...> |> ZipShorts.Zip.stream()
      ...> |> ZipShorts.S3.segment_upload("myapp-bucket", "hello.txt", [s3: [access_key_id: "XXX", secret_access_key: "XXX"]])

      iex> [%{path: "zip_shorts/guides/hello_world.txt", source: ["Hello world!"]}]
      ...> |> ZipShorts.Zip.stream()
      ...> |> ZipShorts.S3.upload("myapp-bucket", "hello.txt", [s3: [access_key_id: "XXX", secret_access_key: "XXX"]])
  """
  def upload_file(entries, bucket, object, opts \\ []) do
    cond do
      opts[:multipart] === true and opts[:segment] === true ->
        raise "options :multipart and :segment cannot both be true, must choose one. got: #{inspect(opts)}"

      opts[:multipart] === true ->
        entries
        |> stream_zip(opts)
        |> multipart_upload(bucket, object, opts)

      opts[:segment] === true ->
        entries
        |> stream_zip(opts)
        |> segment_upload(bucket, object, opts)

      true ->
        entries
        |> stream_zip(opts)
        |> upload(bucket, object, opts)
    end
  end

  defp upload(source, bucket, path, opts) do
    data = source |> Enum.to_list() |> :erlang.iolist_to_binary()
    CloudCache.put_object(bucket, path, data, opts)
  end

  defp segment_upload(source, bucket, path, opts) do
    async_opts =
      opts
      |> Keyword.put_new(:max_concurrency, 4)
      |> Keyword.put_new(:ordered, false)

    source
    |> Stream.with_index()
    |> Stream.map(fn {chunk, idx} ->
      sid = idx |> to_string() |> String.pad_leading(5, "0")
      dest = "#{path}.#{sid}"
      {chunk, dest}
    end)
    |> Task.async_stream(
      fn {chunk, dest} ->
        data = :erlang.iolist_to_binary(chunk)

        case CloudCache.put_object(bucket, dest, data, opts) do
          {:ok, _} -> :ok
          {:error, reason} -> raise "failed to upload segment: #{inspect(reason)}"
        end
      end,
      async_opts
    )
    |> Stream.run()
  end

  defp multipart_upload(source, bucket, path, opts) do
    async_opts =
      opts
      |> Keyword.put_new(:max_concurrency, 4)
      |> Keyword.put_new(:ordered, false)

    case CloudCache.create_multipart_upload(bucket, path, opts) do
      {:ok, multipart} ->
        source
        |> Stream.with_index()
        |> Task.async_stream(
          fn {chunk, idx} ->
            part_number = idx + 1

            case CloudCache.upload_part(
                   bucket,
                   path,
                   multipart.upload_id,
                   part_number,
                   chunk,
                   opts
                 ) do
              {:ok, body} ->
                {part_number, body.etag}

              {:error, reason} ->
                raise "failed to upload part: #{inspect(reason)}"
            end
          end,
          async_opts
        )
        |> Enum.reduce([], fn
          {:ok, part}, acc -> [part | acc]
          {:exit, reason}, _acc -> raise "failed to upload part: #{inspect(reason)}"
        end)
        |> then(fn parts ->
          parts = Enum.reverse(parts)
          CloudCache.complete_multipart_upload(bucket, path, multipart.upload_id, parts, opts)
        end)

      {:error, reason} ->
        raise "failed to create multipart upload: #{inspect(reason)}"
    end
  end

  @doc """
  ### Examples

      iex> stream = ZipShorts.stream_zip([%{path: "rel/path/path.txt", source: ["abc"], options: [coder: Zstream.Coder.Stored]}], max_bytes_per_chunk: 10)
      ...> Enum.to_list(stream)

      iex> ZipShorts.stream_zip([%{path: "rel/path/path.txt", source: ["abc"]}], stream: false)

      iex> stream = ZipShorts.stream_zip([%{path: "rel/path/path.txt", source: ["abc"]}], upload: [bucket: "my-app-bucket", object: "path/to/object", segment?: true])
      ...> Enum.to_list(stream)
  """
  def stream_zip(entries, opts \\ []) do
    max = Keyword.get(opts, :max_bytes_per_chunk, @sixty_four_mebibytes)

    entries
    |> normalize_entries()
    |> Zstream.zip()
    |> maybe_gzip_stream(opts)
    |> ElixirUtils.Binary.chunk_bytes_stream(max)
  end

  defp maybe_gzip_stream(stream, opts) do
    if opts[:gzip] do
      gzip_opts = Keyword.merge(@default_gzip_options, opts[:gzip] || [])
      StreamGzip.gzip(stream, gzip_opts)
    else
      stream
    end
  end

  defp normalize_entries(stream) when is_function(stream) or is_struct(stream, Stream) do
    Stream.map(stream, &to_entry/1)
  end

  defp normalize_entries(list) when is_list(list) do
    if Keyword.keyword?(list) do
      [to_entry(list)]
    else
      Enum.map(list, &to_entry/1)
    end
  end

  defp normalize_entries(term) do
    [to_entry(term)]
  end

  defp to_entry(opts) when is_map(opts) do
    opts |> Map.to_list() |> to_entry()
  end

  defp to_entry(opts) do
    params = Map.new(opts)
    Zstream.entry(params.path, params.source, params.options)
  end
end
