# Script to create a development user with confirmed email
alias RouterosCm.Accounts
alias RouterosCm.Accounts.User
alias RouterosCm.Repo

email = "dev@localhost.com"
password = "devpassword123"

IO.puts("Creating development user...")

case Accounts.register_user(%{email: email, password: password}) do
  {:ok, user} ->
    # Manually confirm the user by setting confirmed_at
    {:ok, confirmed_user} =
      user
      |> User.confirm_changeset()
      |> Repo.update()

    IO.puts("\n✓ User created and confirmed!")
    IO.puts("  Email: #{confirmed_user.email}")
    IO.puts("  Password: #{password}")
    IO.puts("\nYou can now log in at http://localhost:4000/users/log-in")

  {:error, changeset} ->
    IO.puts("\n✗ Failed to create user:")
    IO.inspect(changeset.errors)

    # Check if user already exists
    if existing_user = Repo.get_by(User, email: email) do
      if is_nil(existing_user.confirmed_at) do
        # Confirm existing user
        {:ok, confirmed_user} =
          existing_user
          |> User.confirm_changeset()
          |> Repo.update()

        IO.puts("\n✓ Existing user confirmed!")
        IO.puts("  Email: #{confirmed_user.email}")
        IO.puts("  Password: #{password}")
      else
        IO.puts("\n✓ User already exists and is confirmed:")
        IO.puts("  Email: #{email}")
        IO.puts("  Password: #{password}")
      end

      IO.puts("\nYou can now log in at http://localhost:4000/users/log-in")
    end
end
