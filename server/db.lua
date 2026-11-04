MZWhitelist = MZWhitelist or {}
MZWhitelist.DB = MZWhitelist.DB or {}

local ready = false
local readyError = 'not_initialized'

local TABLE_STATEMENTS = {
  [[CREATE TABLE IF NOT EXISTS mz_whitelist_entries (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    public_id VARCHAR(16) NOT NULL,
    license_hash CHAR(64) NOT NULL,
    player_name VARCHAR(128) NOT NULL DEFAULT '',
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    revision BIGINT UNSIGNED NOT NULL DEFAULT 1,
    requested_at BIGINT UNSIGNED NOT NULL,
    decided_at BIGINT UNSIGNED NULL,
    decided_by VARCHAR(128) NULL,
    decision_reason VARCHAR(256) NULL,
    last_attempt_at BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_mz_whitelist_public_id (public_id),
    UNIQUE KEY uq_mz_whitelist_license_hash (license_hash),
    KEY idx_mz_whitelist_status_requested (status, requested_at),
    KEY idx_mz_whitelist_player_name (player_name)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
  [[CREATE TABLE IF NOT EXISTS mz_whitelist_audit (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    entry_id BIGINT UNSIGNED NOT NULL,
    entry_revision BIGINT UNSIGNED NOT NULL,
    public_id VARCHAR(16) NOT NULL,
    action VARCHAR(32) NOT NULL,
    actor_source INT NULL,
    actor_name VARCHAR(128) NOT NULL,
    previous_status VARCHAR(16) NOT NULL,
    next_status VARCHAR(16) NOT NULL,
    reason VARCHAR(256) NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    UNIQUE KEY uq_mz_whitelist_audit_revision (entry_id, entry_revision),
    KEY idx_mz_whitelist_audit_public_id (public_id, created_at),
    KEY idx_mz_whitelist_audit_action (action, created_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]
}

local function validateSchema()
  local ok, result = pcall(function()
    MySQL.single.await([[
      SELECT id, public_id, license_hash, player_name, status, revision,
             requested_at, decided_at, decided_by, decision_reason, last_attempt_at
      FROM mz_whitelist_entries
      LIMIT 1
    ]])
    MySQL.single.await([[
      SELECT id, entry_id, entry_revision, public_id, action, actor_source,
             actor_name, previous_status, next_status, reason, created_at
      FROM mz_whitelist_audit
      LIMIT 1
    ]])
    return true
  end)
  return ok and result == true, ok and nil or tostring(result)
end

function MZWhitelist.DB.Initialize()
  ready = false
  readyError = 'initializing'

  if Config.Database and Config.Database.AutoCreateMissingTables == true then
    for _, statement in ipairs(TABLE_STATEMENTS) do
      local ok, err = pcall(MySQL.query.await, statement)
      if not ok then
        readyError = 'schema_create_failed:' .. tostring(err)
        return false, readyError
      end
    end
  end

  local valid, validationError = validateSchema()
  if not valid then
    readyError = 'schema_invalid:' .. tostring(validationError)
    return false, readyError
  end

  ready = true
  readyError = nil
  return true
end

function MZWhitelist.DB.IsReady()
  return ready, readyError
end

function MZWhitelist.DB.HashLicense(license)
  if type(license) ~= 'string' or license == '' then return nil end
  local ok, value = pcall(function()
    return MySQL.scalar.await('SELECT SHA2(?, 256)', { license })
  end)
  value = ok and type(value) == 'string' and value:lower() or nil
  if not value or not value:match('^[a-f0-9]+$') or #value ~= 64 then return nil end
  return value
end

function MZWhitelist.DB.GetByHash(licenseHash)
  return MySQL.single.await([[
    SELECT id, public_id, player_name, status, revision, requested_at,
           decided_at, decided_by, decision_reason, last_attempt_at
    FROM mz_whitelist_entries
    WHERE license_hash = ?
    LIMIT 1
  ]], { licenseHash })
end

function MZWhitelist.DB.GetByPublicId(publicId)
  return MySQL.single.await([[
    SELECT id, public_id, player_name, status, revision, requested_at,
           decided_at, decided_by, decision_reason, last_attempt_at
    FROM mz_whitelist_entries
    WHERE public_id = ?
    LIMIT 1
  ]], { publicId })
end

function MZWhitelist.DB.EnsurePending(licenseHash, publicId, playerName, now)
  local ok = pcall(function()
    MySQL.insert.await([[
      INSERT INTO mz_whitelist_entries
        (public_id, license_hash, player_name, status, revision, requested_at, last_attempt_at)
      VALUES (?, ?, ?, 'pending', 1, ?, ?)
    ]], { publicId, licenseHash, playerName, now, now })
  end)
  if ok then return MZWhitelist.DB.GetByHash(licenseHash) end

  -- Concorrencia da mesma license retorna o registro vencedor. Uma colisao
  -- apenas do public_id nunca atualiza o registro de outra pessoa.
  local existing = MZWhitelist.DB.GetByHash(licenseHash)
  if existing then
    MZWhitelist.DB.Touch(existing.id, playerName, now)
    return existing
  end
  return nil, 'public_id_collision'
end

function MZWhitelist.DB.Touch(entryId, playerName, now)
  local ok = pcall(function()
    MySQL.update.await([[
      UPDATE mz_whitelist_entries
      SET player_name = ?, last_attempt_at = ?
      WHERE id = ?
    ]], { playerName, now, entryId })
  end)
  return ok
end

function MZWhitelist.DB.List(filters)
  filters = type(filters) == 'table' and filters or {}
  local clauses = {}
  local parameters = {}

  if filters.status then
    clauses[#clauses + 1] = 'status = ?'
    parameters[#parameters + 1] = filters.status
  end
  if filters.search then
    clauses[#clauses + 1] = '(public_id LIKE ? OR player_name LIKE ?)'
    parameters[#parameters + 1] = '%' .. filters.search .. '%'
    parameters[#parameters + 1] = '%' .. filters.search .. '%'
  end

  local where = #clauses > 0 and (' WHERE ' .. table.concat(clauses, ' AND ')) or ''
  local countRow = MySQL.single.await(
    'SELECT COUNT(1) AS total FROM mz_whitelist_entries' .. where,
    parameters
  )
  local queryParameters = {}
  for index = 1, #parameters do queryParameters[index] = parameters[index] end
  queryParameters[#queryParameters + 1] = filters.pageSize
  queryParameters[#queryParameters + 1] = filters.offset

  local rows = MySQL.query.await([[
    SELECT id, public_id, player_name, status, revision, requested_at,
           decided_at, decided_by, decision_reason, last_attempt_at
    FROM mz_whitelist_entries
  ]] .. where .. [[
    ORDER BY requested_at DESC, id DESC
    LIMIT ? OFFSET ?
  ]], queryParameters) or {}

  return rows, tonumber(countRow and countRow.total) or 0
end

function MZWhitelist.DB.Transition(entry, nextStatus, action, actorSource, actorName, reason, now)
  local previousStatus = tostring(entry.status)
  local previousRevision = math.max(1, tonumber(entry.revision) or 1)
  local nextRevision = previousRevision + 1
  local statements = {
    {
      query = [[
        UPDATE mz_whitelist_entries
        SET status = ?, revision = ?, decided_at = ?, decided_by = ?, decision_reason = ?
        WHERE id = ? AND revision = ? AND status = ?
      ]],
      parameters = {
        nextStatus,
        nextRevision,
        now,
        actorName,
        reason,
        entry.id,
        previousRevision,
        previousStatus
      }
    },
    {
      query = [[
        INSERT INTO mz_whitelist_audit
          (entry_id, entry_revision, public_id, action, actor_source, actor_name,
           previous_status, next_status, reason, created_at)
        SELECT id, revision, public_id, ?, ?, ?, ?, ?, ?, ?
        FROM mz_whitelist_entries
        WHERE id = ? AND revision = ? AND status = ?
      ]],
      parameters = {
        action,
        actorSource,
        actorName,
        previousStatus,
        nextStatus,
        reason,
        now,
        entry.id,
        nextRevision,
        nextStatus
      }
    }
  }

  if MySQL.transaction.await(statements) ~= true then
    return nil, 'persistence_failed'
  end

  local updated = MZWhitelist.DB.GetByPublicId(entry.public_id)
  if not updated
    or tonumber(updated.revision) ~= nextRevision
    or tostring(updated.status) ~= nextStatus then
    return nil, 'revision_conflict'
  end
  return updated
end
