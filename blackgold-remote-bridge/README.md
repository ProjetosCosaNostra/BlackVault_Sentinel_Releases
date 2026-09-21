# BlackGold Remote Bridge V1.1

Sistema próprio de acesso ao Windows para os projetos BlackGold.

- Sem porta de entrada aberta.
- O PC faz apenas conexão de saída com um repositório GitHub privado.
- Execução headless em tarefa agendada.
- Atalhos LIGAR / DESLIGAR na Área de Trabalho.
- Suporta screenshot, clique, digitação, janelas, arquivos, PowerShell, ADB e screenshot do Android.

## Instalação única

Abra o PowerShell e execute:

```powershell
irm 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/blackgold-remote-bridge-v1_1/blackgold-remote-bridge/install.ps1' | iex
```

Destino: `E:\BlackGold_Remote_Bridge`

Depois da instalação o agente passa a monitorar a branch privada `blackgold-remote-bridge-v1` do repositório `ProjetosCosaNostra/BlackVault_Sentinel`.
