defmodule Mix.Tasks.Container do
  @moduledoc """
  Container build and publish tasks for RouterOS Cluster Manager.

  ## Available tasks

      mix container.build      # Build the container image locally
      mix container.publish    # Publish to ghcr.io
      mix container.run        # Run the container locally
      mix container.stop       # Stop the running container
      mix container.logs       # View container logs

  ## Configuration

  Set the following environment variables for publishing:

      GITHUB_USERNAME    - Your GitHub username (for ghcr.io)
      GITHUB_TOKEN       - GitHub Personal Access Token with packages:write scope

  Or configure in config/config.exs:

      config :routeros_cm, :container,
        registry: "ghcr.io",
        namespace: "your-github-username",
        image_name: "routeros_cm"

  """
end

defmodule Mix.Tasks.Container.Build do
  @shortdoc "Build the container image locally"
  @moduledoc """
  Build the container image locally using Podman.

  ## Usage

      mix container.build [options]

  ## Options

      --tag, -t     - Tag for the image (default: latest)
      --no-cache    - Build without using cache

  ## Examples

      mix container.build
      mix container.build --tag v1.0.0
      mix container.build --no-cache

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        aliases: [t: :tag],
        switches: [tag: :string, no_cache: :boolean]
      )

    tag = Keyword.get(opts, :tag, "latest")
    no_cache = Keyword.get(opts, :no_cache, false)

    image_name = get_image_name()
    full_tag = "#{image_name}:#{tag}"

    Mix.shell().info("Building container image: #{full_tag}")

    cache_arg = if no_cache, do: ["--no-cache"], else: []

    args = ["build", "-t", full_tag] ++ cache_arg ++ ["."]

    case System.cmd("podman", args, into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        Mix.shell().info("\n✓ Successfully built #{full_tag}")

      {_, code} ->
        Mix.raise("Container build failed with exit code #{code}")
    end
  end

  defp get_image_name do
    config = Application.get_env(:routeros_cm, :container, [])
    Keyword.get(config, :image_name, "routeros_cm")
  end
end

defmodule Mix.Tasks.Container.Publish do
  @shortdoc "Publish the container image to ghcr.io"
  @moduledoc """
  Publish the container image to GitHub Container Registry (ghcr.io).

  ## Usage

      mix container.publish [options]

  ## Options

      --tag, -t         - Tag for the image (default: latest)
      --build, -b       - Build the image before publishing
      --namespace, -n   - GitHub namespace/username (overrides config)

  ## Environment Variables

      GITHUB_USERNAME   - Your GitHub username
      GITHUB_TOKEN      - GitHub PAT with packages:write scope

  ## Examples

      mix container.publish
      mix container.publish --tag v1.0.0
      mix container.publish --build --tag v1.0.0
      mix container.publish --namespace myorg --tag latest

  ## Authentication

  Before publishing, authenticate with ghcr.io:

      echo $GITHUB_TOKEN | podman login ghcr.io -u $GITHUB_USERNAME --password-stdin

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        aliases: [t: :tag, b: :build, n: :namespace],
        switches: [tag: :string, build: :boolean, namespace: :string]
      )

    tag = Keyword.get(opts, :tag, "latest")
    build_first = Keyword.get(opts, :build, false)
    namespace_override = Keyword.get(opts, :namespace)

    config = Application.get_env(:routeros_cm, :container, [])
    registry = Keyword.get(config, :registry, "ghcr.io")

    namespace =
      namespace_override ||
        Keyword.get(config, :namespace) ||
        System.get_env("GITHUB_USERNAME") ||
        Mix.raise("""
        GitHub namespace not configured.

        Set GITHUB_USERNAME environment variable or configure:

            config :routeros_cm, :container,
              namespace: "your-github-username"
        """)

    image_name = Keyword.get(config, :image_name, "routeros_cm")
    local_tag = "#{image_name}:#{tag}"
    remote_tag = "#{registry}/#{namespace}/#{image_name}:#{tag}"

    # Build first if requested
    if build_first do
      Mix.shell().info("Building image first...")
      Mix.Task.run("container.build", ["--tag", tag])
    end

    Mix.shell().info("Tagging #{local_tag} as #{remote_tag}")

    case System.cmd("podman", ["tag", local_tag, remote_tag]) do
      {_, 0} -> :ok
      {_, _} -> Mix.raise("Failed to tag image")
    end

    Mix.shell().info("Pushing #{remote_tag}")

    case System.cmd("podman", ["push", remote_tag], into: IO.stream(:stdio, :line)) do
      {_, 0} ->
        Mix.shell().info("\n✓ Successfully published #{remote_tag}")

      {_, code} ->
        Mix.raise("Push failed with exit code #{code}")
    end
  end
end

