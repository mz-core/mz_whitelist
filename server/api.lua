MZWhitelist = MZWhitelist or {}
MZWhitelist.API = MZWhitelist.API or {}

local VALID_STATUS = {
  pending = true,
  approved = true,
  rejected = true,
  revoked = true
}

local ACTION_STATUS = {
  approve = 'approved',
  reject = 'rejected',
  revoke = 'revoked'
}

local function result(ok, data, err)
  return {
    ok = ok == true,
    data = ok == true and data or nil,
    error = ok == true and nil or tostring(err or 'unknown_error')
  }
end

local function integration()
  return type(Config.Integration) == 'table' and Config.Integration or {}
end

local function limits()
  return type(integration().Limits) == 'table' and integration().Limits or {}
end

local function mode()
  local value = tostring(Config.Mode or 'disabled'):lower()
  if value ~= 'observe' and value ~= 'enforce' then return 'disabled' end
  return value
end

local function trusted(resourceName)
  local resources = integration().TrustedResources
  return type(resourceName) == 'string'
    and type(resources) == 'table'
    and resources[resourceName] == true
end

local function sanitizeText(value, maxLength)
  if type(value) ~= 'string' then return '' end
  value = value:gsub('%c', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  maxLength = math.max(1, tonumber(maxLength) or 128)
  return #value > maxLength and value:sub(1, maxLength) or value
end

local function sanitizePublicId(value)
  if type(value) ~= 'string' then return nil end
  value = value:upper():gsub('%s+', '')
  if not value:match('^MWL%-[A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9][A-HJ-NP-Z2-9]$') then
    return nil
  end
  return value
end

local function publicId()
  local alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  local value = {}
  for index = 1, 8 do
    local position = math.random(1, #alphabet)
    value[index] = alphabet:sub(position, position)
  end
  return 'MWL-' .. table.concat(value)
end

local function getLicense(sourceId)
  for _, identifier in ipairs(GetPlayerIdentifiers(sourceId) or {}) do
    if type(identifier) == 'string' and identifier:sub(1, 8) == 'license:' then
      return identifier
    end
  end
  return nil
end

local function authorize(actorSource, permission)
  actorSource = tonumber(actorSource)
  if not actorSource or actorSource <= 0 or not GetPlayerName(actorSource) then
    return false, 'invalid_actor'
  end
  local coreResource = tostring(integration().CoreResource or 'mz_core')
  if GetResourceState(coreResource) ~= 'started' then return false, 'core_unavailable' end
  local ok, allowed = pcall(function()
    return exports[coreResource]:HasGlobalPermission(actorSource, permission)
  end)
  if not ok then return false, 'authorization_unavailable' end
  return allowed == true, allowed == true and nil or 'permission_denied'
end

local function dto(entry)
  return {
    publicId = entry.public_id,
    playerName = entry.player_name,
    status = entry.status,
    revision = tonumber(entry.revision),
    requestedAt = tonumber(entry.requested_at),
    decidedAt = tonumber(entry.decided_at),
    decidedBy = entry.decided_by,
    decisionReason = entry.decision_reason,
    lastAttemptAt = tonumber(entry.last_attempt_at)
  }
end

local function auditGlobal(actorSource, action, entry, reason)
  local coreResource = tostring(integration().CoreResource or 'mz_core')
  if GetResourceState(coreResource) ~= 'started' then return end
  pcall(function()
    exports[coreResource]:CreateDetailedLog('admin', 'admin.whitelist.' .. action, {
      actor = {
        type = 'player',
        source = actorSource,
        name = GetPlayerName(actorSource)
      },
      target = {
        type = 'whitelist',
        id = entry.public_id,
        name = entry.player_name
      },
      context = {
        resource = 'mz_whitelist',
        decision = action
      },
      meta = {
        publicId = entry.public_id,
        status = entry.status,
        reason = reason
      }
    })
  end)
end

function MZWhitelist.API.IsReady()
  return MZWhitelist.DB.IsReady()
end

function MZWhitelist.API.CheckConnection(sourceId, playerName, invokingResource)
  if not trusted(invokingResource) or invokingResource ~= 'mz_banguard' then
    return result(false, nil, 'untrusted_resource')
  end

  local currentMode = mode()
  if currentMode == 'disabled' then
    return result(true, {
      allowed = true,
      mode = currentMode,
      status = 'disabled'
    })
  end

  sourceId = tonumber(sourceId)
  if not sourceId or sourceId <= 0 or not GetPlayerName(sourceId) then
    return result(false, nil, 'invalid_player')
  end

  -- Break-glass do dono vem antes do banco para que uma indisponibilidade da
  -- whitelist nao tranque o operador supremo fora do servidor.
  if Config.OwnerBypass == true and IsPlayerAceAllowed(
    sourceId,
    tostring(Config.OwnerAce or 'group.mz_owner')
  ) then
    return result(true, {
      allowed = true,
      mode = currentMode,
      status = 'owner_bypass'
    })
  end

  local databaseReady, databaseError = MZWhitelist.DB.IsReady()
  if databaseReady ~= true then
    if currentMode == 'observe' then
      return result(true, {
        allowed = true,
        mode = currentMode,
        status = 'unavailable',
        warning = databaseError
      })
    end
    return result(false, nil, databaseError or 'database_unavailable')
  end

  local license = getLicense(sourceId)
  if not license then return result(false, nil, 'missing_license') end
  local operationOk, entry, operationError = pcall(function()
    local licenseHash = MZWhitelist.DB.HashLicense(license)
    license = nil
    if not licenseHash then return nil, 'hash_failed' end

    local now = os.time()
    playerName = sanitizeText(playerName or GetPlayerName(sourceId), 128)
    local resolved = MZWhitelist.DB.GetByHash(licenseHash)
    if not resolved then
      local createError
      for _ = 1, 3 do
        resolved, createError = MZWhitelist.DB.EnsurePending(
          licenseHash,
          publicId(),
          playerName,
          now
        )
        if resolved or createError ~= 'public_id_collision' then break end
      end
      if not resolved then return nil, createError or 'request_persistence_failed' end
    else
      MZWhitelist.DB.Touch(resolved.id, playerName, now)
    end
    return resolved
  end)

  if not operationOk or not entry then
    local failure = operationOk and operationError or 'database_operation_failed'
    if currentMode == 'observe' then
      return result(true, {
        allowed = true,
        mode = currentMode,
        status = tostring(failure or 'persistence_failed')
      })
    end
    return result(false, nil, failure or 'request_persistence_failed')
  end

  local status = tostring(entry.status or 'pending')
  local allowed = currentMode == 'observe' or status == 'approved'
  local message
  if not allowed then
    local template = status == 'rejected' and Config.Messages.Rejected
      or (status == 'revoked' and Config.Messages.Revoked or Config.Messages.Pending)
    message = string.format(template, entry.public_id)
  end

  return result(true, {
    allowed = allowed,
    mode = currentMode,
    status = status,
    publicId = entry.public_id,
    message = message
  })
end

function MZWhitelist.API.List(actorSource, filters, invokingResource)
  if not trusted(invokingResource) or invokingResource ~= 'mz_admin' then
    return result(false, nil, 'untrusted_resource')
  end
  local permission = integration().Permissions and integration().Permissions.View
  local allowed, authError = authorize(actorSource, permission)
  if not allowed then return result(false, nil, authError) end

  local databaseReady, databaseError = MZWhitelist.DB.IsReady()
  if databaseReady ~= true then return result(false, nil, databaseError) end

  filters = type(filters) == 'table' and filters or {}
  local status = type(filters.status) == 'string' and filters.status:lower() or nil
  if status and not VALID_STATUS[status] then return result(false, nil, 'invalid_status') end
  local search = sanitizeText(filters.search, limits().SearchMax or 80)
  if search == '' then search = nil end
  local page = math.max(1, math.floor(tonumber(filters.page) or 1))
  local maxPageSize = math.max(1, tonumber(limits().MaxPageSize) or 50)
  local pageSize = math.min(maxPageSize, math.max(1, math.floor(
    tonumber(filters.pageSize) or tonumber(limits().PageSize) or 25
  )))

  local rows, total = MZWhitelist.DB.List({
    status = status,
    search = search,
    pageSize = pageSize,
    offset = (page - 1) * pageSize
  })
  local items = {}
  for _, entry in ipairs(rows) do items[#items + 1] = dto(entry) end
  return result(true, {
    items = items,
    total = total,
    page = page,
    pageSize = pageSize,
    mode = mode()
  })
end

function MZWhitelist.API.Decide(actorSource, publicIdValue, action, reason, invokingResource)
  if not trusted(invokingResource) or invokingResource ~= 'mz_admin' then
    return result(false, nil, 'untrusted_resource')
  end
  local permission = integration().Permissions and integration().Permissions.Manage
  local allowed, authError = authorize(actorSource, permission)
  if not allowed then return result(false, nil, authError) end

  local databaseReady, databaseError = MZWhitelist.DB.IsReady()
  if databaseReady ~= true then return result(false, nil, databaseError) end

  publicIdValue = sanitizePublicId(publicIdValue)
  action = type(action) == 'string' and action:lower() or nil
  local nextStatus = action and ACTION_STATUS[action] or nil
  if not publicIdValue then return result(false, nil, 'invalid_public_id') end
  if not nextStatus then return result(false, nil, 'invalid_action') end

  reason = sanitizeText(reason, limits().ReasonMax or 256)
  if #reason < math.max(1, tonumber(limits().ReasonMin) or 3) then
    return result(false, nil, 'invalid_reason')
  end

  local entry = MZWhitelist.DB.GetByPublicId(publicIdValue)
  if not entry then return result(false, nil, 'not_found') end
  if tostring(entry.status) == nextStatus then return result(false, nil, 'already_in_state') end
  if action == 'reject' and tostring(entry.status) ~= 'pending' then
    return result(false, nil, 'invalid_transition')
  end
  if action == 'revoke' and tostring(entry.status) ~= 'approved' then
    return result(false, nil, 'invalid_transition')
  end

  local actorName = sanitizeText(GetPlayerName(actorSource), 128)
  local updated, transitionError = MZWhitelist.DB.Transition(
    entry,
    nextStatus,
    action,
    tonumber(actorSource),
    actorName,
    reason,
    os.time()
  )
  if not updated then return result(false, nil, transitionError) end
  auditGlobal(actorSource, action, updated, reason)
  return result(true, { entry = dto(updated) })
end

exports('IsReady', function()
  return MZWhitelist.API.IsReady()
end)

exports('CheckConnection', function(sourceId, playerName)
  return MZWhitelist.API.CheckConnection(sourceId, playerName, GetInvokingResource())
end)

exports('ListEntries', function(actorSource, filters)
  return MZWhitelist.API.List(actorSource, filters, GetInvokingResource())
end)

exports('Decide', function(actorSource, publicIdValue, action, reason)
  return MZWhitelist.API.Decide(actorSource, publicIdValue, action, reason, GetInvokingResource())
end)
