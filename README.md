# Pynkaro — assistente de voz local para macOS

Protótipo de linha de comando. Fica ouvindo o microfone; ao ouvir **"Píncaro"**, grava a pergunta, transcreve pelo macOS ou pela OpenAI, envia o texto para o Claude e fala a resposta.

## Privacidade

- Wake word: **Speech framework da Apple, on-device** (se o idioma pt-BR estiver baixado — veja abaixo).
- Transcrição da pergunta: **Speech framework do macOS** por padrão. Com uma chave OpenAI configurada, `PYNKARO_TRANSCRIPTION_PROVIDER=auto` usa `OPENAI_TRANSCRIPTION_MODEL` (padrão `gpt-4o-transcribe`); se a API falhar, retorna automaticamente ao macOS. Use `macos` para nunca enviar a gravação.
- O áudio do microfone só sai do Mac quando a transcrição OpenAI está selecionada. O arquivo temporário é apagado após qualquer tentativa.
- Voz: **AVSpeechSynthesizer**, local, ou opcionalmente OpenAI/ElevenLabs. Os provedores de nuvem recebem apenas o texto da resposta; a voz OpenAI é gerada por IA, não por uma pessoa.
- O texto da pergunta é enviado para `api.anthropic.com` para gerar a resposta.

## Requisitos

