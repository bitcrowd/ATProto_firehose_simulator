defmodule PLC.Keys do
  # varint for secp256k1-pub
  @secp256k1_pub_multicodec <<0xE7, 0x01>>

  def generate do
    {pub_uncompressed, priv} = :crypto.generate_key(:ecdh, :secp256k1)

    pub_compressed = compress_pubkey(pub_uncompressed)
    multikey = Multibase.encode!(@secp256k1_pub_multicodec <> pub_compressed, :base58_btc)

    %{
      private_hex: Base.encode16(priv, case: :lower),
      multikey: multikey
    }
  end

  defp compress_pubkey(<<4, x::binary-32, y::binary-32>>) do
    prefix = if rem(:binary.decode_unsigned(y), 2) == 0, do: 0x02, else: 0x03
    <<prefix, x::binary>>
  end

  defp compress_pubkey(<<prefix, _::binary-32>> = pub) when prefix in [2, 3], do: pub
end
