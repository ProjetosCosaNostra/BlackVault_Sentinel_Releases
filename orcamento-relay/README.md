# Orçamento no Ponto — Relay V3

Canal seguro de sincronização por arquivos para o projeto `E:\Orcamento_no_Ponto`.

## Instalar / corrigir
Abra PowerShell e execute:

```powershell
irm https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/orcamento-relay-v3/orcamento-relay/install.ps1 | iex
```

## Desativar
```powershell
irm https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/orcamento-relay-v3/orcamento-relay/uninstall.ps1 | iex
```

## Limites de segurança
- usa somente o clone privado já autenticado em `%LOCALAPPDATA%\BlackGold\OrcamentoRelay\repo`;
- trabalha somente com `E:\Orcamento_no_Ponto`;
- recebe patches como arquivos, nunca comandos;
- o cliente cria backup antes de aplicar patch;
- execução agendada a cada 5 minutos em janela oculta;
- não altera outros projetos nem outros emuladores.
