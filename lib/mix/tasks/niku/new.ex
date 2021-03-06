defmodule Mix.Tasks.Niku.New do
  use Mix.Task

  import Mix.Generator

  @shortdoc "Creates a new Elixir project with some customization"

  @moduledoc """
  Creates a new Elixir project with some customization.
  It expects the path of the project as argument.

      mix niku.new PATH [--sup] [--module MODULE] [--app APP] [--umbrella]

  A project at the given PATH will be created. The
  application name and module name will be retrieved
  from the path, unless `--module` or `--app` is given.

  A `--sup` option can be given to generate an OTP application
  skeleton including a supervision tree. Normally an app is
  generated without a supervisor and without the app callback.

  An `--umbrella` option can be given to generate an
  umbrella project.

  An `--app` option can be given in order to
  name the OTP application for the project.

  A `--module` option can be given in order
  to name the modules in the generated code skeleton.

  ## Examples

      mix niku.new hello_world

  Is equivalent to:

      mix niku.new hello_world --module HelloWorld

  To generate an app with a supervision tree and an application callback:

      mix niku.new hello_world --sup

  """

  @switches [
    app: :string,
    module: :string,
    sup: :boolean,
    umbrella: :boolean
  ]

  @spec run(OptionParser.argv) :: :ok
  def run(argv) do
    {opts, argv} = OptionParser.parse!(argv, strict: @switches)

    case argv do
      [] ->
        Mix.raise "Expected PATH to be given, please use \"mix niku.new PATH\""
      [path | _] ->
        app = opts[:app] || Path.basename(Path.expand(path))
        check_application_name!(app, !opts[:app])
        mod = opts[:module] || Macro.camelize(app)
        check_mod_name_validity!(mod)
        check_mod_name_availability!(mod)
        unless path == "." do
          check_directory_existence!(path)
          File.mkdir_p!(path)
        end

        File.cd! path, fn ->
          if opts[:umbrella] do
            generate_umbrella(app, mod, path, opts)
          else
            generate(app, mod, path, opts)
          end
        end
    end
  end

  defp generate(app, mod, path, opts) do
    assigns = [app: app, mod: mod, sup_app: sup_app(mod, !!opts[:sup]),
               version: get_version(System.version), user: System.get_env("USER"), year: Date.utc_today.year]

    create_file "README.md",  readme_template(assigns)
    create_file ".gitignore", gitignore_text()
    create_file "LICENSE", license_template(assigns)
    create_file ".travis.yml", dot_travis_template(assigns)
    create_file "Dockerfile", dockerfile_template(assigns)

    if in_umbrella?() do
      create_file "mix.exs", mixfile_apps_template(assigns)
    else
      create_file "mix.exs", mixfile_template(assigns)
    end

    create_directory "config"
    create_file "config/config.exs", config_template(assigns)
    create_file "config/.credo.exs", config_dot_credo_text()

    create_directory "lib"
    create_file "lib/#{app}.ex", lib_template(assigns)

    if opts[:sup] do
      create_file "lib/#{app}/application.ex", lib_app_template(assigns)
    end

    create_directory "test"
    create_file "test/test_helper.exs", test_helper_template(assigns)
    create_file "test/#{app}_test.exs", test_template(assigns)

    """

    Your Mix project was created successfully.
    You can use "mix" to compile it, test it, and more:

        #{cd_path(path)}mix test

    Run "mix help" for more commands.

    Additionaly, you can use Travis CI if you wanted.

    1. Make a github repository for this project
    2. Make CI enable
    3. Set HEX_PASSPHRASE as environment variable on Travis CI
    4. Encrypt ~/.hex/hex.config and commit encripted file to the repository

        % cd #{path}
        #{path}% hub create
        #{path}% travis enable
        #{path}% travis set HEX_PASSPHRASE *YOUR_HEX_PASSPHRASE_HERE*
        #{path}% travis encrypt-file ~/.hex/hex.config
    """
    |> String.trim_trailing
    |> Mix.shell.info
  end

  defp sup_app(_mod, false), do: ""
  defp sup_app(mod, true), do: ",\n      mod: {#{mod}.Application, []}"

  defp cd_path("."), do: ""
  defp cd_path(path), do: "cd #{path}\n    "

  defp generate_umbrella(_app, mod, path, _opts) do
    assigns = [app: nil, mod: mod, user: System.get_env("USER"), year: Date.utc_today.year]

    create_file ".gitignore", gitignore_text()
    create_file "LICENSE", license_template(assigns)
    create_file "README.md", readme_template(assigns)
    create_file "mix.exs", mixfile_umbrella_template(assigns)
    create_file ".travis.yml", dot_travis_template(assigns)
    create_file "Dockerfile", dockerfile_template(assigns)

    create_directory "apps"

    create_directory "config"
    create_file "config/config.exs", config_umbrella_template(assigns)
    create_file "config/.credo.exs", config_dot_credo_text()

    """

    Your umbrella project was created successfully.
    Inside your project, you will find an apps/ directory
    where you can create and host many apps:

        #{cd_path(path)}cd apps
        mix niku.new my_app

    Commands like "mix compile" and "mix test" when executed
    in the umbrella project root will automatically run
    for each application in the apps/ directory.

    Additionaly, you can use Travis CI if you wanted.

    1. Make a github repository for this project
    2. Make CI enable
    3. Set HEX_PASSPHRASE as environment variable on Travis CI
    4. Encrypt ~/.hex/hex.config and commit encripted file to the repository

        % cd #{path}
        #{path}% hub create
        #{path}% travis enable
        #{path}% travis env set HEX_PASSPHRASE *YOUR_HEX_PASSPHRASE_HERE*
        #{path}% travis encrypt-file ~/.hex/hex.config
    """
    |> String.trim_trailing
    |> Mix.shell.info
  end

  defp check_application_name!(name, inferred?) do
    unless name =~ Regex.recompile!(~r/^[a-z][a-z0-9_]*$/) do
      Mix.raise "Application name must start with a letter and have only lowercase " <>
                "letters, numbers and underscore, got: #{inspect name}" <>
                (if inferred? do
                  ". The application name is inferred from the path, if you'd like to " <>
                  "explicitly name the application then use the \"--app APP\" option"
                else
                  ""
                end)
    end
  end

  defp check_mod_name_validity!(name) do
    unless name =~ Regex.recompile!(~r/^[A-Z]\w*(\.[A-Z]\w*)*$/) do
      Mix.raise "Module name must be a valid Elixir alias (for example: Foo.Bar), got: #{inspect name}"
    end
  end

  defp check_mod_name_availability!(name) do
    name = Module.concat(Elixir, name)
    if Code.ensure_loaded?(name) do
      Mix.raise "Module name #{inspect name} is already taken, please choose another name"
    end
  end

  defp check_directory_existence!(path) do
    if File.dir?(path) and not Mix.shell.yes?("The directory #{inspect(path)} already exists. Are you sure you want to continue?") do
      Mix.raise "Please select another directory for installation"
    end
  end

  defp get_version(version) do
    {:ok, version} = Version.parse(version)
    "#{version.major}.#{version.minor}" <>
      case version.pre do
        [h | _] -> "-#{h}"
        []      -> ""
      end
  end

  defp in_umbrella? do
    apps = Path.dirname(File.cwd!)

    try do
      Mix.Project.in_project(:umbrella_check, "../..", fn _ ->
        path = Mix.Project.config[:apps_path]
        path && Path.expand(path) == apps
      end)
    catch
      _, _ -> false
    end
  end

  embed_template :readme, """
  # <%= @mod %>

  **TODO: Add description**
  <%= if @app do %>
  ## Installation

  If [available in Hex](https://hex.pm/docs/publish), the package can be installed
  by adding `<%= @app %>` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [
      {:<%= @app %>, "~> 0.1.0"}
    ]
  end
  ```

  Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
  and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
  be found at [https://hexdocs.pm/<%= @app %>](https://hexdocs.pm/<%= @app %>).
  <% end %>
  """

  embed_template :license, """
  MIT License

  Copyright (c) <%= @year %> <%= @user %>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  """

  # We use `\\` (double-backslash) in this template. Usually, It is converted to `\` (single-backslash).
  # So, we have to use `~S` to avoid unexpected convertion.
  embed_template :dot_travis, ~S"""
  language: elixir
  sudo: false
  otp_release:
    - 20.0
  elixir:
    - 1.5.0
  env:
    global:
      # Follow other language's environment
      # e.g.) `RACK_ENV=test` has been setted as Default Environment Variables
      # https://docs.travis-ci.com/user/environment-variables/#Default-Environment-Variables
      - MIX_ENV=test
  cache:
    directories:
      - _build
      - deps
  before_install:
    # https://docs.travis-ci.com/user/encrypting-files/
    # Decrypt the file about configuration(auth and so on) of hex.pm
    - mkdir -p ~/.hex/
    # You need execution command `travis encrypt-file ~/.hex/hex.config` in the repository and adding generated line following like:
    # - openssl aes-256-cbc -K $encrypted_36030c2fae51_key -iv $encrypted_36030c2fae51_iv -in hex.config.enc -out ~/.hex/hex.config -d
  script:
    - mix credo --strict
    # https://github.com/jeremyjh/dialyxir#command-line-options
    # > exit immediately with same exit status as dialyzer. useful for CI
    - mix dialyzer --halt-exit-status
    - mix test
  deploy:
     # https://docs.travis-ci.com/user/deployment/script/
     # > `script` must be a scalar pointing to an executable file or command.
     provider: script
     # http://yaml.org/spec/1.2/spec.html#id2779048
     # `>-` indicates the line folding.
     script: >-
       mix deps.get &&
       (echo "$HEX_PASSPHRASE"\\nY | mix hex.publish) &&
       mix clean &&
       mix deps.clean --all
     on:
      tags: true
  """

  embed_template :dockerfile, ~S"""
  FROM elixir
  MAINTAINER <%= @user %>

  RUN mkdir /app
  ADD . /app
  WORKDIR /app

  RUN mix local.hex --force && \
      mix deps.get && \
      mix compile

  CMD ["iex"]
  """

  embed_text :gitignore, """
  # The directory Mix will write compiled artifacts to.
  /_build/

  # If you run "mix test --cover", coverage assets end up here.
  /cover/

  # The directory Mix downloads your dependencies sources to.
  /deps/

  # Where 3rd-party dependencies like ExDoc output generated docs.
  /doc/

  # Ignore .fetch files in case you like to edit your project deps locally.
  /.fetch

  # If the VM crashes, it generates a dump, let's ignore it too.
  erl_crash.dump

  # Also ignore archive artifacts (built via "mix archive.build").
  *.ez
  """

  embed_template :mixfile, """
  defmodule <%= @mod %>.Mixfile do
    use Mix.Project

    def project do
      [
        app: :<%= @app %>,
        version: "0.1.0",
        elixir: "~> <%= @version %>",
        start_permanent: Mix.env == :prod,
        deps: deps(),
        description: description(),
        package: package()
      ]
    end

    # Run "mix help compile.app" to learn about applications.
    def application do
      [
        extra_applications: [:logger]<%= @sup_app %>
      ]
    end

    # Run "mix help deps" to learn about dependencies.
    defp deps do
      [
        {:ex_doc, "~> 0.16", only: [:dev, :test], runtime: false},
        {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false}
      ]
    end

    defp description do
      "TODO: Add description"
    end

    defp package do
      [maintainers: ["<%= @user %>"],
       licenses: ["MIT"],
       links: %{"GitHub" => "https://github.com/<%= @user %>/<%= @app %>"}]
    end
  end
  """

  embed_template :mixfile_apps, """
  defmodule <%= @mod %>.Mixfile do
    use Mix.Project

    def project do
      [
        app: :<%= @app %>,
        version: "0.1.0",
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock",
        elixir: "~> <%= @version %>",
        start_permanent: Mix.env == :prod,
        deps: deps()
      ]
    end

    # Run "mix help compile.app" to learn about applications.
    def application do
      [
        extra_applications: [:logger]<%= @sup_app %>
      ]
    end

    # Run "mix help deps" to learn about dependencies.
    defp deps do
      [
        # {:dep_from_hexpm, "~> 0.3.0"},
        # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
        # {:sibling_app_in_umbrella, in_umbrella: true},
      ]
    end
  end
  """

  embed_template :mixfile_umbrella, """
  defmodule <%= @mod %>.Mixfile do
    use Mix.Project

    def project do
      [
        apps_path: "apps",
        start_permanent: Mix.env == :prod,
        deps: deps(),
        description: description(),
        package: package()
      ]
    end

    # Dependencies listed here are available only for this
    # project and cannot be accessed from applications inside
    # the apps folder.
    #
    # Run "mix help deps" for examples and options.
    defp deps do
      [
        {:ex_doc, "~> 0.16", only: [:dev, :test], runtime: false},
        {:credo, "~> 0.8", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false}
      ]
    end

    defp description do
      "TODO: Add description"
    end

    defp package do
      [maintainers: ["<%= @user %>"],
       licenses: ["MIT"],
       links: %{"GitHub" => "https://github.com/<%= @user %>/<%= @app %>"}]
    end
  end
  """

  embed_template :config, ~S"""
  # This file is responsible for configuring your application
  # and its dependencies with the aid of the Mix.Config module.
  use Mix.Config

  # This configuration is loaded before any dependency and is restricted
  # to this project. If another project depends on this project, this
  # file won't be loaded nor affect the parent project. For this reason,
  # if you want to provide default values for your application for
  # 3rd-party users, it should be done in your "mix.exs" file.

  # You can configure your application as:
  #
  #     config :<%= @app %>, key: :value
  #
  # and access this configuration in your application as:
  #
  #     Application.get_env(:<%= @app %>, :key)
  #
  # You can also configure a 3rd-party app:
  #
  #     config :logger, level: :info
  #

  # It is also possible to import configuration files, relative to this
  # directory. For example, you can emulate configuration per environment
  # by uncommenting the line below and defining dev.exs, test.exs and such.
  # Configuration from the imported file will override the ones defined
  # here (which is why it is important to import them last).
  #
  #     import_config "#{Mix.env}.exs"
  """

  embed_template :config_umbrella, ~S"""
  # This file is responsible for configuring your application
  # and its dependencies with the aid of the Mix.Config module.
  use Mix.Config

  # By default, the umbrella project as well as each child
  # application will require this configuration file, ensuring
  # they all use the same configuration. While one could
  # configure all applications here, we prefer to delegate
  # back to each application for organization purposes.
  import_config "../apps/*/config/config.exs"

  # Sample configuration (overrides the imported configuration above):
  #
  #     config :logger, :console,
  #       level: :info,
  #       format: "$date $time [$level] $metadata$message\n",
  #       metadata: [:user_id]
  """

  embed_text :config_dot_credo, """
  # This file contains the configuration for Credo and you are probably reading
  # this after creating it with `mix credo.gen.config`.
  #
  # If you find anything wrong or unclear in this file, please report an
  # issue on GitHub: https://github.com/rrrene/credo/issues
  #
  %{
    #
    # You can have as many configs as you like in the `configs:` field.
    configs: [
      %{
        #
        # Run any exec using `mix credo -C <name>`. If no exec name is given
        # "default" is used.
        #
        name: "default",
        #
        # These are the files included in the analysis:
        files: %{
          #
          # You can give explicit globs or simply directories.
          # In the latter case `**/*.{ex,exs}` will be used.
        #
          included: ["lib/", "src/", "web/", "apps/"],
          excluded: [~r"/_build/", ~r"/deps/"]
        },
        #
        # If you create your own checks, you must specify the source files for
        # them here, so they can be loaded by Credo before running the analysis.
        #
        requires: [],
        #
        # If you want to enforce a style guide and need a more traditional linting
        # experience, you can change `strict` to `true` below:
        #
        strict: false,
        #
        # If you want to use uncolored output by default, you can change `color`
        # to `false` below:
        #
        color: true,
        #
        # You can customize the parameters of any check by adding a second element
        # to the tuple.
        #
        # To disable a check put `false` as second element:
        #
        #     {Credo.Check.Design.DuplicatedCode, false}
        #
        checks: [
          {Credo.Check.Consistency.ExceptionNames},
          {Credo.Check.Consistency.LineEndings},
          {Credo.Check.Consistency.ParameterPatternMatching},
          {Credo.Check.Consistency.SpaceAroundOperators},
          {Credo.Check.Consistency.SpaceInParentheses},
          {Credo.Check.Consistency.TabsOrSpaces},

          # For some checks, like AliasUsage, you can only customize the priority
          # Priority values are: `low, normal, high, higher`
          #
          {Credo.Check.Design.AliasUsage, false},

          # For others you can set parameters

          # If you don't want the `setup` and `test` macro calls in ExUnit tests
          # or the `schema` macro in Ecto schemas to trigger DuplicatedCode, just
          # set the `excluded_macros` parameter to `[:schema, :setup, :test]`.
          #
          {Credo.Check.Design.DuplicatedCode, excluded_macros: []},

          # You can also customize the exit_status of each check.
          # If you don't want TODO comments to cause `mix credo` to fail, just
          # set this value to 0 (zero).
          #
          {Credo.Check.Design.TagTODO, exit_status: 2},
          {Credo.Check.Design.TagFIXME},

          {Credo.Check.Readability.FunctionNames},
          {Credo.Check.Readability.LargeNumbers},
          {Credo.Check.Readability.MaxLineLength, priority: :low, max_length: 120},
          {Credo.Check.Readability.ModuleAttributeNames},
          {Credo.Check.Readability.ModuleDoc},
          {Credo.Check.Readability.ModuleNames},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs},
          {Credo.Check.Readability.ParenthesesInCondition},
          {Credo.Check.Readability.PredicateFunctionNames},
          {Credo.Check.Readability.PreferImplicitTry},
          {Credo.Check.Readability.RedundantBlankLines},
          {Credo.Check.Readability.StringSigils},
          {Credo.Check.Readability.TrailingBlankLine},
          {Credo.Check.Readability.TrailingWhiteSpace},
          {Credo.Check.Readability.VariableNames},
          {Credo.Check.Readability.Semicolons},
          {Credo.Check.Readability.SpaceAfterCommas},

          {Credo.Check.Refactor.DoubleBooleanNegation},
          {Credo.Check.Refactor.CondStatements},
          {Credo.Check.Refactor.CyclomaticComplexity},
          {Credo.Check.Refactor.FunctionArity},
          {Credo.Check.Refactor.LongQuoteBlocks},
          {Credo.Check.Refactor.MatchInCondition},
          {Credo.Check.Refactor.NegatedConditionsInUnless},
          {Credo.Check.Refactor.NegatedConditionsWithElse},
          {Credo.Check.Refactor.Nesting},
          {Credo.Check.Refactor.PipeChainStart, false},
          {Credo.Check.Refactor.UnlessWithElse},

          {Credo.Check.Warning.BoolOperationOnSameValues},
          {Credo.Check.Warning.IExPry},
          {Credo.Check.Warning.IoInspect},
          {Credo.Check.Warning.LazyLogging},
          {Credo.Check.Warning.OperationOnSameValues},
          {Credo.Check.Warning.OperationWithConstantResult},
          {Credo.Check.Warning.UnusedEnumOperation},
          {Credo.Check.Warning.UnusedFileOperation},
          {Credo.Check.Warning.UnusedKeywordOperation},
          {Credo.Check.Warning.UnusedListOperation},
          {Credo.Check.Warning.UnusedPathOperation},
          {Credo.Check.Warning.UnusedRegexOperation},
          {Credo.Check.Warning.UnusedStringOperation},
          {Credo.Check.Warning.UnusedTupleOperation},
          {Credo.Check.Warning.RaiseInsideRescue},

          # Controversial and experimental checks (opt-in, just remove `, false`)
          #
          {Credo.Check.Refactor.ABCSize, false},
          {Credo.Check.Refactor.AppendSingleItem, false},
          {Credo.Check.Refactor.VariableRebinding, false},
          {Credo.Check.Warning.MapGetUnsafePass, false},
          {Credo.Check.Consistency.MultiAliasImportRequireUse, false},

          # Deprecated checks (these will be deleted after a grace period)
          #
          {Credo.Check.Readability.Specs, false},
          {Credo.Check.Warning.NameRedeclarationByAssignment, false},
          {Credo.Check.Warning.NameRedeclarationByCase, false},
          {Credo.Check.Warning.NameRedeclarationByDef, false},
          {Credo.Check.Warning.NameRedeclarationByFn, false},

          # Custom checks can be created using `mix credo.gen.check`.
          #
        ]
      }
    ]
  }
  """

  embed_template :lib, """
  defmodule <%= @mod %> do
    @moduledoc \"""
    Documentation for <%= @mod %>.
    \"""

    @doc \"""
    Hello world.

    ## Examples

        iex> <%= @mod %>.hello
        :world

    \"""
    def hello do
      :world
    end
  end
  """

  embed_template :lib_app, """
  defmodule <%= @mod %>.Application do
    # See https://hexdocs.pm/elixir/Application.html
    # for more information on OTP Applications
    @moduledoc false

    use Application

    def start(_type, _args) do
      # List all child processes to be supervised
      children = [
        # Starts a worker by calling: <%= @mod %>.Worker.start_link(arg)
        # {<%= @mod %>.Worker, arg},
      ]

      # See https://hexdocs.pm/elixir/Supervisor.html
      # for other strategies and supported options
      opts = [strategy: :one_for_one, name: <%= @mod %>.Supervisor]
      Supervisor.start_link(children, opts)
    end
  end
  """

  embed_template :test, """
  defmodule <%= @mod %>Test do
    use ExUnit.Case
    doctest <%= @mod %>

    test "greets the world" do
      assert <%= @mod %>.hello() == :world
    end
  end
  """

  embed_template :test_helper, """
  ExUnit.start()
  """
end
