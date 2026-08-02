# Pynkaro — assistente de voz local para macOS

Protótipo de linha de comando. Fica ouvindo o microfone; ao ouvir **"Píncaro"**, grava a pergunta, transcreve com a OpenAI, envia o texto para o Claude e fala a resposta.

## Privacidade

- Wake word: **Speech framework da Apple, on-device** (se o idioma pt-BR estiver baixado — veja abaixo).
- Transcrição da pergunta: **OpenAI** (`gpt-4o-transcribe`); o arquivo de áudio temporário é enviado à API e apagado depois da resposta.
- Voz: **AVSpeechSynthesizer**, local.
- O texto da pergunta é enviado para `api.anthropic.com`; com ElevenLabs, o texto da resposta também é enviado para síntese de voz.

## Requisitos

- macOS 13+ (Apple Silicon recomendado), Xcode ou Command Line Tools instalados.
- Chave de API da Anthropic (https://console.anthropic.com).
- Chave de API da OpenAI (https://platform.openai.com/api-keys).
- Para detecção local da wake word: em **Ajustes do Sistema > Teclado > Ditado**, ative o ditado e baixe Português (Brasil). O app avisa no início se o modo on-device está ativo.

## Como rodar

1. Copie `config.example.json` para `config.json` e preencha as chaves (o arquivo está no `.gitignore`, não vai em commits):

```json
{
  "anthropic_api_key": "sk-ant-...",
  "openai_api_key": "sk-...",
  "elevenlabs_api_key": "..."
}
```

> Ou configure os valores em .envrc e .env, melhor para desenvolvimento e debugging

2. Compile e rode (desenvolvimento):

> [!WARNING] Rodar no vscode pode produzir erro com exit code 134 sem permissão.

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

Para distribuir, envie o `Pynkaro.dmg`: o usuário arrasta o app para Applications e, na primeira execução, uma janela de boas-vindas pede as chaves de API (Anthropic e OpenAI obrigatórias; ElevenLabs opcional — sem ela, voz do sistema), salvas no **Keychain**. Depois dá para editá-las em "Configurações…" no menu da orelha. O `config.json` continua funcionando como fallback para desenvolvimento.

**Atenção (Gatekeeper):** com a assinatura ad-hoc atual, o app só roda sem bloqueio no Mac em que foi compilado. Para outros Macs é preciso assinar com **Developer ID** e **notarizar** (conta Apple Developer, US$ 99/ano): `codesign --sign "Developer ID Application: ..." --options runtime`, depois `xcrun notarytool submit` e `xcrun stapler staple`.

O app vive na **menu bar** (sem ícone no Dock): o ícone muda com o estado (ouvindo/pensando/falando), e o menu permite pausar/retomar a escuta, definir os sugestores de notícias e sair. Rodando como .app, o config.json é lido de `~/.config/pynkaro/` e o avatar vem embutido no bundle.

O `config.json` é procurado no diretório atual e depois em `~/.config/pynkaro/config.json`. As variáveis de ambiente `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`/`ELEVENLABS_API_KEY` funcionam como fallback para campos vazios.

Na primeira execução o macOS pedirá permissão de **Microfone** e **Reconhecimento de Fala** para o Terminal. Se os diálogos não aparecerem, habilite manualmente em Ajustes do Sistema > Privacidade e Segurança.

## Uso

1. Aguarde `👂 Aguardando "Píncaro"...`
2. Diga **"Píncaro"**, aguarde `🎤 Pode falar...` e então faça a pergunta. A pausa é necessária para trocar do reconhecedor local para o gravador.
3. Ele envia o áudio da pergunta à OpenAI, consulta o Claude com a transcrição e responde em voz alta.
4. O histórico da conversa é mantido durante a sessão.

## Configuração

Chaves de API: no `config.json` (ver "Como rodar"). Demais ajustes, por variável de ambiente:

| Variável              | Padrão                                            | Descrição                                                                                           |
| --------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `PYNKARO_MODEL`       | `claude-sonnet-5`                                 | modelo da API Anthropic                                                                             |
| `PYNKARO_VOICE`       | melhor voz masculina pt-BR instalada              | nome da voz do sistema (ex.: `Felipe (Aprimorada)`)                                                 |
| `ELEVENLABS_VOICE_ID` | `9yzdeviXkFddZ4Oz8Mok` (Lutz, masculina, risonha) | voz da ElevenLabs — a Lutz vem da Voice Library: adicione-a em My Voices na sua conta antes de usar |
| `ELEVENLABS_MODEL`    | `eleven_multilingual_v2`                          | use `eleven_flash_v2_5` para menor latência                                                         |
| `PYNKARO_WEB_SEARCH`  | `1` (ligada)                                      | `0` desativa a busca na web                                                                         |
| `PYNKARO_WAKE_WORDS`  | `pincaro,icaro`                                   | wake words em CSV; espaços, acentos e maiúsculas são ignorados                                      |
| `PYNKARO_VERBOSE`     | `0`                                               | `1` imprime as parciais usadas pelo macOS para detectar a wake word                                  |

### Avatar na tela

Salve a imagem do assistente como `avatar.png` na raiz do projeto (ou em `~/.config/pynkaro/avatar.png`) — PNG com fundo transparente fica melhor. O avatar aparece com fade no canto inferior direito quando a wake word é detectada e some quando a resposta termina. A janela flutua acima das outras, não rouba o foco e deixa os cliques passarem. Sem o arquivo, o app apenas avisa e segue sem avatar.

**Boca animada (lip sync por visemas):** com a voz da ElevenLabs, o app usa o endpoint `with-timestamps`, que devolve o áudio junto com o instante exato de cada caractere. As letras viram formatos de boca sincronizados: a → aberta, e/i e consoantes → entreaberta, o/u → arredondada, m/b/p → fechada, f/v → lábio-dental; pausas fecham a boca. Sprites, na mesma pasta e dimensões do avatar.png: `avatar_mid.png` (entreaberta) e `avatar_open.png` (aberta) são os essenciais; `avatar_round.png` (o/u) e `avatar_fv.png` (f/v) são opcionais — sem eles, o app usa o sprite mais próximo. Se a resposta vier sem timestamps, cai automaticamente no modo por amplitude (volume); com a voz do sistema, a boca segue o ritmo das palavras. Sem sprites extras, o avatar fica estático (sem erro). Dica: gere as variações com um editor de imagens por IA pedindo "mesma imagem, apenas boca X".

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

Com `ELEVENLABS_API_KEY` definida, a resposta é sintetizada na nuvem da ElevenLabs (voz neural, muito mais natural). Apenas o **texto** da resposta é enviado à ElevenLabs; o áudio do microfone é enviado somente à OpenAI para transcrição. Se a API de voz falhar, o app usa a voz do sistema como fallback.

Para escolher outra voz, veja as suas em https://elevenlabs.io/app/voice-lab ou liste via API:

```bash
curl -s https://api.elevenlabs.io/v1/voices -H "xi-api-key: $ELEVENLABS_API_KEY" | python3 -c "import json,sys; [print(v['voice_id'], '-', v['name']) for v in json.load(sys.stdin)['voices']]"
```

Ajustes no código: wake word em `VoiceAssistant.swift` (`wakeWord`), tempo de silêncio para encerrar a pergunta (`armSilenceTimer`, 1,8 s), prompt de sistema em `ClaudeClient.swift`.

## Arquitetura

```
main.swift            → entrada, run loop
VoiceAssistant.swift  → máquina de estados e coordenação do fluxo
SpeechRecognizer.swift→ wake word via SFSpeechRecognizer (pt-BR, on-device)
QuestionRecorder.swift→ gravação M4A + detecção de silêncio por volume
OpenAITranscriptionClient.swift → envio multipart e transcrição da pergunta
ClaudeClient.swift    → Messages API da Anthropic, com histórico
Speaker.swift         → AVSpeechSynthesizer (voz pt-BR)
```

Detalhes de implementação: a sessão local da wake word é reiniciada a cada 45 s (limite de ~1 min do SFSpeechRecognizer); depois da ativação há até 6 s para começar a pergunta, que termina após 1,8 s de silêncio ou 60 s no total. A escuta é pausada enquanto o assistente fala, para não ouvir a si mesmo.

## Limitações do protótipo / próximos passos

- Roda no terminal; o próximo passo natural é um app de menu bar (SwiftUI) com ícone de estado.
- Wake word via transcrição contínua funciona, mas consome mais CPU que um detector dedicado (ex.: Porcupine).
- Sem streaming: a fala começa só quando a resposta completa chega. Streaming da API + fala por sentenças reduziria a latência.
- Não dá para interromper a resposta falada (adicionar "Pynkaro, para").
