# Como o sistema funciona (visão geral)

Este documento explica o Panorama360 em português, do ponto de vista do produto e do pipeline técnico.

## O que o app faz

O Panorama360 transforma um iPhone comum numa **câmera 360° guiada**:

1. Mostra a câmera em tela cheia.
2. Projeta no espaço virtual dezenas de **pontos de captura** ao redor da esfera (60–100, em bandas de latitude).
3. O usuário gira o corpo; quando o telefone aponta para um ponto, está estável e a imagem está nítida, a foto **dispara sozinha**.
4. Ao terminar, as fotos são costuradas numa imagem **equiretangular** (o formato padrão de panoramas 360°).
5. O viewer Metal abre automaticamente: arraste, pinça e incline o aparelho para olhar ao redor.

Não precisa de câmera 360 dedicada (Insta360, Theta, etc.) — só iPhone com ARKit.

## Por que a costura é confiável

Em stitchers clássicos (OpenCV “cego”), o software tenta **adivinhar** como as fotos se encaixam via features. Aqui o ARKit já sabe a **orientação exata** de cada disparo. Cada JPEG é projetado na esfera pela rotação gravada — warp determinístico + blend. Resultado: menos falhas de alinhamento e zero dependência de terceiros no build padrão.

## Experiência de captura (UX)

| Estado do ponto | Cor | Significado |
|-----------------|-----|-------------|
| Idle | Verde | Ainda não capturado |
| Near | Amarelo | Você está se aproximando do alvo |
| Aligned | Azul | Alinhado — aguardando estabilidade / nitidez |

O retículo central espelha: branco → amarelo → **verde** (pronto para disparar).

Barra inferior: progresso (`28 de 80`) + ETA estimado.

Feedback: haptic + pulse visual a cada foto.

## Módulos principais

| Pasta | Responsabilidade |
|-------|------------------|
| `App/` | Entrada `@main` e roteador de telas |
| `Domain/` | Modelos puros (`PanoramaSession`, `CapturePoint`, …) |
| `Device/` | Câmera, ARKit, motion, gate de auto-disparo |
| `Guide/` | Geração da esfera de pontos + máquina de alinhamento |
| `Panorama/` | Pipeline de stitch (Metal; OpenCV opcional) |
| `Viewer/` | Renderer Metal 360° + shaders |
| `Presentation/` | ViewModels (estado da UI) |
| `UI/` | Views SwiftUI |
| `Utilities/` | Storage, blur, haptics, math, log |

## Fluxo de dados resumido

```
Usuário gira o iPhone
        ↓
ARKit + CoreMotion → orientação + estabilidade
        ↓
CaptureGuide decide qual ponto está alinhado
        ↓
CaptureGate libera o disparo (ângulo + foco + exposição + nitidez)
        ↓
AVFoundation grava JPEG + metadados (quatérnio, intrínsecos)
        ↓
SessionStore grava no disco
        ↓
(último ponto) → PanoramaEngine → equiretangular
        ↓
Viewer Metal
```

## Requisitos de hardware

- **iOS 16+**, iPhone físico (simulador sem câmera/ARKit).
- Chip **A11+** recomendado (world tracking estável).
- Permissões: Câmera, Motion; opcionalmente Fotos para salvar o panorama.

## Instalar sem Mac

O código iOS **só compila em macOS**. Sem Mac próprio:

1. Push no GitHub → Actions (`Build IPA`) gera IPA não assinado na nuvem.
2. No Windows, **Sideloadly** assina com Apple ID grátis e instala via USB.

Guia completo: [InstallingOnWindows.md](InstallingOnWindows.md).

## Escopo v1 vs futuro

**Incluído:** captura guiada, stitch, viewer local.

**Fora de escopo (v1):** login, feed social, marketplace, tokens, IA generativa, backend na nuvem. As costuras entre módulos foram deixadas limpas para esses recursos entrarem depois.
