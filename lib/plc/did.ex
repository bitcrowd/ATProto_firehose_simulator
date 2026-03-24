defmodule PLC.DID do
  @moduledoc "https://web.plc.directory/spec/v0.1/did-plc"

  @default_multikey "zQ3shaSUSFjTPxogQR7eQ9QGwKWUdMmrHyjNiUg9oGJ8Lefiv"
  # private_hex=bfe084f28e8bd6a64cbc18eea04c17457c9c48ce34498bc635b19ec7530d5e4a
  @pds_endpoint "http://127.0.0.1:2583"

  def document(did, op \\ nil) do
    handle = handle_from_op(op)
    public_key_multibase = public_key_multibase_from_op(op)
    pds_endpoint = pds_endpoint_from_op(op)

    %{
      "@context" => [
        "https://www.w3.org/ns/did/v1",
        "https://w3id.org/security/multikey/v1",
        "https://w3id.org/security/suites/secp256k1-2019/v1"
      ],
      "id" => did,
      "alsoKnownAs" => ["at://#{handle}"],
      "verificationMethod" => [
        %{
          "id" => "#{did}#atproto",
          "type" => "Multikey",
          "controller" => did,
          "publicKeyMultibase" => public_key_multibase
        }
      ],
      "service" => [
        %{
          "id" => "#atproto_pds",
          "type" => "AtprotoPersonalDataServer",
          "serviceEndpoint" => pds_endpoint
        }
      ]
    }
  end

  def data(op) when is_map(op) do
    %{
      "rotationKeys" => Map.get(op, "rotationKeys", []),
      "verificationMethods" => Map.get(op, "verificationMethods", %{}),
      "alsoKnownAs" => Map.get(op, "alsoKnownAs", []),
      "services" => Map.get(op, "services", %{})
    }
  end

  defp handle_from_op(op) when is_map(op) do
    op
    |> Map.get("alsoKnownAs", [])
    |> Enum.find_value("dummy.handle", fn
      "at://" <> handle -> handle
      _ -> nil
    end)
  end

  defp handle_from_op(_), do: "dummy.handle"

  defp pds_endpoint_from_op(op) when is_map(op) do
    op
    |> Map.get("services", %{})
    |> Map.get("atproto_pds", %{})
    |> Map.get("endpoint", @pds_endpoint)
  end

  defp pds_endpoint_from_op(_), do: @pds_endpoint

  defp public_key_multibase_from_op(op) when is_map(op) do
    atproto =
      op
      |> Map.get("verificationMethods", %{})
      |> Map.get("atproto")

    case atproto do
      "did:key:" <> multikey ->
        multikey

      %{"publicKeyMultibase" => multikey} when is_binary(multikey) ->
        multikey

      _ ->
        @default_multikey
    end
  end

  defp public_key_multibase_from_op(_), do: @default_multikey
end
