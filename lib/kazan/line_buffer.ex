defmodule Kazan.LineBuffer do
  @moduledoc "Buffers strings until a complete line is formed with a CR on the end"
  alias __MODULE__

  defstruct lines: [], pending: ""

  @doc "Create a new buffer"
  def new, do: %LineBuffer{}

  @doc "Add a chunk for characters to the buffer"
  def add_chunk(%LineBuffer{lines: lines, pending: pending}, chunk) do
    {new_lines, pending} =
      case String.last(chunk) do
        # Final line is complete
        "\n" ->
          {String.split(pending <> String.trim_trailing(chunk), "\n"), ""}

        # Final line is not complete
        _ ->
          new_lines = String.split(pending <> chunk, "\n")
          {Enum.drop(new_lines, -1), List.last(new_lines)}
      end
    %LineBuffer{lines: lines ++ new_lines, pending: pending}
  end

  @doc "Extract any complete buffered lines"
  def get_lines(%LineBuffer{lines: lines} = buffer) do
    {lines, %LineBuffer{buffer | lines: []}}
  end
end
