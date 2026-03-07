ExUnit.start(exclude: [:integration])
# Disable background tab refresh polling during tests to prevent
# background API calls from interfering with Bypass mocks.
Application.put_env(:jarga_admin, :disable_tab_refresh, true)
