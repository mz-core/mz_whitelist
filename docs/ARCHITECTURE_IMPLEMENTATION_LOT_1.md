# Whitelist de entrada — implementação do Lote 1

Data: 2026-07-28.

## Autoridades

- `mz_whitelist`: estados, hash de identificação, solicitações, decisões e auditoria.
- `mz_banguard`: único coordenador do `playerConnecting` e dos deferrals.
- `mz_admin`: interface e pré-autorização; não acessa SQL.
- `mz_core`: permissões globais e logs administrativos sanitizados.
- `mz_menu`: apresentação visual.

O campo organizacional `mz_orgs.requires_whitelist` não participa deste domínio. Ele continua representando recrutamento controlado da organização.

## Estados

```text
pending  → approved
pending  → rejected
rejected → approved
revoked  → approved
approved → revoked
```

Rejeição somente parte de `pending`. Revogação somente parte de `approved`. Não há exclusão.

## Gate

`Config.Mode` aceita:

- `disabled`: nenhum acesso ao banco ou criação de solicitação;
- `observe`: cria/atualiza solicitação e sempre permite a conexão;
- `enforce`: permite apenas `approved`.

`group.mz_owner` possui bypass de recuperação configurável. Resource ausente não ativa whitelist; resource iniciado com contrato quebrado falha fechado no BanGuard. Em `observe`, indisponibilidade do banco não bloqueia a conexão. Em `enforce`, indisponibilidade bloqueia.

## Persistência

São criadas apenas tabelas totalmente ausentes:

- `mz_whitelist_entries`;
- `mz_whitelist_audit`.

Não há `ALTER`, `DROP`, migration destrutiva ou exclusão automática. Schema existente incompatível deixa o resource indisponível.

A license não é persistida. `SHA2(license, 256)` produz `license_hash`, usado apenas para match exato. O Public ID `MWL-XXXXXXXX` é a referência administrativa.

Decisão e auditoria são executadas na mesma transação. `revision` e o índice único `(entry_id, entry_revision)` impedem duas decisões concorrentes de produzirem duas auditorias válidas para a mesma revisão.

## API

Exports:

```lua
exports['mz_whitelist']:IsReady()
exports['mz_whitelist']:CheckConnection(source, playerName)
exports['mz_whitelist']:ListEntries(actorSource, filters)
exports['mz_whitelist']:Decide(actorSource, publicId, action, reason)
```

`CheckConnection` aceita somente `mz_banguard`. Administração aceita somente `mz_admin` e revalida no `mz_core`:

- `staff.whitelist.view`;
- `staff.whitelist.manage`.

DTOs não contêm license, hash, IP, tokens ou identificadores alternativos.

O painel lista 25 entradas por página, preserva status/busca durante navegação e aceita busca somente por Public ID ou nome.

## Compatibilidade

- o BanGuard continua com um único `playerConnecting`;
- banimentos são verificados antes da whitelist, evitando criar solicitação para banido;
- cloud, autoban e retenção não são ativados;
- cargos Staff existentes não são modificados pelo seed;
- frontend do `/admin` permanece baseado em `mz_menu`;
- nenhum React, Vite ou TypeScript foi introduzido.

## Runtime

O código não fica aprovado em runtime pelos harnesses. Seguir `RUNTIME_CHECKLIST_LOT_1.md`, começando obrigatoriamente em `observe`.
