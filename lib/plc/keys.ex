defmodule PLC.Keys do
  @moduledoc false
  alias Multiformats.Multibase

  # varint for secp256k1-pub
  @secp256k1_pub_multicodec <<0xE7, 0x01>>

  def generate do
    {pub_uncompressed, priv} = :crypto.generate_key(:ecdh, :secp256k1)

    pub_compressed = compress_pubkey(pub_uncompressed)
    multikey = Multibase.encode(@secp256k1_pub_multicodec <> pub_compressed, :base58btc)

    %{
      private_hex: Base.encode16(priv, case: :lower),
      private: priv,
      multikey: multikey,
      public_uncompressed: pub_uncompressed
    }
  end

  defp compress_pubkey(<<4, x::binary-32, y::binary-32>>) do
    prefix = if rem(:binary.decode_unsigned(y), 2) == 0, do: 0x02, else: 0x03
    <<prefix, x::binary>>
  end

  defp compress_pubkey(<<prefix, _::binary-32>> = pub) when prefix in [2, 3], do: pub

  def public_from_multikey(multikey) do
    decoded = Multibase.decode!(multikey)

    <<@secp256k1_pub_multicodec, compressed::binary>> = decoded

    decompress_pubkey(compressed)
  end

  def private_from_hex(private_hex) when is_binary(private_hex) do
    Base.decode16!(private_hex, case: :mixed)
  end

  defp decompress_pubkey(<<prefix, x::binary-32>>) when prefix in [2, 3] do
    x_int = :binary.decode_unsigned(x)

    # secp256k1 params
    p = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F

    # y^2 = x^3 + 7 mod p
    y_sq = rem(x_int * x_int * x_int + 7, p)

    # since p % 4 == 3, sqrt can be done via exponentiation
    y =
      y_sq
      |> :crypto.mod_pow(div(p + 1, 4), p)
      |> :binary.decode_unsigned()

    y =
      case rem(y, 2) do
        parity when parity == prefix - 2 -> y
        _ -> p - y
      end

    y_bin = :binary.encode_unsigned(y) |> pad32()

    <<4, x::binary, y_bin::binary>>
  end

  defp pad32(bin) when byte_size(bin) < 32 do
    :binary.copy(<<0>>, 32 - byte_size(bin)) <> bin
  end

  defp pad32(bin), do: bin
end
