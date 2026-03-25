defmodule PLCWeb.Controller do
  use Phoenix.Controller, formats: [:json]

  def show(conn, %{"did" => did}) do
    last_op = PLC.OpLog.last_op(did)

    if last_op do
      doc = PLC.DID.document(did, last_op)

      conn
      |> put_resp_content_type("application/did+ld+json")
      |> send_resp(200, JSON.encode!(doc))
    else
      doc = PLC.DID.document(did)

      conn
      |> put_resp_content_type("application/did+ld+json")
      |> send_resp(200, JSON.encode!(doc))
    end
  end

  def data(conn, %{"did" => did}) do
    case PLC.OpLog.last_op(did) do
      nil ->
        send_resp(conn, 404, "DID not registered: #{did}")

      last_op ->
        json(conn, PLC.DID.data(last_op))
    end
  end

  def full_log(conn, %{"did" => did}) do
    case PLC.OpLog.get_ops(did) do
      [] -> send_resp(conn, 404, "DID not registered: #{did}")
      ops -> json(conn, ops)
    end
  end

  def log(conn, %{"did" => did} = _params) do
    last_op = PLC.OpLog.last_op(did)

    if last_op do
      json = JSON.encode!(last_op)

      send_resp(conn, 200, json)
    else
      send_resp(conn, 404, "DID not registered: #{did}")
    end
  end

  def create(conn, %{"did" => did} = params) do
    op = Map.delete(params, "did")

    valid_operation =
      is_map(op) and
        Map.has_key?(op, "type") and
        (op["type"] == "plc_operation" or op["type"] == "plc_tombstone")

    if valid_operation do
      PLC.OpLog.put_op(did, op)
      send_resp(conn, 200, "")
    else
      send_resp(conn, 400, "Not a valid operation")
    end
  end
end
