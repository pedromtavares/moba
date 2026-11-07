# Sandbox owners hold a connection for the whole test. Reserve two connections
# for tests that start additional database clients instead of overrunning the pool.
pool_size = Keyword.fetch!(Moba.Repo.config(), :pool_size)
ExUnit.start(max_cases: min(System.schedulers_online(), max(1, pool_size - 2)))
Ecto.Adapters.SQL.Sandbox.mode(Moba.Repo, :manual)
