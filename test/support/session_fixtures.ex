defmodule FirehoseSimulator.SessionFixtures do
  @moduledoc false

  def session(id, next_request_at, expires_at) do
    %{
      id: id,
      user_id: id,
      duration_ms: expires_at - next_request_at,
      request_interval_ms: 100,
      next_request_at: next_request_at,
      expires_at: expires_at,
      started_at: next_request_at - 100
    }
  end
end
