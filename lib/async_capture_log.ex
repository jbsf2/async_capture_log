defmodule AsyncCaptureLog do

  defstruct [
    :string_io,
    :level,
    :formatter
  ]

  @typep log_event :: :logger.log_event()
  @typep handler_config :: :logger.handler_config()
  @typep formatter :: {module(), :logger.formatter_config()}
  @typep level :: :logger.level()

  @typep log_capture :: %__MODULE__{
    string_io: StringIO.t(),
    level: level(),
    formatter: formatter()
  }

  @handler_name :async_capture_log

  @spec capture_log(keyword(), (() -> any())) :: String.t()
  def capture_log(opts \\ [], function) do
    {_result, output} = with_log(opts, function)
    output
  end

  @spec with_log(keyword(), (() -> any())) :: {any(), String.t()}
  def with_log(opts \\ [], function) do
    :ok = ensure_handler_added()

    log_captures = ProcessTree.get(:async_log_captures) || []

    {:ok, string_io} = StringIO.open("")
    new_log_capture = %__MODULE__{
      string_io: string_io,
      level: Keyword.get(opts, :level, :all),
      formatter: Logger.default_formatter(opts)
    }
    log_captures = [new_log_capture | log_captures]

    Process.put(:async_log_captures, log_captures)

    try do
      try do
        function.()
      after
        :ok = Logger.flush()
        Process.put(:async_log_captures, List.delete_at(log_captures, 0))
      end
    catch
      kind, reason ->
        _ = StringIO.close(string_io)
        :erlang.raise(kind, reason, __STACKTRACE__)
    else
      result ->
        {:ok, {"", output}} = StringIO.close(string_io)
        {result, output}
    end
  end

  @spec log(log_event(), handler_config()) :: :ok
  def log(log_event, _config) do
    log_captures = ProcessTree.get(:async_log_captures) || []

    case log_captures do
      [] ->
        :ok

      captures ->
        Enum.each(captures, fn log_capture ->
          log_event(log_capture, log_event)
        end)
    end

    :ok
  end

  @spec log_event(log_capture(), log_event()) :: :ok
  defp log_event(log_capture, log_event) do
    if level_high_enough?(log_event.level, log_capture.level) do
      formatted_message = format_event(log_capture.formatter, log_event)
      IO.write(log_capture.string_io, formatted_message)
    end
  end

  @spec ensure_handler_added() :: :ok
  defp ensure_handler_added() do
    {:ok, config} = :logger.get_handler_config(:default)
    config = %{config | id: @handler_name, module: __MODULE__}

    case :logger.add_handler(@handler_name, __MODULE__, config) do
      :ok ->
        :ok

      {:error, {:already_exist, _}} ->
        :ok
    end
  end

  @spec format_event(formatter(), log_event()) :: String.t()
  defp format_event({formatter_module, formatter_config}, log_event) do
    formatter_module.format(log_event, formatter_config)
  end

  @spec level_high_enough?(level(), level()) :: boolean()
  defp level_high_enough?(event_level, configured_level) do
    :logger.compare_levels(event_level, configured_level) in [:gt, :eq]
  end

end
