defmodule ZipGz.Util do
  @moduledoc false

  defguardp is_pos_integer(t) when is_integer(t) and t > 0
  defguardp is_non_neg_integer(t) when is_integer(t) and t >= 0

  def content_byte_stream(bin, size) when is_binary(bin) and is_pos_integer(size) do
    Stream.resource(
      fn -> bin end,
      fn
        <<>> ->
          {:halt, nil}

        bin ->
          case chunk_bytes(bin, size) do
            {[], rest} -> {[rest], <<>>}
            {chunks, rest} -> {chunks, rest}
          end
      end,
      fn _ -> :ok end
    )
  end

  def content_byte_stream(enum, size) when is_pos_integer(size) do
    Stream.transform(
      enum,
      fn -> <<>> end,
      fn
        iodata, <<>> ->
          bin = IO.iodata_to_binary(iodata)
          chunk_bytes(bin, size)

        bin, buf when is_binary(bin) ->
          combined = <<buf::binary, bin::binary>>
          chunk_bytes(combined, size)

        iodata, buf ->
          combined = IO.iodata_to_binary([buf, iodata])
          chunk_bytes(combined, size)
      end,
      fn
        <<>> -> {[], <<>>}
        rest -> {[rest], <<>>}
      end,
      fn _ -> :ok end
    )
  end

  @doc """
  Splits a binary into fixed-size chunks.

  ## Examples

      iex> ElixirUtils.Binary.chunk_bytes("abcd", 2)
      {["ab"], "cd"}

      iex> ElixirUtils.Binary.chunk_bytes("a", 2)
      {[], "a"}
  """
  def chunk_bytes(bin, size) when is_binary(bin) and is_pos_integer(size) do
    traverse(
      bin,
      size,
      [],
      fn fragment, acc -> [fragment | acc] end,
      fn rest, acc -> {Enum.reverse(acc), rest} end
    )
  end

  @doc """
  Traverses a binary, ensuring each fragment is at most the given size.

  - `bin` is the binary input
  - `size` is the max fragment size
  - `acc` is the accumulator
  - `reducer` is called for each full fragment
  - `last_fun` is called once at the end with the final (possibly short) fragment and the acc

  It always returns `{emitted, rest_or_new_acc}` depending on `last_fun`.
  """
  def traverse(bin, size, acc, reducer, last_fun) when is_binary(bin) and is_pos_integer(size) do
    case split(bin, 0, size) do
      {fragment, <<>>} ->
        last_fun.(fragment, acc)

      {fragment, rest} ->
        next_acc = reducer.(fragment, acc)
        traverse(rest, size, next_acc, reducer, last_fun)
    end
  end

  @doc """
  Extracts a fragment from a binary.

  Returns `{fragment, rest}` where `fragment` is max of `length`
  bytes in size starting at `start`, and `rest` is the remaining
  binary (or `nil` when none).

  ## Examples

      iex> ElixirUtils.Binary.split("abc", 0, 1)
      {"a", "bc"}

      iex> ElixirUtils.Binary.split("abc", 1, 1)
      {"b", "c"}

      iex> ElixirUtils.Binary.split("abc", 0, 3)
      {"abc", ""}
  """
  def split(bin, start, length)
      when is_binary(bin) and is_non_neg_integer(start) and is_pos_integer(length) do
    total = byte_size(bin)

    if start >= total do
      {<<>>, <<>>}
    else
      # how many bytes remain from start
      avail = total - start
      # ensures we never read past the end.
      take = min(length, avail)
      <<_::binary-size(start), fragment::binary-size(take), rest::binary>> = bin
      {fragment, rest}
    end
  end
end
