defmodule LocalLedger.RouterTest do
  use ExUnit.Case, async: true
  import Plug.Test

  test "index page shows ledger reports instead of a streaming journal" do
    conn = conn(:get, "/")
    conn = LocalLedger.Router.call(conn, LocalLedger.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Account balances"
    assert conn.resp_body =~ "type === 'report'"
    refute conn.resp_body =~ "type === 'chunk'"
    assert conn.resp_body =~ "data.download"
    assert conn.resp_body =~ "ledgerFilename"
  end
end
