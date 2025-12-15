defmodule RouterosCm.WireGuard.Keys do
  @moduledoc """
  WireGuard key generation using Curve25519.
  """

  @doc """
  Generates a new WireGuard private key.
  Returns a base64-encoded 32-byte key.
  """
  def generate_private_key do
    {public, private} = :crypto.generate_key(:ecdh, :x25519)
    # We only need the private key, RouterOS derives the public key
    _ = public
    Base.encode64(private)
  end

  @doc """
  Derives the public key from a private key.
  Both keys are base64-encoded.
  """
  def derive_public_key(private_key_b64) do
    {:ok, private_key} = Base.decode64(private_key_b64)
    {public, _private} = :crypto.generate_key(:ecdh, :x25519, private_key)
    Base.encode64(public)
  end

  @doc """
  Generates a new key pair.
  Returns `{private_key, public_key}` as base64-encoded strings.
  """
  def generate_key_pair do
    {public, private} = :crypto.generate_key(:ecdh, :x25519)
    {Base.encode64(private), Base.encode64(public)}
  end
end
