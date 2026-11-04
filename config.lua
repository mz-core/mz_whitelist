Config = {}

Config.Version = '1.0.0'
Config.OwnerAce = 'group.mz_owner'
Config.OwnerBypass = true

-- disabled: nao consulta nem cria solicitacoes.
-- observe: cria/atualiza solicitacoes, mas nao bloqueia conexoes.
-- enforce: somente registros approved podem conectar.
Config.Mode = 'observe'

Config.Database = {
  AutoCreateMissingTables = true
}

Config.Integration = {
  CoreResource = 'mz_core',
  TrustedResources = {
    mz_admin = true,
    mz_banguard = true
  },
  Permissions = {
    View = 'staff.whitelist.view',
    Manage = 'staff.whitelist.manage'
  },
  Limits = {
    PageSize = 25,
    MaxPageSize = 50,
    ReasonMin = 3,
    ReasonMax = 256,
    SearchMax = 80
  }
}

Config.Messages = {
  Pending = 'Sua whitelist esta pendente. Codigo: %s',
  Rejected = 'Sua whitelist foi recusada. Codigo: %s',
  Revoked = 'Sua whitelist foi revogada. Codigo: %s',
  Unavailable = 'O sistema de whitelist esta temporariamente indisponivel.'
}
