defmodule PLC.KeysTest do
  use ExUnit.Case, async: true

  alias PLC.Keys

  test "generate returns expected key material" do
    keys = Keys.generate()

    assert is_binary(keys.private_hex)
    assert byte_size(keys.private_hex) == 64
    assert is_binary(keys.private)
    assert byte_size(keys.private) == 32
    assert is_binary(keys.multikey)
    assert String.starts_with?(keys.multikey, "z")
    assert is_binary(keys.public_uncompressed)
    assert byte_size(keys.public_uncompressed) == 65
    assert binary_part(keys.public_uncompressed, 0, 1) == <<4>>
  end

  test "restores public key from multikey" do
    keys = Keys.generate()

    assert Keys.public_from_multikey(keys.multikey) == keys.public_uncompressed
  end

  test "restores private key from private_hex" do
    keys = Keys.generate()

    assert Keys.private_from_hex(keys.private_hex) == keys.private
  end
end