- macOS 13+ (Apple Silicon recomendado), Xcode ou Command Line Tools instalados.
- Chave de API da Anthropic (https://console.anthropic.com).
- Chave de API da OpenAI opcional (https://platform.openai.com/api-keys).
- Para wake word e fallback de transcrição on-device: em **Ajustes do Sistema > Teclado > Ditado**, ative o ditado e baixe Português (Brasil). O app avisa no início se o modo on-device está ativo; sem o idioma local, o Speech framework pode usar os servidores da Apple.

## Como rodar

1. Copie `config.example.json` para `config.json` e preencha as chaves (o arquivo está no `.gitignore`, não vai em commits):

```json
{
  "anthropic_api_key": "sk-ant-...",
  "openai_api_key": "",
  "elevenlabs_api_key": ""
}
```

Preencha somente os serviços desejados; os campos vazios mantêm os respectivos recursos no macOS. A mesma chave OpenAI pode ser usada independentemente para transcrição e voz.

> Ou configure os valores em .envrc e .env, melhor para desenvolvimento e debugging

2. Compile e rode (desenvolvimento):

> [!WARNING]
> Rodar no vscode pode produzir erro com exit code 134 sem permissão.

```bash
cd ~/Git/Pynkaro
swift run -c release
```

3. Ou monte o aplicativo de verdade (menu bar, sem terminal):

```bash
./make_app.sh          # gera Pynkaro.app e Pynkaro.dmg
```

Para abrir o Pynkaro.app do terminal

```bash
source .envrc # ou direnv allow se tiver o direnv instalado
./Pynkaro.app/Contents/MacOS/Pynkaro
```

Para distribuir, envie o `Pynkaro.dmg`: o usuário arrasta o app para Applications e, na primeira execução, uma janela de boas-vindas pede as chaves de API (somente Anthropic é obrigatória; OpenAI e ElevenLabs são opcionais), salvas no **Keychain**. Sem os serviços opcionais, transcrição e voz usam o macOS. Depois dá para editar as chaves em "Configurações…" no menu da orelha. O `config.json` continua funcionando como fallback para desenvolvimento.

**Atenção (Gatekeeper):** com a assinatura ad-hoc atual, o app só roda sem bloqueio no Mac em que foi compilado. Para outros Macs é preciso assinar com **Developer ID** e **notarizar** (conta Apple Developer, US$ 99/ano): `codesign --sign "Developer ID Application: ..." --options runtime`, depois `xcrun notarytool submit` e `xcrun stapler staple`.

O app vive na **menu bar** (sem ícone no Dock): o ícone muda com o estado (ouvindo/pensando/falando), e o menu permite pausar/retomar a escuta, definir os sugestores de notícias e sair. Rodando como .app, o config.json é lido de `~/.config/pynkaro/` e o avatar vem embutido no bundle.

O `config.json` é procurado no diretório atual e depois em `~/.config/pynkaro/config.json`. As variáveis de ambiente `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`/`ELEVENLABS_API_KEY` funcionam como fallback para campos vazios.

Na primeira execução o macOS pedirá permissão de **Microfone** e **Reconhecimento de Fala** para o Terminal. Se os diálogos não aparecerem, habilite manualmente em Ajustes do Sistema > Privacidade e Segurança.

## Uso

1. Aguarde `👂 Aguardando "Píncaro"...`
2. Diga **"Píncaro"**, aguarde `🎤 Pode falar...` e então faça a pergunta. A pausa é necessária para trocar do reconhecedor local para o gravador.
3. Ele transcreve pelo macOS ou, se configurada, pela OpenAI; depois consulta o Claude e responde em voz alta.
4. O histórico da conversa é mantido durante a sessão.

## Configuração

Chaves de API: no `config.json` (ver "Como rodar"). Demais ajustes, por variável de ambiente:

`openai_api_key`/`OPENAI_API_KEY` é opcional e pode atender tanto transcrição quanto voz. As duas rotas são configuradas separadamente; ausência de chave ou erro da API ativa o fallback automático do macOS.

| Variável                         | Padrão                                            | Descrição                                                                                           |
| -------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `PYNKARO_MODEL`                  | `claude-sonnet-5`                                 | modelo da API Anthropic                                                                             |
| `PYNKARO_CLAUDE_EFFORT`          | padrão da API                                     | Sonnet/Opus: `low`, `medium`, `high`, `xhigh`, `max`; Haiku não suporta effort                      |
| `PYNKARO_TRANSCRIPTION_PROVIDER` | `auto`                                            | `auto`, `openai` ou `macos`; `macos` impede o envio da gravação à OpenAI                            |
| `OPENAI_TRANSCRIPTION_MODEL`     | `gpt-4o-transcribe`                               | use `gpt-4o-mini-transcribe` para priorizar custo e potencialmente menor latência                   |
| `PYNKARO_FINAL_SILENCE_MS`       | `1200`                                            | silêncio final em ms; aceita de `300` a `5000` (`1800` tolera pausas mais longas)                   |
| `PYNKARO_TTS_PROVIDER`           | legado                                            | ausente: ElevenLabs→macOS; aceita `openai`, `elevenlabs`, `system` ou `auto`                        |
| `PYNKARO_VOICE`                  | melhor voz masculina pt-BR instalada              | nome da voz do sistema (ex.: `Felipe (Aprimorada)`)                                                 |
| `OPENAI_TTS_MODEL`               | `gpt-4o-mini-tts`                                 | `tts-1` prioriza latência; `tts-1-hd` prioriza qualidade                                            |
| `OPENAI_TTS_VOICE`               | `onyx`                                            | voz OpenAI; `marin` e `cedar` são recomendadas para qualidade com o modelo GPT                      |
| `OPENAI_TTS_SPEED`               | `1.0`                                             | velocidade entre `0.25` e `4.0`; valores inválidos retornam ao padrão                               |
| `OPENAI_TTS_INSTRUCTIONS`        | instrução pt-BR do Pynkaro                        | tom, sotaque e ritmo; enviado somente a modelos `gpt-4o-mini-tts`                                   |
| `ELEVENLABS_VOICE_ID`            | `9yzdeviXkFddZ4Oz8Mok` (Lutz, masculina, risonha) | voz da ElevenLabs — a Lutz vem da Voice Library: adicione-a em My Voices na sua conta antes de usar |
| `ELEVENLABS_MODEL`               | `eleven_multilingual_v2`                          | use `eleven_flash_v2_5` para menor latência                                                         |
| `PYNKARO_WEB_SEARCH`             | `1` (ligada)                                      | `0` desativa a busca na web                                                                         |
| `PYNKARO_WAKE_WORDS`             | `pincaro,icaro`                                   | wake words em CSV; espaços, acentos e maiúsculas são ignorados                                      |
| `PYNKARO_VERBOSE`                | `0`                                               | `1` imprime as parciais usadas pelo macOS para detectar a wake word                                 |

### Voz do Pynkaro

No plano free da ElevenLabs so é possível usar vozes que você criar via API, abaixo um prompt que cria a voz do Pynkaro

```txt
A young adult Brazilian Portuguese male voice, around 25 to 35 years old, with a neutral Brazilian accent. Medium to slightly high pitch, bright and clear timbre, smooth tone, crisp articulation, and natural Brazilian Portuguese pronunciation.

The delivery is conversational, friendly, intelligent, energetic, and lightly playful. He speaks at a moderately fast pace with short natural pauses and expressive but controlled intonation. The voice should sound spontaneous and approachable, like a clever technology assistant speaking directly to one person.

Avoid a deep or booming voice, radio-announcer delivery, theatrical acting, excessive enthusiasm, breathiness, sensuality, childishness, robotic rhythm, and strongly regional accents. Keep the result natural, modern, concise, and responsive.
```

### Avatar na tela

Salve a imagem do assistente como `avatar.png` na raiz do projeto (ou em `~/.config/pynkaro/avatar.png`) — PNG com fundo transparente fica melhor. O avatar aparece com fade no canto inferior direito quando a wake word é detectada e some quando a resposta termina. A janela flutua acima das outras, não rouba o foco e deixa os cliques passarem. Sem o arquivo, o app apenas avisa e segue sem avatar.

**Boca animada (lip sync):** com a voz da ElevenLabs, o app usa o endpoint `with-timestamps`, que devolve o áudio junto com o instante exato de cada caractere. As letras viram formatos de boca sincronizados: a → aberta, e/i e consoantes → entreaberta, o/u → arredondada, m/b/p → fechada, f/v → lábio-dental; pausas fecham a boca. Com OpenAI, a boca acompanha a amplitude do WAV; com a voz do sistema, acompanha o ritmo das palavras. Sprites, na mesma pasta e dimensões do avatar.png: `avatar_mid.png` (entreaberta) e `avatar_open.png` (aberta) são os essenciais; `avatar_round.png` (o/u) e `avatar_fv.png` (f/v) são opcionais — sem eles, o app usa o sprite mais próximo. Sem sprites extras, o avatar fica estático (sem erro).

### Avatar com rig 2D (Rive)

Alternativa aos sprites: um rig animado feito no [editor da Rive](https://rive.app). Se existir `avatar.riv` na raiz do projeto (ou `~/.config/pynkaro/`), ele é usado no lugar dos PNGs. O app envia o nível de boca (0 a 4) a um input numérico do state machine — animações de idle (piscar, respirar) rodam por conta do próprio rig.

Contrato esperado no arquivo .riv (nomes configuráveis por env):

| Elemento               | Nome padrão                                                | Env var                      |
| ---------------------- | ---------------------------------------------------------- | ---------------------------- |
| State machine          | `State Machine 1`                                          | `PYNKARO_RIVE_STATE_MACHINE` |
| Input numérico da boca | `mouth` (0=fechada, 1=entreaberta, 2=aberta, 3=o/u, 4=f/v) | `PYNKARO_RIVE_INPUT`         |

### Busca na web

O app habilita a ferramenta de busca da própria API da Anthropic (`web_search`): o Claude decide quando pesquisar e responde com dados atuais (notícias, cotações, clima etc.). A busca roda nos servidores da Anthropic — nada muda no app. Custo: US$ 10 por 1.000 buscas, além dos tokens; limitado a 3 buscas por pergunta (`max_uses`). Perguntas que exigem busca demoram alguns segundos a mais.

### Voz ElevenLabs

Com `ELEVENLABS_API_KEY` definida e o provedor correspondente selecionado, a resposta é sintetizada na nuvem da ElevenLabs. Apenas o **texto** da resposta é enviado à ElevenLabs. O áudio do microfone só é enviado à OpenAI quando a transcrição OpenAI está selecionada. Se qualquer serviço opcional falhar, o app retorna ao recurso correspondente do macOS.

Para escolher outra voz, veja as suas em https://elevenlabs.io/app/voice-lab ou liste via API:

```bash
curl -s https://api.elevenlabs.io/v1/voices -H "xi-api-key: $ELEVENLABS_API_KEY" | python3 -c "import json,sys; [print(v['voice_id'], '-', v['name']) for v in json.load(sys.stdin)['voices']]"
```

### Voz OpenAI

Defina `PYNKARO_TTS_PROVIDER=openai` para enviar o texto da resposta ao endpoint `/v1/audio/speech`. O padrão `gpt-4o-mini-tts` permite controlar sotaque, emoção, tom e ritmo por `OPENAI_TTS_INSTRUCTIONS`; `tts-1` reduz a latência com menor qualidade e `tts-1-hd` prioriza qualidade. O app solicita WAV, reproduz o áudio somente depois do download completo e usa a voz do macOS se a API ou a reprodução falhar. Consulte o [guia oficial de text-to-speech](https://developers.openai.com/api/docs/guides/text-to-speech) para ouvir as vozes disponíveis.

Use `PYNKARO_TRANSCRIPTION_PROVIDER=macos` se quiser usar `OPENAI_API_KEY` apenas para voz. Conforme a política da OpenAI, usuários devem ser informados de que a voz é gerada por IA e não é uma voz humana.

Ajustes no código: wake words em `VoiceAssistant.swift`, limites de silêncio em `QuestionRecorder.swift` e prompt de sistema em `ClaudeClient.swift`.

## Arquitetura

```
main.swift            → entrada, run loop
VoiceAssistant.swift  → máquina de estados e coordenação do fluxo
SpeechRecognizer.swift→ wake word e fallback de arquivo via SFSpeechRecognizer
QuestionRecorder.swift→ gravação M4A + detecção de silêncio por volume
OpenAITranscriptionClient.swift → transcrição remota opcional via multipart
ClaudeClient.swift    → Messages API da Anthropic, com histórico
Speaker.swift         → AVSpeechSynthesizer (voz pt-BR)
SpeakerRouter.swift   → seleção modular do provedor de voz
OpenAISpeechClient.swift → geração e reprodução opcional de voz OpenAI
ElevenLabsSpeaker.swift → voz ElevenLabs com timestamps/visemas
```

Detalhes de implementação: a sessão local da wake word é reiniciada a cada 45 s (limite de ~1 min do SFSpeechRecognizer); depois da ativação há até 6 s para começar a pergunta, que termina após `PYNKARO_FINAL_SILENCE_MS` (padrão 1,2 s) de silêncio ou 60 s no total. A escuta é pausada enquanto o assistente fala, para não ouvir a si mesmo.

## Limitações do protótipo / próximos passos

- Roda no terminal; o próximo passo natural é um app de menu bar (SwiftUI) com ícone de estado.
- Wake word via transcrição contínua funciona, mas consome mais CPU que um detector dedicado (ex.: Porcupine).
- Sem streaming: a fala começa só quando a resposta completa chega. Streaming da API + fala por sentenças reduziria a latência.
- Não dá para interromper a resposta falada (adicionar "Pynkaro, para").
