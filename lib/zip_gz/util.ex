defmodule ZipGz.Util do
  @moduledoc false

  @doc """

  ### Examples

      iex> "ABCDE" |> ZipGz.Util.byte_stream(2) |> Enum.to_list()
      ["AB", "CD", "EF"

      iex> ["A", "B", "CDE"] |> ZipGz.Util.byte_stream(2) |> Enum.to_list()
      ["AB", "CD", "E"]

      iex> ["A", "B", "CD"] |> ZipGz.Util.byte_stream(2) |> Enum.to_list()
      ["AB", "CD"]
  """
  def byte_stream(bin, size) when is_binary(bin) do
    bin |> split(0, size) |> Tuple.to_list() |> byte_stream(size)
  end

  def byte_stream(enum, size) when is_integer(size) and size > 0 do
    enum
    |> Stream.transform(
      fn -> {[], 0} end,
      fn
        data, {buf, buf_size} when buf_size >= size ->
          case buf |> combine() |> split(0, size) do
            {item, <<>>} -> {[item], {[data], byte_size(data)}}
            {item, rest} -> {[item], {[data, rest], byte_size(rest) + byte_size(data)}}
          end

        data, {buf, buf_size} ->
          {[], {[data | buf], buf_size + byte_size(data)}}
      end,
      fn {buf, _} ->
        case buf |> combine() |> split(0, size) do
          {item, <<>>} -> {[item], nil}
          {item, rest} -> {[item, rest], nil}
        end
      end,
      fn _ -> :ok end
    )
  end

  defp combine(buf) do
    buf |> Enum.reverse() |> :erlang.iolist_to_binary()
  end

  @doc """
  Splits a binary into fixed-size chunks.

  ## Examples

      iex> ElixirUtils.Binary.chunk_bytes("abcd", 2)
      {["ab"], "cd"}

      iex> ElixirUtils.Binary.chunk_bytes("a", 2)
      {[], "a"}
  """
  def chunk_bytes(bin, size) when is_binary(bin) do
    transform(
      bin,
      size,
      [],
      fn fragment, acc -> [fragment | acc] end,
      fn rest, acc -> {Enum.reverse(acc), rest} end
    )
  end

  @doc """
  Transforms a binary, ensuring each fragment is at most the given size.

  - `bin` is the binary input
  - `size` is the max fragment size
  - `acc` is the accumulator
  - `reducer` is called for each full fragment
  - `last_fun` is called once at the end with the final (possibly short) fragment and the acc

  It always returns `{emitted, rest_or_new_acc}` depending on `last_fun`.
  """
  def transform(bin, size, acc, reducer, last_fun) when is_binary(bin) do
    case split(bin, 0, size) do
      {fragment, <<>>} -> last_fun.(fragment, acc)
      {fragment, rest} -> transform(rest, size, reducer.(fragment, acc), reducer, last_fun)
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
  def split(bin, start, length) when is_binary(bin) do
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
