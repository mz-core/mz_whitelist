# mz_whitelist

Whitelist de entrada server-side integrada à framework MZ.

## Ordem

```cfg
ensure oxmysql
ensure mz_core
ensure mz_whitelist
ensure mz_banguard
ensure mz_admin
```

O `mz_banguard` continua como único coordenador de `playerConnecting`. Quando `mz_whitelist` está iniciado, o BanGuard consulta seu export antes de liberar a conexão.

## Modos

```lua
Config.Mode = 'disabled' -- não consulta nem cria solicitações
Config.Mode = 'observe'  -- registra solicitações, mas permite entrada
Config.Mode = 'enforce'  -- exige status approved
```

Comece em `observe`. Mude para `enforce` somente depois de aprovar o Owner, validar o painel e manter o bypass `group.mz_owner`.

## Administração

O `/admin` mostra:

- pendentes;
- aprovadas;
- recusadas;
- revogadas;
- ações de aprovar, recusar e revogar com motivo.

Permissões:

```text
staff.whitelist.view
staff.whitelist.manage
```

O Owner recebe autoridade pelo ACE global. Cargos Staff já persistidos não são alterados automaticamente; conceda as novas permissões pelo gerenciador Staff.

## Privacidade

A license é usada somente em memória e convertida para SHA-256 pelo banco. A tabela persiste `license_hash`, nunca a license bruta. DTOs do painel não retornam license nem hash.

Não existe hard delete. Decisões alteram estado e gravam auditoria transacional por revisão.

Veja [docs/ARCHITECTURE_IMPLEMENTATION_LOT_1.md](docs/ARCHITECTURE_IMPLEMENTATION_LOT_1.md) e [docs/RUNTIME_CHECKLIST_LOT_1.md](docs/RUNTIME_CHECKLIST_LOT_1.md).
