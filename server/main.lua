CreateThread(function()
  local ok, err = MZWhitelist.DB.Initialize()
  if ok then
    print(('[mz_whitelist] ready mode=%s'):format(tostring(Config.Mode)))
    return
  end
  print(('[mz_whitelist] unavailable error=%s'):format(tostring(err)))
end)
