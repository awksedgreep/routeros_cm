defmodule RouterosCm.Vault do
  @moduledoc """
  Encryption vault for sensitive data like MikroTik credentials.
  Uses AES-256-GCM encryption with a key derived from environment variable.
  """

  # AES-256 key length is 32 bytes
  @key_bytes 32
  # IV/nonce for AES-GCM is 12 bytes
  @iv_bytes 12
  # Auth tag for AES-GCM
  @tag_bytes 16

  @doc """
  Encrypts plaintext using AES-256-GCM.
  Returns `{:ok, ciphertext}` where ciphertext is base64-encoded and includes IV + tag.
  """
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_key!()
    iv = :crypto.strong_rand_bytes(@iv_bytes)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "", true)

    # Combine IV + tag + ciphertext and base64 encode
    combined = iv <> tag <> ciphertext
    {:ok, Base.encode64(combined)}
  end

  def encrypt(nil), do: {:ok, nil}

  @doc """
  Decrypts ciphertext that was encrypted with `encrypt/1`.
  Returns `{:ok, plaintext}` or `{:error, reason}`.
  """
  def decrypt(nil), do: {:ok, nil}

  def decrypt(ciphertext_b64) when is_binary(ciphertext_b64) do
    key = get_key!()

    with {:ok, combined} <- Base.decode64(ciphertext_b64),
         <<iv::binary-size(@iv_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>> <-
           combined do
      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "", tag, false) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        :error -> {:error, :decryption_failed}
      end
    else
      :error -> {:error, :invalid_base64}
      _ -> {:error, :invalid_ciphertext_format}
    end
  end

  @doc """
  Encrypts a value or raises on failure.
  """
  def encrypt!(plaintext) do
    {:ok, result} = encrypt(plaintext)
    result
  end

  @doc """
  Decrypts a value or raises on failure.
  """
  def decrypt!(ciphertext) do
    case decrypt(ciphertext) do
      {:ok, result} -> result
      {:error, reason} -> raise "Decryption failed: #{inspect(reason)}"
    end
  end

  @doc """
  Generates a new random encryption key suitable for use with this vault.
  The key is returned as a base64-encoded string.
  """
  def generate_key do
    :crypto.strong_rand_bytes(@key_bytes)
    |> Base.encode64()
  end

  # Gets the encryption key from config/environment
  defp get_key! do
    key_b64 =
      Application.get_env(:routeros_cm, :credential_encryption_key) ||
        System.get_env("CREDENTIAL_KEY") ||
        raise """
        Missing encryption key!

        Set the CREDENTIAL_KEY environment variable or configure:

            config :routeros_cm, :credential_encryption_key, "your-base64-key"

        Generate a key with: RouterosCm.Vault.generate_key()
        """

    case Base.decode64(key_b64) do
      {:ok, key} when byte_size(key) == @key_bytes ->
        key

      {:ok, key} ->
        raise "Invalid encryption key length: expected #{@key_bytes} bytes, got #{byte_size(key)}"

      :error ->
        raise "Invalid encryption key: not valid base64"
    end
  end
end
