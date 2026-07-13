# Panorama360

App nativo iOS que captura panoramas **360° profissionais** guiando o usuário por uma esfera de pontos virtuais. Cada ponto alinhado dispara automaticamente quando o aparelho está estável e em foco; as fotos são costuradas numa imagem equiretangular e abertas num viewer 360° interativo.

**Escopo v1:** captura + costura (stitch) + viewer. Feed / login / marketplace / tokens / IA / social / backend ficam de fora de propósito — as costuras entre módulos estão limpas para eles.

[English docs](#stack) · [Como o sistema funciona (PT)](docs/Sistema.md) · [Architecture](docs/Architecture.md)

---

## Stack

SwiftUI · ARKit · RealityKit · AVFoundation · CoreMotion · Metal · CoreImage · Vision · Accelerate (vImage). OpenCV opcional. MVVM + Clean Architecture + Swift Concurrency (`actor`s, `AsyncStream`).

| | |
|--|--|
| **Deployment mínimo** | iOS 16.0, só iPhone |
| **Dispositivo** | iPhone físico com ARKit world tracking (A11+ recomendado) |
| **Bundle ID** | `com.teleport.panorama360` |
| **Projeto Xcode** | Gerado por [XcodeGen](https://github.com/yonaskolb/XcodeGen) a partir de `project.yml` |

O simulador **não** serve (sem câmera / ARKit).

---

## Dois caminhos para rodar

### A) Você tem Mac

```bash
brew install xcodegen
cd Panorama360
xcodegen generate
open Panorama360.xcodeproj
```

Assine com sua Apple Team → iPhone físico → ⌘R.  
Guia completo: [`docs/BuildingOnMac.md`](docs/BuildingOnMac.md).

### B) Só Windows (sem Mac)

O GitHub Actions (runner `macos-14`) compila o IPA na nuvem; no PC você assina e instala com **Sideloadly**.

1. Push deste repo no GitHub (**público** = minutos de build macOS ilimitados e grátis).
2. Aba **Actions** → workflow **Build IPA** (~5–8 min) → baixe o artifact `Panorama360-unsigned-ipa`.
3. Sideloadly + Apple ID grátis → USB → Trust no iPhone.

Passo a passo: [`docs/InstallingOnWindows.md`](docs/InstallingOnWindows.md).

---

## Como funciona (resumo)

1. Câmera em tela cheia, UI estilo Apple.
2. ARKit world-tracking + `CaptureGuide` projetam **60–100 pontos** em bandas de latitude **sobre a imagem ao vivo** (intrínsecos reais do ARKit).
3. Ponto: **verde** (idle) → **amarelo** (perto) → **azul** (alinhado). Retículo: branco → amarelo → **verde**.
4. Alinhado **e** estável **e** nítido → captura automática (haptic + pulse).
5. Barra: progresso (`28 de 80`) + ETA.
6. Último ponto → `PanoramaEngine`: undistort → match de exposição → projeção esférica Metal → equiretangular → disco.
7. Viewer 360°: arrastar, pinça, giroscópio.

### Por que o stitch padrão é “puro Apple”

O ARKit grava a **orientação exata** de cada foto; cada JPEG é projetado na esfera pela rotação — sem feature-matching cego. Mais robusto que um stitcher clássico e zero dependências de terceiros. OpenCV opcional: [`docs/OpenCVIntegration.md`](docs/OpenCVIntegration.md).

Detalhes do pipeline e camadas: [`docs/Architecture.md`](docs/Architecture.md) · visão em PT: [`docs/Sistema.md`](docs/Sistema.md).

---

## Layout do projeto

```
Panorama360/
├─ project.yml                      # fonte de verdade do target Xcode
├─ README.md
├─ LICENSE · CONTRIBUTING.md
├─ .github/workflows/build-ipa.yml  # CI → IPA não assinado
├─ docs/
│  ├─ Sistema.md                    # visão geral em português
│  ├─ Architecture.md               # camadas, gate, pipelines
│  ├─ BuildingOnMac.md
│  ├─ InstallingOnWindows.md
│  └─ OpenCVIntegration.md
└─ Panorama360/
   ├─ App/                          # @main + AppRouter
   ├─ Domain/                       # modelos puros
   ├─ Device/{Camera,Motion,AR,Capture}/
   ├─ Guide/                        # esfera + alinhamento
   ├─ Panorama/                     # stitch Metal (+ OpenCV opcional)
   ├─ Viewer/                       # renderer Metal + shaders
   ├─ Presentation/                 # ViewModels
   ├─ UI/                           # SwiftUI
   └─ Utilities/                    # math, storage, haptics, blur, log
```

Cada arquivo fica sob ~400 linhas.

---

## Documentação

| Doc | Conteúdo |
|-----|----------|
| [Sistema.md](docs/Sistema.md) | Explicação do produto e do pipeline (PT) |
| [Architecture.md](docs/Architecture.md) | Camadas, CaptureGate, concorrência |
| [BuildingOnMac.md](docs/BuildingOnMac.md) | XcodeGen, signing, build Release |
| [InstallingOnWindows.md](docs/InstallingOnWindows.md) | Actions + Sideloadly |
| [OpenCVIntegration.md](docs/OpenCVIntegration.md) | Stitcher opcional com OpenCV |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Regras de PR e estilo |

---

## Notas

- O código foi escrito sem toolchain Swift no Windows; espere ajustes menores de assinatura de API no primeiro build no Xcode.
- Qualidade final do 360 depende da higiene de captura: gire devagar, boa luz, sobreposição entre pontos.
- IPA via Actions é **não assinado** de propósito — o Sideloadly (ou Xcode) assina com a sua conta.

## Licença

[MIT](LICENSE)
