defmodule Botica.Flags.Doc do
  @moduledoc """
  Generates documentation for the currently registered flags.

  The produced `docs/FLAGS.md` contains a markdown table with the
  following columns:

  | Name | Enabled | Default | Rollout | Description |
  """

  @spec generate() :: :ok
  def generate do
    flags = Botica.Flags.all()

    priv_dir = Application.app_dir(:botica, "priv")
    write_path = Path.join(priv_dir, "docs/FLAGS.md")

    header = [
      "# Flags",
      "",
      "| Name | Enabled | Default | Rollout | Description |",
      "|---|---|---|---|---|"
    ]

    rows =
      Enum.map(flags, fn flag ->
        rollout = if flag.rollout, do: "#{flag.rollout}%", else: "-"

        "| #{inspect(flag.name)} | #{flag.enabled} | #{flag.default} | #{rollout} | #{flag.description || ""} |"
      end)

    content = Enum.join(header ++ rows, "\n")

    File.mkdir_p!(Path.dirname(write_path))
    File.write!(write_path, content)
  end
end
