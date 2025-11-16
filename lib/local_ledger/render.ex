defmodule LocalLedger.Render do
  @moduledoc "Minimal template renderer using Elixir's built-in EEx."
  require EEx

  @template_root Path.expand("lib/local_ledger/templates", File.cwd!())

  def render(template, assigns \\ []) do
    template_path = Path.join(@template_root, template)
    EEx.eval_file(template_path, assigns)
  end
end