defmodule Mix.Tasks.Container.Run do
  @shortdoc "Run the container locally"
  @moduledoc """
  Run the container locally using Podman.

  ## Usage

      mix container.run [options]

  ## Options

      --tag, -t       - Image tag to run (default: latest)
      --port, -p      - Host port to bind (default: 6555)
      --name, -n      - Container name (default: routeros_cm)
      --detach, -d    - Run in detached mode (default: true)
      --env-file      - Path to env file (default: .env.docker)
      --host-network  - Use host networking (required for local router access)

  ## Examples

      mix container.run
      mix container.run --port 8080
      mix container.run --tag v1.0.0 --port 4000
      mix container.run --host-network    # Access routers on local network

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        aliases: [t: :tag, p: :port, n: :name, d: :detach],
        switches: [
          tag: :string,
          port: :integer,
          name: :string,
          detach: :boolean,
          env_file: :string,
          host_network: :boolean
        ]
      )

    tag = Keyword.get(opts, :tag, "latest")
    port = Keyword.get(opts, :port, 6555)
    name = Keyword.get(opts, :name, "routeros_cm")
    detach = Keyword.get(opts, :detach, true)
    env_file = Keyword.get(opts, :env_file, ".env.docker")
    host_network = Keyword.get(opts, :host_network, false)

    image_name = get_image_name()
    full_tag = "#{image_name}:#{tag}"

    # Stop existing container if running
    System.cmd("podman", ["rm", "-f", name], stderr_to_stdout: true)

    if host_network do
      Mix.shell().info("Starting container #{name} from #{full_tag} with host networking")
      Mix.shell().info("  App will listen on port 6555")
    else
      Mix.shell().info("Starting container #{name} from #{full_tag} on port #{port}")
    end

    detach_args = if detach, do: ["-d"], else: []

    env_file_args =
      if File.exists?(env_file) do
        ["--env-file", env_file]
      else
        Mix.shell().info("Warning: #{env_file} not found, using defaults")
        []
      end

    # Use host network or bridge with port mapping
    network_args =
      if host_network do
        ["--network", "host"]
      else
        ["-p", "#{port}:6555"]
      end

    args =
      ["run"] ++
        detach_args ++
        ["--name", name] ++
        network_args ++
        ["-v", "routeros_cm_data:/app/data"] ++
        env_file_args ++
        [
          "-e",
          "PHX_SERVER=true",
          "-e",
          "PORT=6555",
          "-e",
          "PHX_HOST=localhost",
          "-e",
          "DATABASE_PATH=/app/data/routeros_cm.db",
          full_tag
        ]

    case System.cmd("podman", args) do
      {output, 0} ->
        container_id = String.trim(output)
        Mix.shell().info("✓ Container started: #{container_id}")

        if host_network do
          Mix.shell().info("  Access at: http://localhost:6555")
        else
          Mix.shell().info("  Access at: http://localhost:#{port}")
        end

        if detach do
          Mix.shell().info("  View logs: mix container.logs")
        end

      {_, code} ->
        Mix.raise("Failed to start container (exit code #{code})")
    end
  end

  defp get_image_name do
    config = Application.get_env(:routeros_cm, :container, [])
    Keyword.get(config, :image_name, "routeros_cm")
  end
end

defmodule Mix.Tasks.Container.Stop do
  @shortdoc "Stop the running container"
  @moduledoc """
  Stop and remove the running container.

  ## Usage

      mix container.stop [options]

  ## Options

      --name, -n    - Container name (default: routeros_cm)
      --keep        - Stop but don't remove the container

  ## Examples

      mix container.stop
      mix container.stop --keep

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        aliases: [n: :name],
        switches: [name: :string, keep: :boolean]
      )

    name = Keyword.get(opts, :name, "routeros_cm")
    keep = Keyword.get(opts, :keep, false)

    Mix.shell().info("Stopping container #{name}...")

    if keep do
      case System.cmd("podman", ["stop", name]) do
        {_, 0} -> Mix.shell().info("✓ Container stopped")
        {_, _} -> Mix.shell().info("Container was not running")
      end
    else
      case System.cmd("podman", ["rm", "-f", name]) do
        {_, 0} -> Mix.shell().info("✓ Container stopped and removed")
        {_, _} -> Mix.shell().info("Container was not running")
      end
    end
  end
end

defmodule Mix.Tasks.Container.Logs do
  @shortdoc "View container logs"
  @moduledoc """
  View logs from the running container.

  ## Usage

      mix container.logs [options]

  ## Options

      --name, -n    - Container name (default: routeros_cm)
      --follow, -f  - Follow log output
      --tail        - Number of lines to show from end (default: 100)

  ## Examples

      mix container.logs
      mix container.logs --follow
      mix container.logs --tail 50

  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        aliases: [n: :name, f: :follow],
        switches: [name: :string, follow: :boolean, tail: :integer]
      )

    name = Keyword.get(opts, :name, "routeros_cm")
    follow = Keyword.get(opts, :follow, false)
    tail = Keyword.get(opts, :tail, 100)

    follow_args = if follow, do: ["-f"], else: []

    args = ["logs", "--tail", "#{tail}"] ++ follow_args ++ [name]

    System.cmd("podman", args, into: IO.stream(:stdio, :line))
  end
end

defmodule Mix.Tasks.Container.Login do
  @shortdoc "Login to GitHub Container Registry"
  @moduledoc """
  Login to ghcr.io using GitHub credentials.

  ## Usage

      mix container.login

  ## Environment Variables

      GITHUB_USERNAME   - Your GitHub username
      GITHUB_TOKEN      - GitHub PAT with packages:write scope

  ## Examples

      # Set credentials and login
      export GITHUB_USERNAME=myuser
      export GITHUB_TOKEN=ghp_xxxx
      mix container.login

  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    username =
      System.get_env("GITHUB_USERNAME") ||
        Mix.raise("GITHUB_USERNAME environment variable not set")

    token =
      System.get_env("GITHUB_TOKEN") ||
        Mix.raise("GITHUB_TOKEN environment variable not set")

    Mix.shell().info("Logging in to ghcr.io as #{username}...")

    port = Port.open({:spawn, "podman login ghcr.io -u #{username} --password-stdin"}, [:binary])
    Port.command(port, token)
    Port.close(port)

    # Give it a moment to process
    Process.sleep(1000)

    Mix.shell().info("✓ Login successful")
  end
end
