# Checklist runtime — whitelist Lote 1

Itens não executados não podem ser marcados como aprovados.

## Preparação

- [ ] Usar staging, sem VPS ou produção.
- [ ] Fazer backup verificável do banco de staging.
- [ ] Confirmar `Config.Mode = 'observe'`.
- [ ] Confirmar `Config.OwnerBypass = true` e `OwnerAce = 'group.mz_owner'`.
- [ ] Iniciar `oxmysql`, `mz_core`, `mz_whitelist`, `mz_banguard` e `mz_admin` nessa ordem.
- [ ] Confirmar `[mz_whitelist] ready mode=observe`.
- [ ] Confirmar criação somente de `mz_whitelist_entries` e `mz_whitelist_audit`.

## Observe

- [x] Player novo conecta normalmente.
- [x] A conexão cria uma única solicitação `pending`.
- [ ] Reconexão preserva o mesmo `MWL-XXXXXXXX`.
- [ ] Nome e `last_attempt_at` são atualizados.
- [ ] License bruta não existe nas duas tabelas.
- [x] `/admin → Whitelist → Pendentes` mostra DTO sem license/hash.
- [ ] Staff sem `staff.whitelist.view` não vê nem lista o módulo.
- [ ] Staff com view e sem manage consulta, mas não decide.
- [x] Staff com manage aprova com motivo.
- [x] Auditoria própria e log global não contêm license/hash.

## Enforce

- [x] Aprovar o operador de teste antes de alterar o modo.
- [x] Alterar para `Config.Mode = 'enforce'` e reiniciar somente `mz_whitelist`.
- [x] Owner conecta por bypass mesmo sem registro.
- [x] Registro `approved` conecta.
- [x] Player novo recebe bloqueio com o mesmo Public ID criado.
- [x] `pending` é bloqueado.
- [x] `rejected` é bloqueado.
- [x] `revoked` é bloqueado na próxima conexão.
- [x] Reaprovar `rejected` ou `revoked` libera a próxima conexão.
- [ ] Ban ativo continua sendo recusado antes da whitelist.

## Segurança e concorrência

- [ ] Resource diferente de `mz_banguard` não chama `CheckConnection`.
- [ ] Resource diferente de `mz_admin` não lista ou decide.
- [ ] Public ID inválido, ação inválida e motivo curto são recusados.
- [ ] Duas decisões concorrentes não geram duas revisões válidas.
- [ ] Falha da transação mantém estado e auditoria anteriores.
- [ ] Com `mz_whitelist` parado, o servidor mantém o comportamento anterior sem whitelist.
- [ ] Com resource iniciado e banco indisponível, `observe` permite e `enforce` falha fechado.

## Evidência

Registrar Public ID, cargo/permissões, estado anterior/posterior, revisão, auditoria e resultado da conexão. Não copiar license ou hash para a evidência.

Smoke de carregamento aprovado pelo operador em 2026-07-28: após atualizar os resources, o `/admin` abriu com o módulo Whitelist sem o erro de builder client ausente. Naquele aceite inicial, os fluxos funcionais ainda permaneciam separados.

Fluxo funcional aprovado pelo operador em 2026-07-29: modo `observe`, criação de pendência, aprovação pelo `/admin`, ativação de `enforce`, entrada de aprovado, bloqueio de pendente/recusado/revogado, reaprovação, bypass do Owner e ausência de license/hash no painel e auditoria. Concorrência, falhas transacionais, indisponibilidade e negativas de permissão/resource continuam independentes.
