# BlackGold Project Runner V1

Ferramenta local Windows para executar tarefas de desenvolvimento autorizadas sem Desktop Commander.

## Instalacao
Use o instalador fixado por commit informado no chat.

## Arquitetura
- runner local headless em %LOCALAPPDATA%\BlackGoldProjectRunner
- control plane privado via GitHub
- Task Scheduler nativo do Windows a cada 1 minuto
- registro local de projetos permitidos
- resultados, heartbeats, screenshots Base64 e UI XML publicados no control plane privado

## Acoes permitidas
health, discover_projects, register_project, project_status, build_debug, lint,
start_emulator, install_debug, launch_app, screenshot,
build_install_launch_screenshot, apply_patch.

Nao existe acao para shell, CMD, PowerShell arbitrario ou execucao livre.

## Projeto inicial
Orcamento no Ponto
- raiz: E:\Orcamento_no_Ponto
- Android: 01_Android_App\orcamento_no_ponto
- AVD: Orcamento_no_Ponto_API35
- applicationId: br.com.lafamigliaplayworks.orcamentonoponto
