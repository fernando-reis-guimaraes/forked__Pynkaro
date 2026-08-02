# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é

Pynkaro é um assistente de voz para macOS (protótipo de linha de comando, Swift Package). Fluxo: detecção local da wake word "Píncaro" → gravação da pergunta → transcrição pelo macOS ou opcionalmente pela OpenAI → pergunta à API da Anthropic (Claude, com busca na web) → resposta falada (OpenAI, ElevenLabs ou voz do sistema) com avatar animado na tela e lip sync.

## Comandos

```bash
swift build            # compila
swift test             # testa rotas, requests/respostas OpenAI e detecção de silêncio
swift run -c release   # roda em modo desenvolvimento (app de menu bar)
./make_app.sh          # monta o Pynkaro.app (bundle com Info.plist, recursos e assinatura ad-hoc)
```

Não há linter configurado. Os testes usam XCTest; o app só roda de fato em macOS (frameworks Speech/AVFoundation/AppKit) e requer permissões de Microfone e Reconhecimento de Fala concedidas ao terminal na primeira execução.

## Configuração em runtime

- `config.json` na raiz (gitignored; modelo em `config.example.json`) ou `~/.config/pynkaro/config.json`: `anthropic_api_key` é obrigatória; `openai_api_key` e `elevenlabs_api_key` são opcionais. Carregado por `Config.swift`; variáveis de ambiente `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`/`ELEVENLABS_API_KEY` são fallback.
- Env vars opcionais: `PYNKARO_MODEL`, `PYNKARO_CLAUDE_EFFORT`, `PYNKARO_TRANSCRIPTION_PROVIDER`, `OPENAI_TRANSCRIPTION_MODEL`, `PYNKARO_FINAL_SILENCE_MS`, `PYNKARO_WAKE_WORDS`, `PYNKARO_WEB_SEARCH=0`, `PYNKARO_TTS_PROVIDER`, `PYNKARO_VOICE`, `OPENAI_TTS_MODEL`, `OPENAI_TTS_VOICE`, `OPENAI_TTS_SPEED`, `OPENAI_TTS_INSTRUCTIONS`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL`.
- Imagens carregadas em runtime da raiz do projeto (ou `~/.config/pynkaro/`): `avatar.png` (obrigatória para exibir o avatar) e sprites de boca opcionais `avatar_mid.png`, `avatar_open.png`, `avatar_round.png`, `avatar_fv.png`.

## Arquitetura (Sources/Pynkaro/)

O centro é a máquina de estados em `VoiceAssistant.swift`: `waitingWakeWord → capturingQuestion → transcribing → thinking → speaking → waitingWakeWord`. Tudo converge para ela; os demais arquivos são satélites plugados por closures.

- `PynkaroApp.swift` — entrada do app (SwiftUI `@main`): `MenuBarExtra` cujo ícone reflete o estado, menu (pausar/retomar, sugestores, sair) e a janela dos sugestores de notícias (`@AppStorage` → UserDefaults, lidos pelo `ClaudeClient` a cada pergunta). `AppDelegate` define `.accessory` (sem Dock) e inicia o assistente.
- `AssistantController.swift` — `ObservableObject` singleton que faz a ponte VoiceAssistant → SwiftUI (`AssistantStatus` com símbolo e rótulo por estado; `pause()`/`resume()`).
- `SpeechRecognizer.swift` — AVAudioEngine + SFSpeechRecognizer pt-BR, usado para a wake word e para transcrever o M4A como fallback (on-device quando disponível). Emite parciais da wake word via `onPartial`; sessões expiram em ~1 min, então `VoiceAssistant` reinicia a escuta a cada 45s e após erros. Um contador `generation` invalida callbacks antigos.
- `QuestionRecorder.swift` — AVAudioRecorder em M4A mono, com medição de volume. Dá 6s para a fala começar, encerra após `PYNKARO_FINAL_SILENCE_MS` (padrão 1200ms, faixa 300–5000ms) e limita cada pergunta a 60s. O usuário precisa pausar depois da wake word.
- `OpenAITranscriptionClient.swift` — `PYNKARO_TRANSCRIPTION_PROVIDER=auto|openai|macos` decide a rota. Quando selecionada e há chave, envia o M4A como multipart para `/v1/audio/transcriptions`, usando `OPENAI_TRANSCRIPTION_MODEL` (padrão `gpt-4o-transcribe`), `language=pt` e resposta JSON. Ausência ou falha da OpenAI aciona o fallback do Speech framework sem pedir nova gravação; temporários são apagados em todos os caminhos.
- `ClaudeClient.swift` — Messages API da Anthropic com histórico (máx. 20 mensagens), `PYNKARO_CLAUDE_EFFORT` para Sonnet 5/Opus 5 e ferramenta server-side `web_search` (max_uses 3). Haiku 4.5 ignora effort por não suportá-lo. O system prompt é recomputado a cada chamada para injetar data/hora locais e inclui: persona bem-humorada, limite estrito de 1 frase, "modo opinião" (perguntas iniciadas com "Na sua opinião" → resposta cômica sem busca) e a resposta fixa sobre quem sugeriu as notícias. Respostas com busca vêm em múltiplos blocos: concatenar apenas os blocos `type == "text"`.
- `Speaker.swift` — define o protocolo `Speaking` (speak + callback `onMouthLevel`) e a implementação com AVSpeechSynthesizer (escolhe a melhor voz pt-BR masculina instalada). Boca animada por evento de palavra (`willSpeakRangeOfSpeechString`).
- `SpeakerRouter.swift` — escolhe o TTS a cada resposta por `PYNKARO_TTS_PROVIDER`: sem a variável preserva ElevenLabs→macOS; `auto` usa OpenAI→ElevenLabs→macOS; provedores explícitos nunca fazem fallback para outro serviço pago.
- `OpenAISpeechClient.swift` — envia o texto para `/v1/audio/speech` com WAV, `OPENAI_TTS_MODEL` (padrão `gpt-4o-mini-tts`), voz, velocidade e instruções configuráveis. Reproduz após baixar o áudio completo, anima a boca por amplitude e usa o macOS em qualquer falha.
- `ElevenLabsSpeaker.swift` — implementação TTS da ElevenLabs. Usa o endpoint `with-timestamps` (JSON com `audio_base64` + alignment por caractere) e constrói uma timeline de visemas (mapa caractere→nível de boca 0-4); um timer 60fps segue `player.currentTime`. Degradação em camadas: sem alignment → medição de amplitude (`averagePower`); falha da API → fallback para `Speaker` (voz do sistema).
- `AvatarWindow.swift` — janela borderless/transparente/flutuante no canto inferior direito, que ignora cliques. Dois renderizadores, decididos na inicialização: rig Rive (`avatar.riv`, boca via input numérico "mouth" 0-4 do state machine "State Machine 1"; RiveRuntime via SPM) ou sprites PNG. Entrada animada: a *janela fica fixa* e a view (Rive ou NSImageView) sobe dentro de um container com `masksToBounds` (animar frame de NSWindow via animator não respeita NSAnimationContext — não "consertar" voltando a animar a janela). `setMouth(_:)` envia ao Rive ou troca sprites com cadeias de fallback por nível.
- A escuta é **pausada durante a fala** (para o assistente não se ouvir) e retomada no completion do `speak`.

## Convenções

- Idioma do código/comentários/mensagens de terminal: português brasileiro.
- Concorrência por GCD/closures (`DispatchQueue.main`) — não migrar para async/await sem pedido explícito.
- Um único alvo executável; única dependência externa: RiveRuntime (rig do avatar). Rede via URLSession + JSONSerialization.
