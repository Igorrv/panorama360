# Instalação no iPhone a partir do Windows

Você não tem Mac — tudo bem. O build roda num Mac na nuvem (GitHub Actions); **assinatura e instalação são 100% no Windows** com Sideloadly.

Versão em inglês (espelho): o fluxo abaixo é o canônico; mantenha as duas sincronizadas se alterar passos.

## Parte 1 — Build do IPA (automático, Mac na nuvem)

1. Faça push deste projeto para um repositório GitHub.
   **Deixe o repo público** → minutos de build macOS ilimitados e grátis.
2. O workflow **Build IPA** roda a cada push em `main`/`master`. Acompanhe em **Actions**. Também dá para disparar manualmente: *Actions → Build IPA → Run workflow*.
3. Quando ficar verde: abra o run → **Artifacts** → baixe `Panorama360-unsigned-ipa`. Descompacte → `Panorama360-unsigned.ipa`.

O IPA vem **sem assinatura** de propósito — o Sideloadly assina com seu Apple ID no passo seguinte.

## Parte 2 — Assinar + instalar (Sideloadly, Apple ID grátis)

> Instalações com Apple ID grátis valem **7 dias** e no máximo **3 apps** sideloaded por vez. Refaça a Parte 2 semanalmente para renovar (o AltStore automatiza isso).

1. Instale o **Sideloadly**: <https://sideloadly.io> (Windows).
2. Precisa dos drivers USB da Apple. Se o iPhone não aparecer, instale o **iTunes fora da Microsoft Store** (<https://www.apple.com/itunes/> — vem com "Apple Mobile Device Support"), ou deixe o instalador do Sideloadly cuidar disso.
3. Conecte o **iPhone no PC via USB**. No telefone: **Confiar neste computador**.
4. Abra o Sideloadly:
   - **IPA**: arraste `Panorama360-unsigned.ipa`.
   - **Apple ID**: o *mesmo* Apple ID grátis logado no iPhone.
   - Escolha o iPhone na lista.
   - **Start**.
   - Se houver 2FA, aprove no dispositivo confiável e digite o código de 6 dígitos.
5. No iPhone: **Ajustes → Geral → VPN e gerenciamento de dispositivo** → perfil do seu Apple ID → **Confiar**.
6. Ícone do Panorama360 na home. Abra, permita **Câmera** e **Movimento**, e capture.

## Depois de mudar o código

Push → Actions rebuilda o IPA → repita a Parte 2 com o IPA novo. O Sideloadly reinstala em ~30 s.

## Problemas comuns

| Sintoma | Solução |
|---------|---------|
| “App cannot be verified” / ícone cinza | Passo 5 (Confiar no perfil) |
| Sideloadly não vê o iPhone | iTunes non-Store + cabo/porta USB |
| Build vermelho no Actions | Abra o log do step; costuma ser ajuste de API Swift — cole o erro e corrija |
| App expira em 7 dias | Limite do Apple ID grátis; re-sideload ou conta Dev US$99/ano (TestFlight = 1 ano) |

## Relacionado

- Visão do sistema: [Sistema.md](Sistema.md)
- Build no Mac: [BuildingOnMac.md](BuildingOnMac.md)
- Workflow: `.github/workflows/build-ipa.yml`
