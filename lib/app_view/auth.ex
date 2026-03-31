defmodule AppView.Auth do
  alias PLC.Keys

  def bearer_token(did, audience, lexicon_method) do
    config = Application.get_env(:firehose_simulator, :plc)

    public = config[:multikey] |> Keys.public_from_multikey()
    private = config[:private_hex] |> Keys.private_from_hex()

    mint!(public, private, did, audience, lexicon_method)
  end

  def mint!(public, private, issuer, audience, lexicon_method) do
    <<4, x::binary-32, y::binary-32>> = public

    jwk =
      JOSE.JWK.from_map(%{
        # Elliptic Curve key
        "kty" => "EC",
        # Curve name
        "crv" => "secp256k1",
        # private key
        "d" => Base.url_encode64(private, padding: false),
        # public key x
        "x" => Base.url_encode64(x, padding: false),
        # public key y
        "y" => Base.url_encode64(y, padding: false)
      })

    now = System.system_time(:second)

    claims = %{
      "iss" => issuer,
      # audience: did of AppView
      "aud" => audience,
      # issued_at
      "iat" => now,
      # expires_at
      "exp" => now + 60,
      # lexicon method, e.g. app.bsky.feed.getTimeline
      "lxm" => lexicon_method,
      # JWT ID
      "jti" => Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    }

    {_, jwt} =
      JOSE.JWT.sign(jwk, %{"alg" => "ES256K", "typ" => "JWT"}, claims)
      |> JOSE.JWS.compact()

    jwt
  end
end
