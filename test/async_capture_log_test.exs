defmodule AsyncCaptureLogTest do
  use ExUnit.Case

  require Logger
  import AsyncCaptureLog

  test "no output" do
    assert capture_log(fn -> nil end) == ""
  end

  test "output" do
    assert capture_log(fn -> Logger.info("here") end) =~ "[info] here\n"
  end

  test "assert inside" do
    try do
      capture_log(fn ->
        assert false
      end)
    rescue
      error in [ExUnit.AssertionError] ->
        assert error.message == "Expected truthy, got false"
    end
  end

  test "level aware" do
    assert capture_log([level: :warning], fn ->
             Logger.info("here")
           end) == ""
  end

  test "log tracking" do
    logged =
      capture_log(fn ->
        Logger.info("one")

        logged = capture_log(fn -> Logger.error("one") end)
        send(test = self(), {:nested, logged})

        Logger.warning("two")

        Task.start(fn ->
          Logger.debug("three")
          send(test, :done)
        end)

        receive do: (:done -> :ok)
      end)

    assert logged
    assert logged =~ "[info] one\n"
    assert logged =~ "[warning] two\n"
    assert logged =~ "[debug] three\n"
    assert logged =~ "[error] one\n"

    receive do
      {:nested, logged} ->
        assert logged =~ "[error] one\n"
        refute logged =~ "[warning] two\n"
    end
  end

  describe "with_log/2" do
    test "returns the result and the log" do
      {result, log} =
        with_log(fn ->
          Logger.error("calculating...")
          2 + 2
        end)

      assert result == 4
      assert log =~ "calculating..."
    end

    test "respects the :format, :metadata, and :colors options" do
      options = [format: "$metadata| $message", metadata: [:id], colors: [enabled: false]]

      assert {4, log} =
               with_log(options, fn ->
                 Logger.info("hello", id: 123)
                 2 + 2
               end)

      assert log == "id=123 | hello"
    end
  end
end
